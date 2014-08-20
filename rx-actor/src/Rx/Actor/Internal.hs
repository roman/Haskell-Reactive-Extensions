{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
module Rx.Actor.Internal where

import Control.Applicative ((<$>), (<*>))

import Control.Monad (forM_, void, when)

import Control.Exception (SomeException(..), fromException, try, throwIO)
import Control.Concurrent (yield)
import Control.Concurrent.Async (cancel, link, wait)
import Control.Concurrent.MVar (MVar, newEmptyMVar, takeMVar, putMVar)
import Control.Concurrent.STM ( TChan, TVar
                              , atomically, orElse
                              , newTVarIO, modifyTVar, readTVar
                              , newTChanIO, writeTChan, readTChan )
import Data.Maybe (fromJust)
import Data.Typeable (typeOf)

import qualified Data.HashMap.Strict as HashMap

import Tiempo.Concurrent (threadDelay)

import Unsafe.Coerce (unsafeCoerce)

import Rx.Observable ( subscribe, scanLeftWithItemM, toAsyncObservable )
import Rx.Disposable ( Disposable, CompositeDisposable
                     , emptyDisposable, createDisposable, dispose
                     , newCompositeDisposable, toDisposable )

import qualified Rx.Observable as Observable
import qualified Rx.Disposable as Disposable

import Rx.Logger (Logger, loudF, Only(..))
import qualified Rx.Logger.Monad as Logger

-- NOTE: If using evalActorM, for some reason it throws
-- a segfault (really crazy behavior, drive with caution)
import Rx.Actor.Monad ( execActorM, runPreActorM
                      , evalReadOnlyActorM )
import Rx.Actor.EventBus (fromGenericEvent, typeOfEvent)
import Rx.Actor.Util (logError, logError_)
import Rx.Actor.Logger ()
import Rx.Actor.Types

--------------------------------------------------------------------------------

startRootActor :: forall st. Logger -> EventBus -> ActorDef st -> IO Actor
startRootActor logger evBus actorDef = do
  let actorDef' = actorDef { _actorChildKey = Nothing }
      gActorDef = GenericActorDef actorDef'
  gevQueue   <- newTChanIO
  childQueue <- newTChanIO
  supQueue   <- newTChanIO
  children   <- newTVarIO HashMap.empty
  spawnActor (ViaPreStart gActorDef)
             Nothing
             logger
             evBus
             children
             gevQueue
             childQueue
             supQueue

stopRootActor :: Actor -> IO ()
stopRootActor = (`sendChildEventToActor` ActorStopped)

joinRootActor :: Actor -> IO ()
joinRootActor actor = do
  wait $ _actorAsync actor


-------------------- * Child Creation functions * --------------------

spawnChildActor :: StartStrategy -> ParentActor -> IO Actor
spawnChildActor strategy parent = do
    children <- createOrGetSupChildren strategy
    ( gevQueue, childQueue, supQueue ) <- createOrGetActorQueues strategy
    spawnActor strategy
               (Just parent)
               (_actorLogger parent)
               (_actorEventBus parent)
               children
               gevQueue
               childQueue
               supQueue

-------------------- * Child Creation functions * --------------------

spawnActor :: StartStrategy
           -> Maybe ParentActor
           -> Logger
           -> EventBus
           -> TVar ActorChildren
           -> TChan GenericEvent
           -> TChan ChildEvent
           -> TChan SupervisorEvent
           -> IO Actor
spawnActor strategy parent logger evBus children gevQueue childQueue supQueue =
  case _startStrategyActorDef strategy of
    gActorDef@(GenericActorDef actorDef) -> do
      let absoluteKey = case parent of
                          Nothing -> "/user"
                          Just p  -> toActorKey p  ++ "/" ++ toActorKey actorDef

      actorVar        <- newEmptyMVar
      actorDisposable <- newCompositeDisposable

      actorAsync <-
        _actorForker actorDef $
          initActor strategy parent actorDef actorVar actorDisposable


      let actor = Actor {
          _actorAbsoluteKey    = absoluteKey
        , _actorAsync          = actorAsync
        , _actorGenericEvQueue = gevQueue
        , _actorChildEvQueue   = childQueue
        , _actorSupEvQueue     = supQueue
        , _actorDisposable     = toDisposable actorDisposable
        , _actorDef            = gActorDef
        , _actorEventBus       = evBus
        , _actorLogger         = logger
        , _actorChildren       = children
        }


      putMVar actorVar actor
      yield

      case parent of
        Nothing -> link actorAsync
        Just _ -> return ()

      -- IMPORTANT: The disposable creation/append has to be done
      -- after the actor thread starts. Please do not move it
      -- before that
      asyncDisposable <- createDisposable $ do
        case parent of
          Just _ ->
            loudF logger
                  "[{}] actor disposable called"
                  (Only $ toActorKey actor)

          Nothing ->
            loudF logger
                  "[{}] actor disposable called"
                  (Only absoluteKey)

        sendChildEventToActor actor ActorStopped
        threadDelay $ _actorStopDelay actorDef
        cancel actorAsync

      -- create eventBus subscription disposable
      eventBusDisposable <-
        case parent of
          Just _ -> emptyDisposable
          Nothing -> do
            subscribe (toAsyncObservable evBus)
                          (atomically . writeTChan gevQueue)
                          throwOnError
                          (return ())

      Disposable.append asyncDisposable actorDisposable
      Disposable.append eventBusDisposable actorDisposable
      return actor
  where
    throwOnError err =
      case fromException err of
        Just (ActorTerminated _) -> return ()
        _ -> throwIO err

initActor
  :: forall st. StartStrategy -> Maybe ParentActor -> ActorDef st
  -> MVar Actor -> CompositeDisposable -> IO ()
initActor strategy parent actorDef actorVar actorDisposable = do
  actor <- takeMVar actorVar

  -- NOTE: Add a disposable to stop all actor children
  childrenDisposable <- createDisposable $ disposeChildren actor
  Disposable.append childrenDisposable actorDisposable

  -- IMPORTANT: This is a synchronous call, whatever we do after
  -- this is going to be executed after the actorLoop is done
  _actorLoopDisposable <-
    case strategy of
      -- NOTE: can't use record function to get prevSt because
      -- of the existencial type :-(
      (ViaPreRestart prevSt _ _ _ _ _ _ _ _) -> do
        threadDelay (_startStrategyDelay strategy)
        restartActor parent
                     actorDef
                     actor
                     (unsafeCoerce prevSt)
                     (_startStrategyError strategy)
                     (_startStrategyFailedEvent strategy)

      (ViaPreStart {}) ->
        newActor parent actorDef actor

  return ()

---

newActor :: forall st . Maybe ParentActor -> ActorDef st -> Actor -> IO Disposable
newActor parent actorDef actor = do
    eResult <-
      try
        $ runPreActorM actor
                       (do Logger.loud ("Calling preStart on actor" :: String)
                           _actorPreStart actorDef)
    case eResult of
      Left err ->
        sendActorInitErrorToSupervisor actor err
      Right result -> do
        threadDelay $ _actorDelayAfterStart actorDef
        case result of
          InitFailure err ->
            sendActorInitErrorToSupervisor actor err
          InitOk st -> do
            startNewChildren
            startActorLoop parent actorDef actor st
  where
    startNewChildren = do
      let children = _actorChildrenDef actorDef
          execActor = runPreActorM actor

      execActor $ Logger.loudF "Starting actor children: {}"
                               (Only $ show children)
      forM_ children $ \gChildActorDef -> do
        _child <- startChildActor (ViaPreStart gChildActorDef) actor
        return ()

---

restartActor
  :: forall st . Maybe ParentActor -> ActorDef st -> Actor -> st
  -> SomeException -> GenericEvent -> IO Disposable
restartActor parent actorDef actor oldSt err gev = do
  result <-
    logError $
       evalReadOnlyActorM oldSt actor
                          (unsafeCoerce $ _actorPostRestart actorDef err gev)
  case result of
    -- TODO: Do a warning with the error
    Nothing -> startActorLoop parent actorDef actor oldSt
    Just (InitOk newSt) -> startActorLoop parent actorDef actor newSt
    Just (InitFailure initErr) ->
      sendActorInitErrorToSupervisor actor initErr

-------------------- * ActorLoop functions * --------------------

startActorLoop :: forall st . Maybe ParentActor
               -> ActorDef st
               -> Actor
               -> st
               -> IO Disposable
startActorLoop mparent actorDef actor st0 = do
    void
      $ execActorM st0 actor
      $ Logger.loud ("Starting actor loop" :: String)

    subscribe actorObservable
                  -- TODO: Receive a function that understands
                  -- the state and can provide meaningful
                  -- state <=> ev info
                  (const $ return ())
                  handleActorObservableError
                  (return ())
  where
    actorObservable =
      scanLeftWithItemM (actorLoop mparent actorDef actor) st0 $
      _actorEventBusDecorator actorDef $
      Observable.repeat (getEventFromQueue actor)

    handleActorObservableError serr = do
      let runActorCtx = evalReadOnlyActorM st0 actor
      case mparent of
        Nothing ->
          case fromException serr of
            Just err@(ActorFailedWithError {}) ->
              throwIO $ _supEvTerminatedError err
            Just err -> do
              let errMsg = "Unhandled SupervisorEvent received " ++ show err
              runActorCtx $ Logger.warn errMsg
            Nothing -> do
              let errMsg = "Actor loop observable received non-supervisor error"
                           ++ show serr
              runActorCtx $ Logger.warn errMsg
              throwIO serr
        Just parent ->
          case fromException serr of
            Just err -> sendSupEventToActor parent err
            Nothing -> do
              let errMsg =
                    "Arrived to unhandled error on actorLoop: " ++ show serr
              runActorCtx $ Logger.severe errMsg
              error errMsg

---

getEventFromQueue :: Actor -> IO ActorEvent
getEventFromQueue actor = atomically $
  (ChildEvent <$> readTChan (_actorChildEvQueue actor)) `orElse`
  (SupervisorEvent <$> readTChan (_actorSupEvQueue actor)) `orElse`
  (NormalEvent  <$> readTChan (_actorGenericEvQueue actor))

---

actorLoop ::
  forall st . Maybe ParentActor -> ActorDef st -> Actor
  -> st -> ActorEvent -> IO st
actorLoop _ actorDef actor st (NormalEvent gev) =
  handleGenericEvent actorDef actor st gev

actorLoop mParent actorDef actor st (ChildEvent (ActorRestarted err gev)) = do
  evalReadOnlyActorM st actor $
    case mParent of
      Just parent ->
        Logger.traceF "Restart actor from Parent {}"
                      (Only $ toActorKey parent)
      Nothing -> do
        let errMsg = "The impossible happened: root actor was reseted"
        Logger.severe errMsg
        error errMsg
  stopActorLoopAndRaise RestartOne actorDef actor err st gev

actorLoop mParent actorDef actor st (ChildEvent ActorStopped) = do
  void $ evalReadOnlyActorM st actor $ do
    case mParent of
      Just parent ->
        Logger.traceF "Stop actor from Parent {}"
                      (Only $ toActorKey parent)
      Nothing ->
        Logger.trace ("Stop actor from user" :: String)

    unsafeCoerce $ _actorPostStop actorDef

  stopChildren actor
  stopActorLoop actorDef

actorLoop _ actorDef actor st (SupervisorEvent ev) = do
  case ev of
    (ActorSpawned gChildActorDef) ->
      void $ addChildActor actor st gChildActorDef

    (ActorTerminated child) ->
      removeChildActor actor st child

    (ActorFailedOnInitialize err _) ->
      cleanupActorAndRaise actor st err

    (ActorFailedWithError child prevChildSt failedEv err directive) ->
      restartChildActor actorDef actor st
                        child prevChildSt
                        failedEv err directive
  return st

-------------------- * Child functions * --------------------

handleGenericEvent
  :: forall st . ActorDef st -> Actor -> st -> GenericEvent -> IO st
handleGenericEvent actorDef actor st gev = do
  let handlers = _actorReceive actorDef
      evType = typeOfEvent gev

  let execActor = execActorM st actor

  void
    $ execActor
    $ Logger.noisyF "[evType: {}] actor receiving event"
                    (Only evType)

  sendGenericEvToChildren actor gev
  newSt <-
    case HashMap.lookup evType handlers of
      Nothing -> return st
      Just (EventHandler _ handler) -> do
        result <-
          try
            $ execActor
            $ do Logger.loudF "[evType: {}] actor handling event"
                              (Only evType)
                 unsafeCoerce $ handler (fromJust $ fromGenericEvent gev)
        case result of
          Left err  -> handleActorLoopError actorDef actor err st gev
          Right (st', _) -> return st'

  return newSt

---

handleActorLoopError
  :: forall st . ActorDef st -> Actor -> SomeException -> st -> GenericEvent -> IO st
handleActorLoopError actorDef actor err@(SomeException innerErr) st gev = do
  let runActorCtx = evalReadOnlyActorM st actor

  runActorCtx $
    Logger.noisyF "Received error on {}: {}"
                  (toActorKey actorDef, show err)

  let errType = show $ typeOf innerErr
      restartDirectives = _actorRestartDirective actorDef
  case HashMap.lookup errType restartDirectives of
    Nothing ->
      stopActorLoopAndRaise Restart actorDef actor err st gev
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
          void $ runActorCtx $ do
            Logger.noisyF "[error: {}] Stop actor" (Only $ show err)
            unsafeCoerce $ _actorPostStop actorDef
          stopActorLoop actorDef
        _ -> do
          runActorCtx $
            Logger.noisyF "[error: {}] Send error to supervisor"
                          (Only $ show err)
          stopActorLoopAndRaise restartDirective actorDef actor err st gev

---

stopActorLoop :: forall st. ActorDef st -> IO st
stopActorLoop actorDef =
  throwIO $ ActorTerminated (GenericActorDef actorDef)

---

stopActorLoopAndRaise
  :: RestartDirective -> ActorDef st -> Actor
  -> SomeException -> st -> GenericEvent
  -> IO st
stopActorLoopAndRaise restartDirective actorDef actor err st gev = do
  let runActorCtx =
          evalReadOnlyActorM st actor

  restartAllChildren actorDef actor st actor st gev err

  logError_
    $ runActorCtx
    $ unsafeCoerce
    $ if restartDirective == Stop
      then _actorPostStop actorDef
      else _actorPreRestart actorDef err gev

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
  :: Actor -> SomeException -> IO Disposable
sendActorInitErrorToSupervisor actor err = do
  let runActorCtx = runPreActorM actor
  runActorCtx
    $ Logger.warnF "Child failed at initialization: {}"
                   (Only $ show err)
  throwIO
    ActorFailedOnInitialize {
      _supEvTerminatedError = err
    , _supEvTerminatedActor = actor
    }

-- -------------------- * Parent/Supervisior functions

sendGenericEvToChildren :: Actor -> GenericEvent -> IO ()
sendGenericEvToChildren actor gev = do
  -- TODO: Add a Set of Available Handler Types
  let runActorCtx = runPreActorM actor

  children <- HashMap.elems <$> (atomically $ readTVar $ _actorChildren actor)
  forM_ children $ \child -> do
    runActorCtx
      $ Logger.noisyF "Send event to child {}"
                      (Only $ toActorKey child)
    sendToActor child gev

startChildActor
  :: StartStrategy -> ParentActor -> IO ChildActor
startChildActor strategy actor = do
  let gChildActorDef = _startStrategyActorDef strategy
      childActorKey = toActorKey gChildActorDef
  child <- spawnChildActor strategy actor
  atomically
    $ modifyTVar (_actorChildren actor)
    $ HashMap.insertWith (\_ _ -> child) childActorKey child
  return child

addChildActor :: forall st. Actor -> st -> GenericActorDef -> IO ChildActor
addChildActor actor actorSt gChildActorDef = do
  let runActorCtx = evalReadOnlyActorM actorSt actor
      childActorKey = toActorKey gChildActorDef
  runActorCtx $ Logger.noisyF "Starting new actor {}" (Only childActorKey)
  startChildActor (ViaPreStart gChildActorDef) actor

restartSingleChild
  :: forall st childSt. ActorDef st -> Actor -> st
  -> ChildActor -> childSt
  -> GenericEvent -> SomeException
  -> IO ()
restartSingleChild actorDef actor actorSt
                        child prevChildSt failedEv err = do

  let runActorCtx = evalReadOnlyActorM actorSt actor
      gChildActorDef = _actorDef child
      restartAttempt = getRestartAttempts gChildActorDef
      backoffDelay =
          _actorSupervisorBackoffDelayFn actorDef restartAttempt

  gChildActorDef1 <- incRestartAttempt gChildActorDef
  removeChildActor actor actorSt child
  runActorCtx $
    Logger.noisyF "Restarting actor {} with delay {}"
                  (toActorKey gChildActorDef, show backoffDelay)

  let strategy =
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

  void $ startChildActor strategy actor

restartAllChildren
  :: forall st failedSt. ActorDef st -> Actor -> st
  -> FailingActor -> failedSt
  -> GenericEvent -> SomeException
  -> IO ()
restartAllChildren _actorDef actor _actorSt
                        _failingActor _prevSt failedEv err = do

  children <- atomically $ readTVar $ _actorChildren actor
  forM_ (HashMap.elems children) $ \otherChild -> do
    sendChildEventToActor otherChild (ActorRestarted err failedEv)

restartChildActor
  :: forall st childSt. ActorDef st -> Actor -> st
  -> ChildActor -> childSt
  -> GenericEvent -> SomeException -> RestartDirective
  -> IO ()
restartChildActor actorDef actor actorSt
                  child prevChildSt
                  failedEv err directive = do
  let runActorCtx = evalReadOnlyActorM actorSt actor
  case directive of
    Raise -> do
      runActorCtx $
        Logger.noisyF "Raise error from child {}" (Only $ toActorKey child)
      cleanupActorAndRaise actor actorSt err
    RestartOne ->
      restartSingleChild actorDef actor actorSt child prevChildSt failedEv err
    Restart -> do
      let restarter =
            case _actorSupervisorStrategy actorDef of
              OneForOne -> restartSingleChild
              AllForOne -> restartAllChildren
      restarter actorDef actor actorSt child prevChildSt failedEv err
    _ -> do
      let errMsg = "FATAL: Restart Actor procedure received " ++
                   "an unexpected directive " ++ show directive
      runActorCtx $ Logger.severe errMsg
      error errMsg

removeChildActor :: forall st child. ToActorKey child
                 => Actor -> st -> child -> IO ()
removeChildActor actor actorSt child = do
  let runActorCtx = evalReadOnlyActorM actorSt actor
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

cleanupActorAndRaise :: forall st. Actor -> st -> SomeException -> IO ()
cleanupActorAndRaise actor actorSt err = do
  let runActorCtx = evalReadOnlyActorM actorSt actor
  runActorCtx $ Logger.noisyF "Failing with error '{}'" (Only $ show err)
  disposeChildren actor
  throwIO err

--------------------------------------------------------------------------------

onChildren :: (ChildActor -> IO ()) -> ParentActor -> IO ()
onChildren onChildFn parent = do
  childMap <- atomically $ readTVar $ _actorChildren parent
  mapM_ onChildFn (HashMap.elems childMap)

stopChildren :: ParentActor -> IO ()
stopChildren = onChildren (`sendChildEventToActor` ActorStopped)

disposeChildren :: ParentActor -> IO ()
disposeChildren = onChildren dispose

--------------------------------------------------------------------------------

sendToActor :: Actor -> GenericEvent -> IO ()
sendToActor actor = atomically . writeTChan (_actorGenericEvQueue actor)
{-# INLINE sendToActor #-}

sendChildEventToActor :: Actor -> ChildEvent -> IO ()
sendChildEventToActor actor = atomically . writeTChan (_actorChildEvQueue actor)
{-# INLINE sendChildEventToActor #-}

sendSupEventToActor :: Actor -> SupervisorEvent -> IO ()
sendSupEventToActor actor = atomically . writeTChan (_actorSupEvQueue actor)
{-# INLINE sendSupEventToActor #-}

--------------------------------------------------------------------------------

createOrGetActorQueues
  :: StartStrategy
  -> IO ( TChan GenericEvent
        , TChan ChildEvent
        , TChan SupervisorEvent)
createOrGetActorQueues (ViaPreStart {}) =
  (,,) <$> newTChanIO <*> newTChanIO <*> newTChanIO
createOrGetActorQueues strategy@(ViaPreRestart {}) =
  return ( _startStrategyGenericEvQueue strategy
         , _startStrategyChildEvQueue strategy
         , _startStrategySupEvQueue strategy)
{-# INLINE createOrGetActorQueues #-}

createOrGetSupChildren
  :: StartStrategy -> IO ChildrenMap
createOrGetSupChildren (ViaPreStart {}) = newTVarIO HashMap.empty
createOrGetSupChildren strategy@(ViaPreRestart {}) =
  return $  _startStrategySupChildren strategy
{-# INLINE createOrGetSupChildren #-}

--------------------------------------------------------------------------------

getRestartAttempts :: GenericActorDef -> Int
getRestartAttempts (GenericActorDef actorDef) = _actorRestartAttempt actorDef
{-# INLINE getRestartAttempts #-}

incRestartAttempt :: GenericActorDef -> IO GenericActorDef
incRestartAttempt (GenericActorDef actorDef) =
    return $ GenericActorDef
           $ actorDef { _actorRestartAttempt = succ restartAttempt }
  where
    restartAttempt = _actorRestartAttempt actorDef
{-# INLINE incRestartAttempt #-}
