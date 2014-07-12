{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ExistentialQuantification #-}
module Rx.Actor.Actor where

import Control.Applicative ((<$>), (<|>))

import Control.Monad (void, when)
import Control.Monad.Trans (liftIO)
import Control.Monad.State.Strict (execStateT)

import Control.Exception (SomeException(..), fromException, try, throwIO)
import Control.Concurrent (forkIO, killThread, myThreadId, yield)
import Control.Concurrent.MVar (newEmptyMVar, takeMVar, putMVar)
import Control.Concurrent.STM (atomically, newTChanIO, readTChan, writeTChan)

import Data.Maybe (fromMaybe, fromJust)
import Data.Typeable (typeOf)

import qualified Data.Set as Set
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
        actorHandlerTypes = Set.fromList . HashMap.keys $ _actorReceive actorDef
        shouldHandleEvent gev = Set.member (show $ typeOfEvent gev) actorHandlerTypes
        sendToActor gev =
          when (shouldHandleEvent gev) $ atomically (writeTChan actorEvQueue gev)

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
          result <- _actorPreStart actorDef _supervisorEventBus
          threadDelay $ _actorDelayAfterStart actorDef
          case result of
            InitFailure err -> do
              sendActorInitErrorToSupervisor actor err
              emptyDisposable
            InitOk st -> startActorLoop actor st

        restartActor actor oldSt err gev = do
          result <- logError $ _actorPostRestart actorDef oldSt err gev
          case result of
            -- TODO: Do a warning with the error
            Nothing -> startActorLoop actor oldSt
            Just (InitOk newSt) -> startActorLoop actor newSt
            Just (InitFailure initErr) -> do
              sendActorInitErrorToSupervisor actor initErr
              emptyDisposable

        startActorLoop actor st =
          safeSubscribe (actorObservable actor st)
                        -- TODO: Receive a function that understands
                        -- the state and can provide meaningful
                        -- state <=> ev info
                        (const $ return ())
                        handleActorObservableError
                        (return ())

        actorObservable actor st =
          scanLeftWithItem (actorLoop actor) st $
          _actorEventBusDecorator actorDef $
          toSyncObservable actorEvQueue

        handleActorObservableError err =
          maybe (error "FATAL: Arrived to unhandled error on actorLoop") id $
                ((\(StopActorLoop _) -> return ()) <$> fromException err) <|>
                (_sendToSupervisor <$> fromException err)


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
                Left err  -> handleActorLoopError actor err st gev
                Right (st', _) -> return st'

        handleActorLoopError actor err@(SomeException innerErr) st gev = do
          putStrLn $ "Received error on " ++ getActorKey gActorDef ++ ": " ++ show err
          let errType = show $ typeOf innerErr
              restartDirectives = _actorRestartDirective actorDef
          case HashMap.lookup errType restartDirectives of
            Nothing ->
              sendActorLoopErrorToSupervisor Restart actor err st gev
            Just (ErrorHandler errHandler) -> do
              restartDirective <- errHandler (fromJust $ fromException err) st
              case restartDirective of
                Resume -> do
                  logMsg $ "[error: " ++ show err ++ "] Resume actor"
                  return st
                Stop -> do
                  logMsg $ "[error: " ++ show err ++ "] Stop actor"
                  _actorPostStop actorDef st
                  stopActorLoop err
                _ -> do
                  logMsg $ "[error: " ++ show err ++ "] Send message to supervisor actor"
                  sendActorLoopErrorToSupervisor restartDirective actor err st gev

        stopActorLoop = throwIO . StopActorLoop

        sendActorLoopErrorToSupervisor restartDirective actor err st gev = do
          logError_ $
            if restartDirective == Restart
              then _actorPreRestart actorDef st err gev
              else _actorPostStop actorDef st

          logMsg "Notify supervisor to restart actor"
          throwIO
            $ ActorFailedWithError {
                    _supEvTerminatedState = st
                  , _supEvTerminatedFailedEvent = gev
                  , _supEvTerminatedError = err
                  , _supEvTerminatedActor = actor
                  , _supEvTerminatedDirective = restartDirective
                  }

        sendActorInitErrorToSupervisor actor err =
          throwIO
            $ ActorFailedOnInitialize {
              _supEvTerminatedError = err
            , _supEvTerminatedActor = actor
            }


        logMsg msg = do
          let sep = case msg of
                      ('[':_) -> ""
                      (' ':_) -> ""
                      _ -> " "
          tid <- myThreadId
          putStrLn $
            "[" ++ show tid ++ "][actorKey:" ++ getActorKey gActorDef ++ "]" ++
            sep ++ msg
