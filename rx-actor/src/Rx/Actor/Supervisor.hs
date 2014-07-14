{-# LANGUAGE RecordWildCards #-}
module Rx.Actor.Supervisor where

import Control.Concurrent (myThreadId, yield)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Concurrent.STM ( TChan, TVar, atomically
                              , newTVarIO, readTVar, modifyTVar
                              , newTChanIO, readTChan, writeTChan  )
import Control.Concurrent.Async (Async, async, cancel, link2, wait)

import Control.Exception (throwIO)

import Control.Monad (void, when, forever, forM_)
import Control.Monad.Free

import Data.Typeable (Typeable)
import Data.HashMap.Strict (HashMap)

import qualified Data.HashMap.Strict as HashMap

import Rx.Subject (Subject, newPublishSubject)
import Rx.Observable (safeSubscribe, toAsyncObservable, onNext)
import Rx.Disposable ( createDisposable, dispose
                     , newSingleAssignmentDisposable, toDisposable )
import qualified Rx.Disposable as Disposable

import Rx.Actor.EventBus (toGenericEvent)
import Rx.Actor.Actor
import Rx.Actor.Types

--------------------------------------------------------------------------------

startSupervisorWithEventBus :: EventBus -> SupervisorDef -> IO Supervisor
startSupervisorWithEventBus evBus supDef = _createSupervisor evBus supDef

startSupervisor :: SupervisorDef -> IO Supervisor
startSupervisor supDef = do
  evBus <- newPublishSubject
  startSupervisorWithEventBus evBus supDef

stopSupervisor :: Supervisor -> IO ()
stopSupervisor sup@(Supervisor {..}) = do
  stopChildren sup
  cancel _supervisorAsync

killSupervisor :: Supervisor -> IO ()
killSupervisor sup@(Supervisor {..}) = do
  disposeChildren sup
  cancel _supervisorAsync

onChildren :: (Actor -> IO b) -> Supervisor -> IO ()
onChildren onChildFn (Supervisor {..}) = do
  actorMap <- atomically $ readTVar _supervisorChildren
  mapM_ onChildFn (HashMap.elems actorMap)

stopChildren :: Supervisor -> IO ()
stopChildren    = onChildren (`_sendCtrlToActor` StopActorEvent)

disposeChildren :: Supervisor -> IO ()
disposeChildren = onChildren dispose

joinSupervisorThread :: Supervisor -> IO ()
joinSupervisorThread = wait . _supervisorAsync

_createSupervisor :: EventBus -> SupervisorDef -> IO Supervisor
_createSupervisor evBus supDef@(SupervisorDef {..}) = do
    ctrlQueue <- newTChanIO
    actorMapVar <- newTVarIO HashMap.empty
    main ctrlQueue actorMapVar
  where
    main ctrlQueue actorMapVar = do
        supVar <- newEmptyMVar
        supAsync <- async $ initSup supVar
        supDisposable <- newSingleAssignmentDisposable
        let sup =
              Supervisor {
                _supervisorDef = supDef
              , _supervisorAsync = supAsync
              , _supervisorEventBus = evBus
              , _supervisorDisposable = toDisposable $ supDisposable
              , _supervisorChildren = actorMapVar
              , _sendToSupervisor = supSend
              }

        innerDisposable <- createDisposable $ stopSupervisor sup
        Disposable.set innerDisposable supDisposable

        subAsync <- async $ initSub sup
        link2 supAsync subAsync
        putMVar supVar sup
        return sup
      where
        initSup supVar = do
          sup <- takeMVar supVar
          initChildrenThreads sup
          supLoop sup

        initSub sup =
          safeSubscribe (toAsyncObservable evBus)
                        emitEventToChildren
                        (\err -> supFail sup err Nothing)
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
            (ActorTerminated actor) -> supRemoveActor actor
            (ActorFailedOnInitialize err actor) -> supFail sup err $ Just actor
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
          wasRemoved <- atomically $ do
            actorMap <- readTVar actorMapVar
            case HashMap.lookup actorKey actorMap of
              Nothing -> return False
              Just actor -> do
                modifyTVar actorMapVar $ HashMap.delete actorKey
                return True
          when wasRemoved (logMsg $ "Supervisor: Removing actor " ++ actorKey)

        supFail sup err _ = do
          logMsg $ "Supervisor: Failing with error '" ++ show err ++ "'"
          disposeChildren sup
          throwIO err

        supStartActor sup gActorDef spawnInfo = do
          let actorKey = getActorKey gActorDef
          actor <- _spawnActor sup $ spawnInfo
          atomically
            $ modifyTVar actorMapVar
            $ HashMap.insertWith (\_ _ -> actor) actorKey actor

        supRestartActor sup prevSt failedEv err actor directive =
          case directive of
            Raise -> do
              logMsg $ "Supervisor: raise error from actor"
              supFail sup err actor
            RestartOne ->
              supRestartSingleActor actor sup prevSt failedEv err
            Restart ->
              let restarter =
                    case _supervisorStrategy of
                      OneForOne -> supRestartSingleActor
                      AllForOne -> supRestartAllActors
              in restarter actor sup prevSt failedEv err

        supRestartSingleActor actor sup prevSt failedEv err = do
          let gActorDef      = _actorDef actor
              backoffDelay   = _supervisorBackoffDelayFn restartAttempt
              restartAttempt = getRestartAttempts gActorDef

          gActorDef1 <- incRestartAttempt gActorDef
          supRemoveActor gActorDef
          logMsg $ "Supervisor: Restarting actor " ++ getActorKey gActorDef  ++
                   " with delay " ++ show backoffDelay
          supStartActor sup gActorDef
            $ RestartActor {
              _spawnPrevState    = prevSt
            , _spawnQueue        = _actorQueue actor
            , _spawnCtrlQueue    = _actorCtrlQueue actor
            , _spawnError        = err
            , _spawnFailedEvent  = failedEv
            , _spawnActorDef     = gActorDef1
            , _spawnDelay        = backoffDelay
            }

        supRestartAllActors failingActor sup prevSt failedEv err = do
          let failingActorKey = getActorKey failingActor
          children <- atomically $ readTVar actorMapVar
          -- TODO: Maybe do this in parallel
          supRestartSingleActor failingActor sup prevSt failedEv err
          forM_ (HashMap.elems children) $ \actor -> do
            let actorKey = getActorKey actor
            when (actorKey /= failingActorKey) $
              -- Actor will send back a message to supervisor to restart itself
              _sendCtrlToActor actor (RestartActorEvent err failedEv)


        logMsg msg = do
          tid <- myThreadId
          putStrLn $ "[" ++ show tid ++ "] " ++ msg

emitEventToSupervisor :: (Typeable t) => Supervisor -> t -> IO ()
emitEventToSupervisor sup ev =
  onNext (_supervisorEventBus sup)
            (toGenericEvent ev)
