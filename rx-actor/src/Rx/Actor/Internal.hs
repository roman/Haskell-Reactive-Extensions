{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE RecordWildCards     #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Rx.Actor.Internal where

import Control.Applicative ((<$>), (<*>))

import Control.Monad (forM_, void, when)
import Control.Monad.Trans (liftIO)

import Control.Concurrent (myThreadId, yield)
import Control.Concurrent.Async (cancel, link, wait)
import Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar, takeMVar)
import Control.Concurrent.STM (TChan, TVar, atomically, modifyTVar, newTChanIO,
                               newTVarIO, orElse, readTChan, readTVar,
                               writeTChan)
import Control.Exception (SomeException (..), catch, fromException, throwIO,
                          try)

import GHC.Conc (labelThread)

import Data.Maybe (fromJust)
import Data.Typeable (typeOf)

import qualified Data.HashMap.Strict as HashMap

import Tiempo.Concurrent (threadDelay)

import Unsafe.Coerce (unsafeCoerce)

import Rx.Disposable (CompositeDisposable, Disposable, createDisposable,
                      dispose, emptyDisposable, newCompositeDisposable,
                      toDisposable)
import Rx.Observable (scanLeftItemM, subscribe, toAsyncObservable)

import qualified Rx.Disposable as Disposable
import qualified Rx.Observable as Observable

import Rx.Logger (Logger, Only (..), loudF, traceF)
import qualified Rx.Logger.Monad as Logger

-- NOTE: If using evalActorM, for some reason it throws
-- a segfault (really crazy behavior, drive with caution)
import Rx.Actor.EventBus (fromGenericEvent, typeOfEvent)
import Rx.Actor.Logger ()
import Rx.Actor.Monad (evalReadOnlyActorM, execActorM, runPreActorM)
import Rx.Actor.Types
import Rx.Actor.Util (logError, logError_)

-------------------- * Root Actor functions * ------------------------

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
  wait (_actorAsync actor)
    `catch` (\(err :: SomeException) -> do
                traceF (_actorLogger actor)
                       "Received error '{} {}' on root actor"
                       (show $ typeOf err, show err)
                throwIO err)


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


-------------------- * Core Actor functions * -----------------------

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
          _actorForker actorDef $ do
            -- GHC debugging
            myThreadId >>= (`labelThread` absoluteKey)
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


        -- IMPORTANT: The disposable creation/append has to be done
        -- after the actor thread starts. Please do not move it
        -- before that
        asyncDisposable <- createDisposable $ do

          loudF logger
                "[{}] Calling actor disposable" $
                maybe (Only absoluteKey) (const $ Only $ toActorKey actor) parent

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

        case parent of
          Nothing -> link $ _actorAsync actor
          Just _ -> return ()

        return actor
  where
    throwOnError err =
      case fromException err of
        Just (ChildTerminated _) -> return ()
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

startNewChildren :: forall st . ActorDef st -> Actor -> IO ()
startNewChildren actorDef actor = do
  let children = _actorChildrenDef actorDef
      execActor = runPreActorM actor

  execActor $ Logger.loudF "Starting actor children: {}"
                           (Only $ show children)
  forM_ children $ \gChildActorDef -> do
    _child <- startChildActor (ViaPreStart gChildActorDef) actor
    return ()


