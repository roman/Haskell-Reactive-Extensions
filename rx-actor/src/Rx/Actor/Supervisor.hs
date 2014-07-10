{-# LANGUAGE RecordWildCards #-}
module Rx.Actor.Supervisor where

import Control.Concurrent (myThreadId, yield)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Concurrent.STM ( TChan, TVar, atomically
                              , newTVarIO, readTVar, modifyTVar
                              , newTChanIO, readTChan, writeTChan  )
import Control.Concurrent.Async (Async, async, cancel, link2, wait)

import Control.Exception (throwIO)

import Control.Monad (void, forever)
import Control.Monad.Free

import Data.Typeable (Typeable)
import Data.HashMap.Strict (HashMap)

import qualified Data.HashMap.Strict as HashMap

import Rx.Subject (Subject, newPublishSubject)
import Rx.Observable (safeSubscribe, toAsyncObservable, onNext)
import Rx.Disposable ( createDisposable, dispose
                     , newSingleAssignmentDisposable, toDisposable )
import qualified Rx.Disposable as Disposable

import Rx.Actor.Actor
import Rx.Actor.Types

{-
defSupervisor $ do
  strategy OneForOne
  backoff $ \n -> seconds (n * 2)
  maxRestarts 5
  addChild actorDef1
  addChild actorDef2
-}


startSupervisorWithEventBus :: EventBus -> SupervisorDef -> IO Supervisor
startSupervisorWithEventBus evBus supDef = _createSupervisor evBus supDef

startSupervisor :: SupervisorDef -> IO Supervisor
startSupervisor supDef = do
  evBus <- newPublishSubject
  startSupervisorWithEventBus evBus supDef

stopSupervisor :: Supervisor -> IO ()
stopSupervisor = dispose

joinSupervisorThread :: Supervisor -> IO ()
joinSupervisorThread = _supervisorJoin

_createSupervisor :: EventBus -> SupervisorDef -> IO Supervisor
_createSupervisor evBus supDef@(SupervisorDef {..}) = do
    ctrlQueue <- newTChanIO
    actorMapVar <- newTVarIO HashMap.empty
    main ctrlQueue actorMapVar
  where
    main ctrlQueue actorMapVar = do
        supVar <- newEmptyMVar
        supAsync <- async $ initSup supVar
        subAsync <- async initSub
        supDisposable <- mkSupDisposable supAsync
        let sup =
              Supervisor {
                _supervisorDef = supDef
              , _supervisorEventBus = evBus
              , _supervisorDisposable = toDisposable $ supDisposable
              , _supervisorChildren = actorMapVar
              , _sendToSupervisor = supSend
              , _supervisorJoin = wait supAsync
              }
        link2 supAsync subAsync
        putMVar supVar sup
        return sup
      where
        initSup supVar = do
          sup <- takeMVar supVar
          initChildrenThreads sup
          supLoop sup

        initSub =
          safeSubscribe (toAsyncObservable evBus)
                        emitEventToChildren
                        (\err -> supFail err Nothing)
                        (return ())

        initChildrenThreads sup =
          mapM_ (supAddActor sup) _supervisorDefChildren

        emitEventToChildren gev = do
          actors <- HashMap.elems `fmap` (atomically $ readTVar actorMapVar)
          mapM_ (flip _sendToActor gev) actors

        supLoop sup = do
          ev <- atomically $ readTChan ctrlQueue
          case ev of
            (ActorSpawned gActorDef) -> supAddActor sup gActorDef
            (ActorTerminated gActorDef) -> supRemoveActor gActorDef
            (ActorTerminatedByKill gActorDef) -> supRemoveActor gActorDef
            (ActorFailedOnInitialize err actor) -> supFail err $ Just actor
            (ActorFailedWithError prevSt failedEv err actor directive) ->
              supRestartActor sup prevSt failedEv err actor directive
          yield
          logMsg "Supervisor: loop"
          supLoop sup

        supSend = atomically . writeTChan ctrlQueue

        supAddActor sup gActorDef = do
          let actorKey = getActorKey gActorDef
          logMsg $ "Supervisor: Starting new actor " ++ actorKey
          supStartActor sup gActorDef $ NewActor gActorDef

        supRemoveActor gActorDef = do
          let actorKey = getActorKey gActorDef
          actorMap <- atomically $ readTVar actorMapVar
          case HashMap.lookup actorKey actorMap of
            Nothing -> return ()
            Just actor -> do
              logMsg $ "Supervisor: Removing actor " ++ actorKey
              dispose actor
              atomically $ modifyTVar actorMapVar
                         $ HashMap.delete actorKey

        supFail err _ = do
          logMsg $ "Supervisor: Failing with error '" ++ show err ++ "'"
          disposeChildren
          throwIO err

        supStartActor sup gActorDef spawnInfo = do
          let actorKey = getActorKey gActorDef
          actor <- _spawnActor sup $ spawnInfo
          atomically
            $ modifyTVar actorMapVar
            $ HashMap.insertWith (\_ _ -> actor) actorKey actor

        supRestartActor sup prevSt failedEv err actor directive =
          let gActorDef = _actorDef actor
          in case directive of
            Raise   -> do
              logMsg $ "Supervisor: raise error from actor"
              supFail err actor
            Restart -> do
              let restartAttempt = getRestartAttempts gActorDef
                  restartDelay = _supervisorBackoffDelayFn restartAttempt

              gActorDef1 <- incRestartAttempt gActorDef
              supRemoveActor gActorDef
              logMsg $ "Supervisor: Restarting actor " ++ getActorKey gActorDef  ++
                       " with delay " ++ show restartDelay
              supStartActor sup gActorDef
                $ RestartActor {
                  _spawnPrevState    = prevSt
                , _spawnQueue       = _actorQueue actor
                , _spawnError        = err
                , _spawnFailedEvent  = failedEv
                , _spawnActorDef     = gActorDef1
                , _spawnDelay        = restartDelay
                }

        mkSupDisposable supAsync = createDisposable $ do
          logMsg "Supervisor: Disposing"
          cancel supAsync
          disposeChildren

        disposeChildren = do
          actorMap <- atomically $ readTVar actorMapVar
          mapM_ dispose $ HashMap.elems actorMap

        logMsg msg = do
          tid <- myThreadId
          putStrLn $ "[" ++ show tid ++ "] " ++ msg

emitEvent :: Typeable t => Supervisor -> t -> IO ()
emitEvent sup ev = onNext (_supervisorEventBus sup)
                          (toGenericEvent ev)
