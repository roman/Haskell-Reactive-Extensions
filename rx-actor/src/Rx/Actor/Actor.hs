{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
module Rx.Actor.Actor where

import Control.Applicative ((<$>))

import Control.Monad (forM_, void, when)
import Control.Monad.State.Strict (execStateT)

import Control.Exception (SomeException(..), fromException, try, throwIO)
import Control.Concurrent.Async (async, cancel)
import Control.Concurrent.MVar (MVar, newEmptyMVar, takeMVar, putMVar)
import Control.Concurrent.STM ( TChan, TVar
                              , atomically, orElse
                              , newTVarIO, modifyTVar, readTVar
                              , newTChanIO, writeTChan, readTChan )

import Data.Maybe (fromMaybe, fromJust)
import Data.Typeable (typeOf)

import qualified Data.HashMap.Strict as HashMap

import Tiempo.Concurrent (threadDelay)

import Unsafe.Coerce (unsafeCoerce)

import Rx.Observable ( Observable, Sync, safeSubscribe, scanLeftWithItemM )
import Rx.Disposable ( Disposable, SingleAssignmentDisposable
                     , emptyDisposable, createDisposable, dispose
                     , newCompositeDisposable, newSingleAssignmentDisposable
                     , toDisposable )

import qualified Rx.Observable as Observable
import qualified Rx.Disposable as Disposable

import Rx.Logger (Logger, loud, loudF, Only(..))
import qualified Rx.Logger.Monad as Logger

import Rx.Actor.Monad ( execActorM, runActorM, runPreActorM
                      , evalActorM, evalReadOnlyActorM )
import Rx.Actor.EventBus (fromGenericEvent, typeOfEvent)
import Rx.Actor.Util (logError, logError_)
import Rx.Actor.Types

--------------------------------------------------------------------------------

-- spawnRootActor :: Logger -> EventBus -> GenericActorDef -> IO Actor
-- spawnRootActor logger evBus gActorDef = do
--    let absoluteKey = "/user"

--    genericEvQueue <- newTChanIO
--    childEvQueue <- newTChanIO
--    supEvQueue <- newTChanIO

--    actorVar <- newEmptyMVar
--    actorDisposable <- newCompositeDisposable
--    actorLoopDisposable <- newSingleAssignmentDisposable
--    actorAsync <- async $ newActor actorVar actorLoopDisposable
--    actorChildren <- newTVarIO HashMap.empty

--    asyncDisposable <- createDisposable $ do
--      loud "Root actor disposable called" logger
--      cancel actorAsync

--    Disposable.append actorLoopDisposable actorDisposable
--    Disposable.append asyncDisposable actorDisposable

--    let actor = Actor {
--        _actorAbsoluteKey    = absoluteKey
--      , _actorAsync          = actorAsync
--      , _actorGenericEvQueue = genericEvQueue
--      , _actorChildEvQueue   = childEvQueue
--      , _actorSupEvQueue     = supEvQueue
--      , _actorDisposable     = toDisposable actorDisposable
--      , _actorDef            = gActorDef
--      , _actorEventBus       = evBus
--      , _actorLogger         = logger
--      , _actorChildren       = actorChildren
--      }

--    putMVar actorVar actor
--    return actor
--   where
--     newActor actor = do
--      actor <- readMVar actorVar
--      result <- runPreActorM (toActorKey actor)
--                                 evBus
--                                 logger
--                                 (_actorPreStart actorDef)
--      threadDelay $ _actorDelayAfterStart actorDef
--      case result of
--        InitFailure err -> throwIO err
--        InitOk st -> startActorLoop actor st



spawnChildActor :: ParentActor -> StartStrategy -> IO Actor
spawnChildActor parent strategy = do
    (actorGenericEvQueue, actorChildEvQueue, actorSupEvQueue) <-
      createOrGetActorQueues strategy
    actorChildren <- createOrGetSupChildren strategy
    main (_startStrategyActorDef strategy)
         (_actorLogger parent)
         (_actorEventBus parent)
         actorChildren
         actorGenericEvQueue actorChildEvQueue actorSupEvQueue
  where
    parentKey = toActorKey parent
    main :: GenericActorDef
         -> Logger -> EventBus -> TVar ActorChildren
         -> TChan GenericEvent -> TChan ChildEvent -> TChan SupervisorEvent
         -> IO Actor
    main gActorDef@(GenericActorDef actorDef)
         logger evBus actorChildren
         actorGenericEvQueue actorChildEvQueue actorSupEvQueue = do

        actorDisposable <- newCompositeDisposable
        actorLoopDisposable <- newSingleAssignmentDisposable

        actorVar <- newEmptyMVar
        actorAsync <-
          _actorForker actorDef $ initActor actorVar actorLoopDisposable


        asyncDisposable <- createDisposable $ do
          loudF "[actorKey: {}] actor disposable called"
                (Only $ toActorKey actorDef)
                logger
          cancel actorAsync

        Disposable.append actorLoopDisposable actorDisposable
        Disposable.append asyncDisposable actorDisposable

        let actor = Actor {
            _actorAbsoluteKey    = absoluteKey
          , _actorAsync          = actorAsync
          , _actorGenericEvQueue = actorGenericEvQueue
          , _actorChildEvQueue   = actorChildEvQueue
          , _actorSupEvQueue     = actorSupEvQueue
          , _actorDisposable     = toDisposable actorDisposable
          , _actorDef            = gActorDef
          , _actorEventBus       = evBus
          , _actorLogger         = logger
          , _actorChildren       = actorChildren
          }

        putMVar actorVar actor
        return actor
      where
        absoluteKey = parentKey ++ "/" ++ toActorKey gActorDef

        -------------------- * Child Creation functions * --------------------

        initActor :: MVar Actor -> SingleAssignmentDisposable -> IO ()
        initActor actorVar actorLoopDisposable = do
          actor <- takeMVar actorVar
          disposable <-
            case strategy of
              -- NOTE: can't use record function to get prevSt because
              -- of the existencial type :-(
              (ViaPreRestart prevSt _ _ _ _ _ _ _ _) -> do
                threadDelay (_startStrategyDelay strategy)
                restartActor actor (unsafeCoerce prevSt)
                                   (_startStrategyError strategy)
                                   (_startStrategyFailedEvent strategy)
              (ViaPreStart {}) -> newActor actor

          Disposable.set disposable actorLoopDisposable

        ---

        newActor :: Actor -> IO Disposable
        newActor actor = do
          result <- runPreActorM (toActorKey actor)
                                 evBus
                                 logger
                                 (_actorPreStart actorDef)
          threadDelay $ _actorDelayAfterStart actorDef
          case result of
            InitFailure err -> do
              sendActorInitErrorToSupervisor actor err
              emptyDisposable
            InitOk st -> startActorLoop actor st

        ---

        restartActor
          :: forall st . Actor -> st -> SomeException -> GenericEvent -> IO Disposable
        restartActor actor oldSt err gev = do
          result <-
            logError $
               evalReadOnlyActorM oldSt evBus actor
                                  (unsafeCoerce $ _actorPostRestart actorDef err gev)
          case result of
            -- TODO: Do a warning with the error
            Nothing -> startActorLoop actor oldSt
            Just (InitOk newSt) -> startActorLoop actor newSt
            Just (InitFailure initErr) -> do
              void $ sendActorInitErrorToSupervisor actor initErr
              emptyDisposable

        -------------------- * ActorLoop functions * --------------------

        startActorLoop :: forall st . Actor -> st -> IO Disposable
        startActorLoop actor st =
          safeSubscribe (actorObservable actor st)
                        -- TODO: Receive a function that understands
                        -- the state and can provide meaningful
                        -- state <=> ev info
                        (const $ return ())
                        (handleActorObservableError actor st)
                        (return ())

        ---

        actorObservable
          :: forall st. Actor -> st -> Observable Sync (st, ActorEvent)
        actorObservable actor st =
          scanLeftWithItemM (actorLoop actor) st $
          _actorEventBusDecorator actorDef $
          Observable.repeat getEventFromQueue

        ---

        getEventFromQueue :: IO ActorEvent
        getEventFromQueue = atomically $
          (ChildEvent <$> readTChan actorChildEvQueue) `orElse`
          (SupervisorEvent <$> readTChan actorSupEvQueue) `orElse`
          (NormalEvent  <$> readTChan actorGenericEvQueue)

        ---

        handleActorObservableError
          :: forall st. Actor -> st -> SomeException -> IO ()
        handleActorObservableError actor st merr = do
          let runActorCtx = evalReadOnlyActorM st evBus actor
          case fromException merr of
            Just err -> sendSupEventToActor parent err
            Nothing -> do
              let errMsg = "FATAL: Arrived to unhandled error on actorLoop: " ++ show merr
              runActorCtx $ Logger.severe errMsg
              error errMsg

        ---

        actorLoop :: forall st . Actor -> st -> ActorEvent -> IO st
        actorLoop actor st (NormalEvent gev) = handleGenericEvent actor st gev

        actorLoop actor st (ChildEvent (ActorRestarted err gev)) = do
          evalReadOnlyActorM st evBus actor $
            Logger.traceF "Restart actor from Parent {}" (Only parentKey)
          stopActorLoopAndRaise RestartOne actor err st gev

        actorLoop actor st (ChildEvent ActorStopped) = do
          evalReadOnlyActorM st evBus actor $ do
            Logger.traceF "Stop actor from Parent {}" (Only parentKey)
            unsafeCoerce $ _actorPostStop actorDef
          stopActorLoop

        actorLoop actor actorSt (SupervisorEvent ev) = do
          case ev of
            (ActorSpawned gChildActorDef) ->
              addChildActor actor actorSt gChildActorDef

            (ActorTerminated child) ->
              removeChildActor actor actorSt child

            (ActorFailedOnInitialize err child) ->
              cleanupActor actor actorSt err

            (ActorFailedWithError prevChildSt failedEv err child directive) ->
              restartChildActor actor actorSt prevChildSt failedEv err
                                child directive
          return actorSt

        -------------------- * Child functions

        handleGenericEvent
          :: forall st . Actor -> st -> GenericEvent -> IO st
        handleGenericEvent actor st gev = do
          let handlers = _actorReceive actorDef
              evType = typeOfEvent gev

          newSt <-
            case HashMap.lookup evType handlers of
              Nothing -> return st
              Just (EventHandler _ handler) -> do
                result <-
                  try
                    $ execActorM st evBus actor $ do
                      Logger.noisyF "[type: {}] actor handling event"
                                    (Only evType)
                      unsafeCoerce $ handler (fromJust $ fromGenericEvent gev)
                case result of
                  Left err  -> handleActorLoopError actor err st gev
                  Right (st', _, _) -> return st'

          sendGenericEvToChildren actor gev
          return newSt

        ---

        handleActorLoopError
          :: forall st . Actor -> SomeException -> st -> GenericEvent -> IO st
        handleActorLoopError actor err@(SomeException innerErr) st gev = do
          let runActorCtx = evalReadOnlyActorM st evBus actor

          runActorCtx $
            Logger.noisyF "Received error on {}: {}"
                          (toActorKey gActorDef, show err)

          let errType = show $ typeOf innerErr
              restartDirectives = _actorRestartDirective actorDef
          case HashMap.lookup errType restartDirectives of
            Nothing ->
              stopActorLoopAndRaise Restart actor err st gev
            Just (ErrorHandler errHandler) -> do
              restartDirective <-
                runActorCtx $ unsafeCoerce $ errHandler (fromJust $ fromException err)
              case restartDirective of
                Resume -> do
                  runActorCtx
                    $ Logger.noisyF "[error: {}] Resume actor" (Only $ show err)
                  return st
                Stop -> do
                  stopChildren actor
                  runActorCtx $ do
                    Logger.noisyF "[error: {}] Stop actor" (Only $ show err)
                    unsafeCoerce $ _actorPostStop actorDef
                  stopActorLoop
                _ -> do
                  runActorCtx $
                    Logger.noisyF "[error: {}] Send error to supervisor"
                                  (Only $ show err)
                  stopActorLoopAndRaise restartDirective actor err st gev

        ---

        stopActorLoop :: forall st. IO st
        stopActorLoop = throwIO $ ActorTerminated gActorDef

        ---

        stopActorLoopAndRaise
          :: RestartDirective -> Actor
          -> SomeException -> st -> GenericEvent
          -> IO st
        stopActorLoopAndRaise restartDirective actor err st gev = do
          let runActorCtx =
                  evalReadOnlyActorM st evBus actor

          restartAllChildrenActor actor st actor st gev err

          logError_
            $ runActorCtx
            $ if restartDirective == Stop
              then unsafeCoerce $ _actorPostStop actorDef
              else unsafeCoerce $ _actorPreRestart actorDef err gev

          runActorCtx $ Logger.noisy ("Notify parent to restart actor" :: String)
          throwIO
            ActorFailedWithError {
                    _supEvTerminatedState = st
                  , _supEvTerminatedFailedEvent = gev
                  , _supEvTerminatedError = err
                  , _supEvTerminatedActor = actor
                  , _supEvTerminatedDirective = restartDirective
                  }

        ---

        sendActorInitErrorToSupervisor
          :: Actor -> SomeException -> IO ()
        sendActorInitErrorToSupervisor actor err = do
          _ <- throwIO
            ActorFailedOnInitialize {
              _supEvTerminatedError = err
            , _supEvTerminatedActor = actor
            }
          return ()

        -------------------- * Parent/Supervisior functions

        sendGenericEvToChildren :: Actor -> GenericEvent -> IO ()
        sendGenericEvToChildren actor gev = do
          -- TODO: Add a Set of Available Handler Types
          children <- atomically $ readTVar $ _actorChildren actor
          mapM_ (`sendToActor` gev) $ HashMap.elems children

        startChildActor
          :: forall st. Actor -> st -> GenericActorDef -> StartStrategy -> IO ()
        startChildActor actor _selfSt gChildActorDef startStrategy = do
          let childActorKey = toActorKey gChildActorDef
          child <- spawnChildActor actor startStrategy
          atomically
            $ modifyTVar (_actorChildren actor)
            $ HashMap.insertWith (\_ _ -> child) childActorKey child

        addChildActor :: forall st. Actor -> st -> GenericActorDef -> IO ()
        addChildActor actor actorSt gChildActorDef = do
          let runActorCtx = evalReadOnlyActorM actorSt evBus actor
              childActorKey = toActorKey gChildActorDef
          runActorCtx $ Logger.noisyF "Starting new actor {}" (Only childActorKey)
          startChildActor actor actorSt gChildActorDef $ ViaPreStart gChildActorDef

        restartSingleChildActor
          :: forall st childSt. Actor -> st
          -> ChildActor -> childSt
          -> GenericEvent -> SomeException
          -> IO ()
        restartSingleChildActor actor actorSt
                                child prevChildSt failedEv err = do

          let runActorCtx = evalReadOnlyActorM actorSt evBus actor
              gChildActorDef = _actorDef child
              restartAttempt = getRestartAttempts gChildActorDef
              backoffDelay =
                  _actorSupervisorBackoffDelayFn actorDef restartAttempt

          gChildActorDef1 <- incRestartAttempt gChildActorDef
          removeChildActor actor actorSt child
          runActorCtx $
            Logger.noisyF "Restarting actor {} with delay {}"
                          (toActorKey gChildActorDef, show backoffDelay)

          startChildActor actor actorSt gChildActorDef $
            ViaPreRestart {
              _startStrategyPrevState      = prevChildSt
            , _startStrategyGenericEvQueue = _actorGenericEvQueue child
            , _startStrategyChildEvQueue   = _actorChildEvQueue child
            , _startStrategySupEvQueue     = _actorSupEvQueue child
            , _startStrategySupChildren    = _actorChildren child
            , _startStrategyError          = err
            , _startStrategyFailedEvent    = failedEv
            , _startStrategyActorDef       = gChildActorDef1
            , _startStrategyDelay          = backoffDelay
            }

        restartAllChildrenActor
          :: forall st failedSt. Actor -> st
          -> Actor -> failedSt
          -> GenericEvent -> SomeException
          -> IO ()
        restartAllChildrenActor actor actorSt
                                failingActor prevSt failedEv err = do

          let failingActorKey = toActorKey failingActor
          children <- atomically $ readTVar $ _actorChildren actor
          -- TODO: Maybe do this in parallel
          restartSingleChildActor actor actorSt failingActor prevSt failedEv err
          forM_ (HashMap.elems children) $ \otherChild -> do
            let otherChildKey = toActorKey otherChild
            when (otherChildKey /= failingActorKey) $
              -- Actor will send back a message to supervisor to restart itself
              sendChildEventToActor otherChild (ActorRestarted err failedEv)

        restartChildActor
          :: forall st childSt. Actor -> st
          -> childSt -> GenericEvent -> SomeException
          -> ChildActor -> RestartDirective
          -> IO ()
        restartChildActor actor actorSt prevChildSt
                          failedEv err child directive = do
          let runActorCtx = evalReadOnlyActorM actorSt evBus actor
          case directive of
            Raise -> do
              runActorCtx $
                Logger.noisyF "Raise error from child {}" (Only $ toActorKey child)
              cleanupActor actor actorSt err
            RestartOne ->
              restartSingleChildActor actor actorSt child prevChildSt failedEv err
            Restart -> do
              let restarter =
                    case _actorSupervisorStrategy actorDef of
                      OneForOne -> restartSingleChildActor
                      AllForOne -> restartAllChildrenActor
              restarter actor actorSt child prevChildSt failedEv err
            _ -> do
              let errMsg = "FATAL: Restart Actor procedure received " ++
                           "an unexpected directive " ++ show directive
              runActorCtx $ Logger.severe errMsg
              error errMsg

        removeChildActor :: forall st child. ToActorKey child
                         => Actor -> st -> child -> IO ()
        removeChildActor actor actorSt child = do
          let runActorCtx = evalReadOnlyActorM actorSt evBus actor
              childActorKey = toActorKey child
          wasRemoved <- atomically $ do
            childMap <- readTVar $ _actorChildren actor
            case HashMap.lookup childActorKey childMap of
              Nothing -> return False
              Just _ -> do
                modifyTVar (_actorChildren actor) $ HashMap.delete childActorKey
                return True
          when wasRemoved $
            runActorCtx $
              Logger.noisyF "Removing child {}" (Only childActorKey)

        cleanupActor :: forall st. Actor -> st -> SomeException -> IO ()
        cleanupActor actor actorSt err = do
          let runActorCtx = evalReadOnlyActorM actorSt evBus actor
          runActorCtx $ Logger.noisyF "Failing with error '{}'" (Only $ show err)
          disposeChildren actor
          throwIO err


onChildren :: (ChildActor -> IO ()) -> ParentActor -> IO ()
onChildren onChildFn parent = do
  childMap <- atomically $ readTVar $ _actorChildren parent
  mapM_ onChildFn (HashMap.elems childMap)

stopChildren :: ParentActor -> IO ()
stopChildren = onChildren (`sendChildEventToActor` ActorStopped)

disposeChildren :: ParentActor -> IO ()
disposeChildren = onChildren dispose

sendToActor :: Actor -> GenericEvent -> IO ()
sendToActor actor = atomically . writeTChan (_actorGenericEvQueue actor)

sendChildEventToActor :: Actor -> ChildEvent -> IO ()
sendChildEventToActor actor = atomically . writeTChan (_actorChildEvQueue actor)

sendSupEventToActor :: Actor -> SupervisorEvent -> IO ()
sendSupEventToActor actor = atomically . writeTChan (_actorSupEvQueue actor)
