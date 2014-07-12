{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ExistentialQuantification #-}
module Rx.Actor.Actor where

import Control.Monad (void, when)
import Control.Monad.Trans (liftIO)
import Control.Monad.State.Strict (execStateT)

import Control.Exception (SomeException(..), fromException, try, throwIO)
import Control.Concurrent (forkIO, killThread, myThreadId, yield)
import Control.Concurrent.MVar (newEmptyMVar, takeMVar, putMVar)
import Control.Concurrent.STM (atomically, newTChanIO, readTChan, writeTChan)

import Data.Maybe (fromMaybe, fromJust)
import Data.Typeable (typeOf)

import qualified Data.HashMap.Strict as HashMap

import Tiempo.Concurrent (threadDelay)

import Rx.Disposable (createDisposable)

import Unsafe.Coerce (unsafeCoerce)

import Rx.Observable (toSyncObservable, safeSubscribe, scanLeftWithItem)
import Rx.Disposable ( emptyDisposable
                     , newCompositeDisposable, newSingleAssignmentDisposable
                     , toDisposable )
import qualified Rx.Disposable as Disposable

import Rx.Actor.EventBus (fromGenericEvent, typeOfEvent)
import Rx.Actor.Util (logError, logError_)
import Rx.Actor.Types

--------------------------------------------------------------------------------

_spawnActor :: Supervisor -> SpawnInfo -> IO Actor
_spawnActor (Supervisor {..}) spawn = do
    actorEvQueue <- createActorQueue spawn
    main (_spawnActorDef spawn) actorEvQueue
  where
    main gActorDef@(GenericActorDef actorDef) actorEvQueue = do
        actorDisposable <- newCompositeDisposable
        subDisposable <- newSingleAssignmentDisposable

        actorVar <- newEmptyMVar
        actorTid <- _actorForker actorDef $ initActor actorVar subDisposable

        threadDisposable <- createDisposable $ do
          logMsg $ "Disposable called"
          killThread actorTid

        Disposable.append threadDisposable actorDisposable
        Disposable.append subDisposable actorDisposable

        let actor = Actor {
            _sendToActor            = atomically . writeTChan actorEvQueue
          , _actorQueue             = actorEvQueue
          , _actorCleanup           = toDisposable $ actorDisposable
          , _actorDef               = gActorDef
          , _actorEventBus          = _supervisorEventBus
          }

        putMVar actorVar actor
        return actor
      where
        actorObservable actor st =
          scanLeftWithItem (actorLoop actor) st $
          _actorEventBusDecorator actorDef $
          toSyncObservable actorEvQueue

        initActor actorVar subDisposable = do
          actor <- takeMVar actorVar
          disposable <-
            case spawn of
              (RestartActor _ st' err gev _ delay) -> do
                threadDelay delay
                restartActor actor (unsafeCoerce st') err gev
              (NewActor {}) -> newActor actor

          Disposable.set disposable subDisposable


        newActor actor = do
          result <- _actorPreStart actorDef
          threadDelay $ _actorDelayAfterStart actorDef
          case result of
            InitFailure err -> do
              _sendToSupervisor
                $ ActorFailedOnInitialize {
                  _supEvTerminatedError = err
                , _supEvTerminatedActor = actor
                }
              emptyDisposable
            InitOk st ->
              safeSubscribe (actorObservable actor st)
                            (const $ return ()) -- log events here
                            (const $ return ())
                            (return ())


        restartActor actor oldSt err gev = do
          result <- logError $ _actorPostRestart actorDef oldSt err gev
          case result of
            Nothing ->
              -- TODO: Do a warning with the error
              safeSubscribe (actorObservable actor oldSt)
                            (const $ return ()) -- log events here
                            (const $ return ()) -- log events on error
                            (return ())
            Just (InitOk newSt) ->
              safeSubscribe (actorObservable actor newSt)
                            (const $ return ()) -- log events here
                            (const $ return ()) -- log events on error
                            (return ())

            Just (InitFailure initErr) -> do
              _sendToSupervisor
                $ ActorFailedOnInitialize {
                  _supEvTerminatedError = initErr
                , _supEvTerminatedActor = actor
                }
              emptyDisposable

        actorLoop actor st gev = do
          let handlers = _actorReceive actorDef
              evType = show $ typeOfEvent gev

          case HashMap.lookup evType handlers of
            Nothing -> return st
            Just (EventHandler _ handler) -> do
              logMsg $ "[type: " ++ evType ++ "] Handling event"
              result <- try $ execStateT (fromActorM . handler
                                           $ fromJust $ fromGenericEvent gev)
                                         (st, _supervisorEventBus)
              case result of
                Left err  -> handleActorError actor err st gev
                Right (st', _) -> return st'

        handleActorError actor err@(SomeException innerErr) st gev = do
          putStrLn $ "Received error on " ++ getActorKey gActorDef ++ ": " ++ show err
          let errType = show $ typeOf innerErr
              restartDirectives = _actorRestartDirective actorDef
          case HashMap.lookup errType restartDirectives of
            Nothing ->
              sendErrorToSupervisor Restart actor err st gev
            Just (ErrorHandler errHandler) -> do
              restartDirective <- errHandler (fromJust $ fromException err) st
              case restartDirective of
                Stop -> do
                  logMsg $ "[error: " ++ show err ++ "] Stop actor"
                  _actorPostStop actorDef
                  throwIO err
                Resume -> do
                  logMsg $ "[error: " ++ show err ++ "] Resume actor"
                  return st
                _ -> do
                  logMsg $ "[error: " ++ show err ++ "] Send message to supervisor actor"
                  sendErrorToSupervisor restartDirective actor err st gev


        sendErrorToSupervisor restartDirective actor err st gev = do
          when (restartDirective == Restart)
            $ logError_ $ _actorPreRestart actorDef st err gev
          logMsg "Notify supervisor to restart actor"
          _sendToSupervisor
                  $ ActorFailedWithError {
                    _supEvTerminatedState = st
                  , _supEvTerminatedFailedEvent = gev
                  , _supEvTerminatedError = err
                  , _supEvTerminatedActor = actor
                  , _supEvTerminatedDirective = restartDirective
                  }
          throwIO err

        logMsg msg = do
          let sep = case msg of
                      ('[':_) -> ""
                      (' ':_) -> ""
                      _ -> " "
          tid <- myThreadId
          putStrLn $
            "[" ++ show tid ++ "][actorKey:" ++ getActorKey gActorDef ++ "]" ++
            sep ++ msg
