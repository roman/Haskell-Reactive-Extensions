{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
module Rx.Actor.Actor where

import Control.Applicative ((<$>))

import Control.Monad (void)
import Control.Monad.State.Strict (execStateT)

import Control.Exception (SomeException(..), fromException, try, throwIO)
import Control.Concurrent (killThread)
import Control.Concurrent.MVar (newEmptyMVar, takeMVar, putMVar)
import Control.Concurrent.STM (atomically, orElse, readTChan, writeTChan)

import Data.Maybe (fromMaybe, fromJust)
import Data.Typeable (typeOf)

import qualified Data.HashMap.Strict as HashMap

import Tiempo.Concurrent (threadDelay)


import Unsafe.Coerce (unsafeCoerce)

import Rx.Observable ( safeSubscribe, scanLeftWithItem )
import Rx.Disposable ( emptyDisposable, createDisposable
                     , newCompositeDisposable, newSingleAssignmentDisposable
                     , toDisposable )
import Rx.Logger (trace, noisyF, noisy, loudF, Only(..))

import qualified Rx.Observable as Observable
import qualified Rx.Disposable as Disposable

import Rx.Actor.Monad (execActorM, runActorM, runPreActorM)
import Rx.Actor.EventBus (fromGenericEvent, typeOfEvent)
import Rx.Actor.Util (logError, logError_)
import Rx.Actor.Types

--------------------------------------------------------------------------------

_spawnActor :: Supervisor -> SpawnInfo -> IO Actor
_spawnActor (Supervisor {..}) spawn = do
    (actorEvQueue, actorCtrlQueue) <- createActorQueues spawn
    main (_spawnActorDef spawn) _supervisorLogger actorEvQueue actorCtrlQueue
  where
    main gActorDef@(GenericActorDef actorDef) logger actorEvQueue actorCtrlQueue = do
        actorDisposable <- newCompositeDisposable
        subDisposable <- newSingleAssignmentDisposable

        actorVar <- newEmptyMVar
        actorTid <- _actorForker actorDef $ initActor actorVar subDisposable

        threadDisposable <- createDisposable $ do
          loudF "[actorKey: {}] actor disposable called"
                (Only $ getActorKey actorDef)
                logger
          killThread actorTid

        Disposable.append threadDisposable actorDisposable
        Disposable.append subDisposable actorDisposable

        let actor = Actor {
            _actorQueue      = actorEvQueue
          , _actorCtrlQueue  = actorCtrlQueue
          , _actorCleanup    = toDisposable actorDisposable
          , _actorDef        = gActorDef
          , _actorEventBus   = _supervisorEventBus
          , _actorLogger     = _supervisorLogger
          }

        putMVar actorVar actor
        return actor

      where

        initActor actorVar subDisposable = do
          actor <- takeMVar actorVar
          disposable <-
            case spawn of
              (RestartActor _ _ st' err gev _ delay) -> do
                threadDelay delay
                restartActor actor (unsafeCoerce st') err gev
              (NewActor {}) -> newActor actor

          Disposable.set disposable subDisposable

        ---

        newActor actor = do
          result <- runPreActorM (getActorKey actor)
                                 _supervisorEventBus
                                 logger
                                 (_actorPreStart actorDef)
          threadDelay $ _actorDelayAfterStart actorDef
          case result of
            InitFailure err -> do
              sendActorInitErrorToSupervisor actor err
              emptyDisposable
            InitOk st -> startActorLoop actor st

        ---

        restartActor actor oldSt err gev = do
          result <-
            logError $ runActorM oldSt _supervisorEventBus  actor
                                 (_actorPostRestart actorDef err gev)
          case result of
            -- TODO: Do a warning with the error
            Nothing -> startActorLoop actor oldSt
            Just (InitOk newSt, _) -> startActorLoop actor newSt
            Just (InitFailure initErr, _) -> do
              void $ sendActorInitErrorToSupervisor actor initErr
              emptyDisposable

        ---

        startActorLoop actor st =
          safeSubscribe (actorObservable actor st)
                        -- TODO: Receive a function that understands
                        -- the state and can provide meaningful
                        -- state <=> ev info
                        (const $ return ())
                        handleActorObservableError
                        (return ())

        ---

        actorObservable actor st =
          scanLeftWithItem (actorLoop actor) st $
          _actorEventBusDecorator actorDef $
          Observable.repeat getEventFromQueue

        ---

        getEventFromQueue = atomically $ do
          orElse (NormalEvent  <$> readTChan actorEvQueue)
                 (readTChan actorCtrlQueue)

        ---

        handleActorObservableError err =
          fromMaybe
            (error $ "FATAL: Arrived to unhandled error on actorLoop: " ++ show err)
            (_sendToSupervisor <$> fromException err)

        ---

        actorLoop actor st (NormalEvent gev) = handleNormalEvent actor st gev

        actorLoop actor st (RestartActorEvent err gev) = do
          trace ("Restart actor from Supervisor" :: String) logger
          sendActorLoopErrorToSupervisor RestartOne actor err st gev

        actorLoop actor st StopActorEvent = do
          trace ("Stop actor from Supervisor" :: String) logger
          runActorM st _supervisorEventBus actor $ _actorPostStop actorDef
          stopActorLoop

        ---

        handleNormalEvent actor st gev = do
          let handlers = _actorReceive actorDef
              evType = typeOfEvent gev

          case HashMap.lookup evType handlers of
            Nothing -> return st
            Just (EventHandler _ handler) -> do
              noisyF "[type: {}] actor handling event" (Only evType) logger
              result <-
                try $ execActorM st _supervisorEventBus actor
                                 (handler $ fromJust $ fromGenericEvent gev)
              case result of
                Left err  -> handleActorLoopError actor err st gev
                Right (st', _, _) -> return st'

        ---

        handleActorLoopError actor err@(SomeException innerErr) st gev = do
          noisyF "Received error on {}: {}" (getActorKey gActorDef, show err) logger
          let errType = show $ typeOf innerErr
              restartDirectives = _actorRestartDirective actorDef
          case HashMap.lookup errType restartDirectives of
            Nothing ->
              sendActorLoopErrorToSupervisor Restart actor err st gev
            Just (ErrorHandler errHandler) -> do
              (restartDirective, _) <-
                 runActorM st _supervisorEventBus actor $
                   errHandler (fromJust $ fromException err)
              case restartDirective of
                Resume -> do
                  noisyF "[error: {}] Resume actor" (Only $ show err) logger
                  return st
                Stop -> do
                  noisyF "[error: {}] Stop actor" (Only $ show err) logger
                  runActorM st _supervisorEventBus actor
                    $ _actorPostStop actorDef
                  stopActorLoop
                _ -> do
                  noisyF "[error: {}] Send error to supervisor" (Only $ show err) logger
                  sendActorLoopErrorToSupervisor restartDirective actor err st gev

        ---

        stopActorLoop = throwIO $ ActorTerminated gActorDef

        ---

        sendActorLoopErrorToSupervisor restartDirective actor err st gev = do
          logError_
            $ runActorM st _supervisorEventBus actor
            $ if restartDirective == Stop
              then _actorPostStop actorDef
              else _actorPreRestart actorDef err gev

          noisy ("Notify supervisor to restart actor" :: String) logger
          throwIO
            ActorFailedWithError {
                    _supEvTerminatedState = st
                  , _supEvTerminatedFailedEvent = gev
                  , _supEvTerminatedError = err
                  , _supEvTerminatedActor = actor
                  , _supEvTerminatedDirective = restartDirective
                  }

        ---

        sendActorInitErrorToSupervisor actor err = do
          _ <- throwIO
            ActorFailedOnInitialize {
              _supEvTerminatedError = err
            , _supEvTerminatedActor = actor
            }
          return ()

_sendToActor :: Actor -> GenericEvent -> IO ()
_sendToActor actor gev = do
  atomically $ writeTChan (_actorQueue actor) gev

_sendCtrlToActor :: Actor -> ActorEvent -> IO ()
_sendCtrlToActor actor aev = do
  atomically $ writeTChan (_actorCtrlQueue actor) aev