newActor :: forall st . Maybe ParentActor -> ActorDef st -> Actor -> IO Disposable
newActor parent actorDef actor = do
    eResult <-
      try
        $ runPreActorM actor
                       (do Logger.info ("Calling preStart on actor" :: String)
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
            startNewChildren actorDef actor
            startActorLoop parent actorDef actor st

---

restartActor
  :: forall st . Maybe ParentActor -> ActorDef st -> Actor -> st
  -> SomeException -> GenericEvent -> IO Disposable
restartActor parent actorDef actor oldSt err gev = do
  result <-
    logError $
       evalReadOnlyActorM oldSt actor
                          (do Logger.info ("Calling postRestart on actor" :: String)
                              unsafeCoerce $ _actorPostRestart actorDef err gev)
  case result of
    -- TODO: Do a warning with the error
    Nothing -> do
      startNewChildren actorDef actor
      startActorLoop parent actorDef actor oldSt
    Just (InitOk newSt) -> do
      startNewChildren actorDef actor
      startActorLoop parent actorDef actor newSt
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
      scanLeftItemM (actorLoop mparent actorDef actor) st0
        $ _actorEventBusDecorator actorDef
        $ Observable.repeat (getEventFromQueue actor)

    handleActorObservableError serr@(SomeException err0) = do
      let runActorCtx = evalReadOnlyActorM st0 actor
      case mparent of
        Nothing ->
          case fromException serr of
            Just (ChildTerminated {}) ->
              return ()
            Just err@(ChildFailedWithError {}) ->
              throwIO $ _supEvTerminatedError err
            Just err -> do
              let errMsg = "Unhandled SupervisorEvent received " ++ show err
              runActorCtx $ Logger.severe errMsg
            Nothing -> do
              let errMsg = "Actor loop received non-supervisor error "
                           ++ show serr
              runActorCtx $ Logger.severe errMsg
              throwIO err0
        Just parent ->
          case fromException serr of
            Just err -> sendSupEventToActor parent err
            Nothing -> do
              let errMsg =
                    "Arrived to unhandled error on actorLoop: "
                    ++ show (typeOf err0)
                    ++ " "
                    ++ show serr
              runActorCtx $ Logger.severe errMsg
              error errMsg

---

getEventFromQueue :: Actor -> IO ActorEvent
getEventFromQueue actor =
  atomically $ (ChildEvent      <$> readTChan (_actorChildEvQueue actor))
      `orElse` (SupervisorEvent <$> readTChan (_actorSupEvQueue actor))
      `orElse` (NormalEvent     <$> readTChan (_actorGenericEvQueue actor))

---

actorLoop ::
  forall st . Maybe ParentActor -> ActorDef st -> Actor
  -> st -> ActorEvent -> IO st
actorLoop _ actorDef actor st (NormalEvent gev) =
  handleGenericEvent actorDef actor st gev

actorLoop mParent actorDef actor st
          (ChildEvent (ActorRestarted failedActorKey err gev)) = do
  evalReadOnlyActorM st actor $
    case mParent of
      Just parent ->
        Logger.traceF "Restart actor from Parent {}"
                      (Only $ toActorKey parent)
      Nothing -> do
        let errMsg = "The impossible happened: root actor was reseted"
        Logger.severe errMsg
        error errMsg
  stopActorLoopAndRaise (RestartOne failedActorKey) actorDef actor err st gev

actorLoop mParent actorDef actor st (ChildEvent ActorStopped) = do
  void $ evalReadOnlyActorM st actor $ do
    case mParent of
      Just parent ->
        Logger.traceF "Stop actor from parent {}"
                      (Only $ toActorKey parent)
      Nothing ->
        Logger.trace ("Stop root actor" :: String)

    unsafeCoerce $ _actorPostStop actorDef

  stopChildren actor
  stopActorLoop actorDef

actorLoop _ actorDef actor st (SupervisorEvent ev) = do
  case ev of
    (TerminateChildFromSupervisor childKey) ->
      terminateChildFromSupervisor actor st childKey

    (ChildSpawned gChildActorDef) ->
      void $ addChildActor actor st gChildActorDef

    (ChildTerminated childKey) ->
      removeChildActor actor st childKey

    (ChildFailedOnInitialize err _) ->
      cleanupActorAndRaise actor st err

    (ChildFailedWithError child prevChildSt failedEv err directive) ->
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
    $ Logger.noisyF "[evType: {}] Receiving event"
                    (Only evType)

  sendGenericEvToChildren actor gev
  newSt <-
    case HashMap.lookup evType handlers of
      Nothing -> return st
      Just (EventHandler _ handler) -> do
        result <-
          try
            $ execActor
            $ do Logger.loudF "[evType: {}] Handling event"
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
    Logger.traceF "Catched error: '{} {}'"
                  (show $ typeOf innerErr , show err)

  let errType = show $ typeOf innerErr
      restartDirectives = _actorRestartDirective actorDef
  case HashMap.lookup errType restartDirectives of
    Nothing ->
      stopActorLoopAndRaise Restart actorDef actor err st gev
    Just (ErrorHandler errHandler) -> do
      restartDirective <-
        runActorCtx
          $ unsafeCoerce
          $ errHandler (fromJust $ fromException err)

      runActorCtx $
        Logger.traceF "Use restart directive '{}'"
                      (Only $ show restartDirective)

      case restartDirective of
        Resume -> do
          runActorCtx
            $ Logger.noisyF "[error: {} {}] Resume actor"
                            (show $ typeOf err, show err)
          return st
        Stop -> do
          stopChildren actor
          void $ runActorCtx $ do
            Logger.noisyF "[error: {} {}] Stop actor"
                          (show $ typeOf err, show err)
            unsafeCoerce $ _actorPostStop actorDef
          stopActorLoop actorDef
        Raise
          | _actorAbsoluteKey actor == "/user" -> do
            runActorCtx $
              Logger.loudF "Raise in root actor, throwing error {}"
                           (Only $ show err)
            throwIO err
        _ ->
          stopActorLoopAndRaise restartDirective actorDef actor err st gev

---

stopActorLoop :: forall st. ActorDef st -> IO st
stopActorLoop actorDef =
  throwIO $ ChildTerminated (toActorKey actorDef)

---

stopActorLoopAndRaise
  :: RestartDirective -> ActorDef st -> Actor
  -> SomeException -> st -> GenericEvent
  -> IO st
stopActorLoopAndRaise restartDirective actorDef actor err st gev = do
  let runActorCtx = evalReadOnlyActorM st actor
  restartAllChildren actorDef actor st actor st gev err

  logError_
    $ runActorCtx
    $ unsafeCoerce
    $ case restartDirective of
        Stop -> do
          Logger.info ("Calling postStop on actor" :: String)
          _actorPostStop actorDef
        Restart -> do
          Logger.info ("Calling preRestart on actor" :: String)
          _actorPreRestart actorDef err gev
        RestartOne failingActorKey
          | _actorAbsoluteKey actor /= failingActorKey ->
              _actorPreRestart actorDef err gev
          | otherwise -> return ()
        Raise -> liftIO $ throwIO err
        _ -> return ()

  runActorCtx $ Logger.noisy ("Notify parent to deal with error" :: String)
  throwIO
    ChildFailedWithError {
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
    ChildFailedOnInitialize {
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
      childKey = toActorKey gChildActorDef
  child <- spawnChildActor strategy actor
  atomically
    $ modifyTVar (_actorChildren actor)
    $ HashMap.insertWith (\_ _ -> child) childKey child
  return child

addChildActor :: forall st. Actor -> st -> GenericActorDef -> IO ChildActor
addChildActor actor actorSt gChildActorDef = do
  let runActorCtx = evalReadOnlyActorM actorSt actor
      childKey = toActorKey gChildActorDef
  runActorCtx $ Logger.noisyF "Starting new actor {}" (Only childKey)
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
                   failingActor _prevSt failedEv err = do

  children <- atomically $ readTVar $ _actorChildren actor
  forM_ (HashMap.elems children) $ \otherChild ->
    sendChildEventToActor otherChild
      $ ActorRestarted (_actorAbsoluteKey failingActor) err failedEv

restartChildActor
  :: forall st childSt. ActorDef st -> Actor -> st
  -> ChildActor -> childSt
  -> GenericEvent -> SomeException -> RestartDirective
  -> IO ()
restartChildActor actorDef actor actorSt
                  child prevChildSt
                  failedEv serr@(SomeException err0) directive = do
  let runActorCtx = evalReadOnlyActorM actorSt actor
  case directive of
    Raise -> do
      runActorCtx $
        Logger.traceF "Raised error '{} {}' from child {}"
                      ( show $ typeOf err0, show err0, toActorKey child)
      dispose child
      unsafeCoerce $ handleActorLoopError actorDef actor serr actorSt failedEv

    RestartOne _ ->
      restartSingleChild actorDef actor actorSt child prevChildSt failedEv serr

    Restart -> do
      runActorCtx $
        Logger.traceF "Restart child {} from error '{} {}'"
                     (toActorKey child, show $ typeOf err0, show err0)
      let restarter =
            case _actorSupervisorStrategy actorDef of
              OneForOne -> restartSingleChild
              AllForOne -> restartAllChildren
      restarter actorDef actor actorSt child prevChildSt failedEv serr

    _ -> do
      let errMsg = "FATAL: Restart Actor procedure received " ++
                   "an unexpected directive " ++ show directive
      runActorCtx $ Logger.severe errMsg
      error errMsg

removeChildActor :: forall st child. ToActorKey child
                 => Actor -> st -> child -> IO ()
removeChildActor actor actorSt child = do
  let runActorCtx = evalReadOnlyActorM actorSt actor
      childKey = toActorKey child
  wasRemoved <- atomically $ do
    childMap <- readTVar $ _actorChildren actor
    case HashMap.lookup childKey childMap of
      Nothing -> return False
      Just _ -> do
        modifyTVar (_actorChildren actor) $ HashMap.delete childKey
        return True
  when wasRemoved $
    runActorCtx $
      Logger.noisyF "Removing child {}" (Only childKey)

terminateChildFromSupervisor :: forall st. Actor -> st -> ChildKey -> IO ()
terminateChildFromSupervisor actor actorSt childKey = do
  let runActorCtx = evalReadOnlyActorM actorSt actor
  mChild <- lookupChild childKey actor
  case mChild of
    Nothing ->
      runActorCtx $
        Logger.warnF "Tried to stop child '{}' but it didn't exist"
                     (Only childKey)
    Just child -> do
      runActorCtx $
        Logger.noisyF "Stop child '{}' from parent" (Only childKey)
      stopChild child


cleanupActorAndRaise :: forall st. Actor -> st -> SomeException -> IO ()
cleanupActorAndRaise actor actorSt serr@(SomeException err) = do
  let runActorCtx = evalReadOnlyActorM actorSt actor
  runActorCtx
    $ Logger.loudF "Failing with error '{} {}': performing cleanup of children"
                   (show $ typeOf err, show serr)
  disposeChildren actor
  throwIO err

--------------------------------------------------------------------------------

lookupChild :: ChildKey -> Actor -> IO (Maybe ChildActor)
lookupChild childKey actor =
  atomically (HashMap.lookup childKey <$> readTVar (_actorChildren actor))
{-# INLINE lookupChild #-}

onChildren :: (ChildActor -> IO ()) -> ParentActor -> IO ()
onChildren onChildFn parent = do
  childMap <- atomically $ readTVar $ _actorChildren parent
  mapM_ onChildFn (HashMap.elems childMap)
{-# INLINE onChildren #-}

stopChild :: ChildActor -> IO ()
stopChild = (`sendChildEventToActor` ActorStopped)
{-# INLINE stopChild #-}

stopChildren :: ParentActor -> IO ()
stopChildren = onChildren stopChild
{-# INLINE stopChildren #-}

disposeChildren :: ParentActor -> IO ()
disposeChildren = onChildren dispose
{-# INLINE disposeChildren #-}

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
