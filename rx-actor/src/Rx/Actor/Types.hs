{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE ExistentialQuantification #-}
module Rx.Actor.Types where

import Control.Concurrent.Async (Async)
import Control.Concurrent.STM (TVar, TChan)

import Control.Exception (Exception, SomeException)

import Control.Applicative (Applicative)
import Control.Monad.Trans (MonadIO(..))
import Control.Monad.Reader (ReaderT)
import Control.Monad.State.Strict (StateT)

import qualified Control.Monad.Reader as Reader
import qualified Control.Monad.State.Strict as State

import Data.Monoid (mappend)
import Data.Typeable (Typeable)
import Data.HashMap.Strict (HashMap)
import Data.Maybe (fromMaybe)

import qualified Data.Text.Lazy as LText

import Tiempo (TimeInterval)

import Rx.Disposable ( Disposable, IDisposable, ToDisposable
                     , dispose )

import Rx.Logger (Logger, ToLogger(..), ToLogMsg(..))

import Rx.Subject (Subject)
import Rx.Observable (Observable, Sync)

import qualified Rx.Disposable as Disposable

--------------------------------------------------------------------------------
-- * class definitions

class HasActor m where
  getActor :: m Actor

class GetState st m | m -> st where
  getState :: m st

class ToActorKey actor where
  toActorKey :: actor -> String

--------------------------------------------------------------------------------
-- * type definitions

type MActorKey = Maybe ActorKey
type EventBus = Subject GenericEvent
type ActorKey = String
type ChildKey = ActorKey
type AttemptCount = Int
type EventBusDecorator =
  Observable Sync ActorEvent -> Observable Sync ActorEvent

data GenericEvent = forall a . Typeable a => GenericEvent a

data ActorLogMsg =
  forall payload . ToLogMsg payload =>
  ActorLogMsg { _actorLogMsgActorKey :: !ActorKey
              , _actorLogMsgPayload  :: !payload }
  deriving (Typeable)

actorLogMsg :: ToLogMsg payload => ActorKey -> payload -> ActorLogMsg
actorLogMsg = ActorLogMsg

data EventHandler st
  = forall t . Typeable t => EventHandler String (t -> ActorM st ())

data ErrorHandler st
  = forall e . (Typeable e, Exception e)
    => ErrorHandler (e -> RO_ActorM st RestartDirective)

data InitResult st
  = InitOk st
  | InitFailure SomeException
  deriving (Show, Typeable)

data RestartDirective
  = Stop
  | Resume
  | Raise
  | Restart
  | RestartOne
  deriving (Show, Eq, Ord, Typeable)

data ChildEvent
  = ActorRestarted
    { _ctrlEvError       :: !SomeException
    , _ctlrEvFailedEvent :: !GenericEvent }
  | ActorStopped
  deriving (Typeable)

data SupervisorEvent
  = ActorSpawned { _supEvInitActorDef :: !GenericActorDef }
  | ActorTerminated {
      _supEvTerminatedActorDef :: !GenericActorDef
    }
  | forall st . ActorFailedWithError {
      _supEvTerminatedActor       :: !Actor
    , _supEvTerminatedState       :: !st
    , _supEvTerminatedFailedEvent :: !GenericEvent
    , _supEvTerminatedError       :: !SomeException
    , _supEvTerminatedDirective   :: !RestartDirective
    }
  | ActorFailedOnInitialize {
      _supEvTerminatedError :: !SomeException
    , _supEvTerminatedActor :: !Actor
    }
  deriving (Typeable)

data ActorEvent
  = NormalEvent     !GenericEvent
  | ChildEvent      !ChildEvent
  | SupervisorEvent !SupervisorEvent
  deriving (Typeable)

--------------------

newtype ActorM st a
  = ActorM { fromActorM :: StateT (st, Actor) IO a }
  deriving (Functor, Applicative, Monad, MonadIO, Typeable)

newtype RO_ActorM st a
  = RO_ActorM { fromRoActorM :: ActorM st a }
  deriving (Functor, Applicative, Monad, MonadIO, Typeable)

newtype PreActorM a
   = PreActorM { fromPreActorM :: ReaderT Actor IO a }
   deriving (Functor, Applicative, Monad, MonadIO, Typeable)

--------------------

data ActorDef st
  = ActorDef {
    _actorChildKey :: !(Maybe ActorKey)
  , _actorForker   :: !(IO () -> IO (Async ()))

  , _actorPreStart  :: PreActorM (InitResult st)
  , _actorPostStop  :: !(RO_ActorM st ())
  , _actorStopDelay :: !TimeInterval

  , _actorPreRestart
      :: !(SomeException -> GenericEvent -> RO_ActorM st ())
  , _actorPostRestart
      :: !(SomeException -> GenericEvent -> RO_ActorM st (InitResult st))

  , _actorDelayAfterStart   :: !TimeInterval
  , _actorRestartAttempt    :: !Int
  , _actorRestartDirective  :: !(HashMap String (ErrorHandler st))
  , _actorReceive           :: !(HashMap String (EventHandler st))
  , _actorEventBusDecorator :: !EventBusDecorator

  -- * supervision fields
  , _actorSupervisorStrategy           :: !SupervisorStrategy
  , _actorSupervisorBackoffDelayFn    :: !(AttemptCount -> TimeInterval)
  , _actorSupervisorMaxRestartAttempts :: !AttemptCount
  , _actorChildrenDef                  :: ![GenericActorDef]
  }
  deriving (Typeable)

data GenericActorDef = forall st . GenericActorDef (ActorDef st)

type ActorChildren = HashMap ActorKey Actor

data Actor
  = Actor {
    _actorAbsoluteKey    :: !ActorKey
  , _actorAsync          :: !(Async ())
  , _actorGenericEvQueue :: !(TChan GenericEvent)
  , _actorChildEvQueue   :: !(TChan ChildEvent)
  , _actorSupEvQueue     :: !(TChan SupervisorEvent)
  , _actorDef            :: !GenericActorDef
  , _actorDisposable     :: !Disposable
  , _actorEventBus       :: !EventBus -- ^ Event Bus with handlers filtering
  , _actorLogger         :: !Logger
  , _actorChildren       :: !(TVar ActorChildren)
  }
  deriving (Typeable)

type ParentActor = Actor
type ChildActor = Actor
type FailingActor = Actor
type ChildrenMap = TVar (HashMap ActorKey Actor)

data StartStrategy
  = ViaPreStart {
    _startStrategyActorDef   :: !GenericActorDef
  }
  | forall st . ViaPreRestart {
    _startStrategyPrevState      :: !st
  , _startStrategyGenericEvQueue :: !(TChan GenericEvent)
  , _startStrategyChildEvQueue   :: !(TChan ChildEvent)
  , _startStrategySupEvQueue     :: !(TChan SupervisorEvent)
  , _startStrategySupChildren    :: !ChildrenMap
  , _startStrategyError          :: !SomeException
  , _startStrategyFailedEvent    :: !GenericEvent
  , _startStrategyActorDef       :: !GenericActorDef
  , _startStrategyDelay          :: !TimeInterval
  }
  deriving (Typeable)

data SupervisorStrategy
  = OneForOne
  | AllForOne
  deriving (Show, Eq, Ord, Typeable)

--------------------------------------------------------------------------------
-- * instance definitions

instance Functor InitResult where
  fmap f (InitOk s) = InitOk (f s)
  fmap _ (InitFailure err) = InitFailure err

--------------------

_getActor
  :: State.StateT (st, Actor) IO Actor
_getActor = State.get >>= \(_, actor) -> return actor

_getState
  :: State.StateT (st,  Actor) IO st
_getState = State.get >>= \(st, _) -> return st

setState :: st -> ActorM st ()
setState st = ActorM $ do
  (_, actor) <- State.get
  State.put (st, actor)

instance GetState st (ActorM st) where
  getState = ActorM _getState

instance HasActor (ActorM st) where
  getActor = ActorM _getActor

instance State.MonadState st (ActorM st) where
  get = getState
  put st = setState st

instance Reader.MonadReader st (ActorM st) where
  ask = getState
  local modFn (ActorM action) =
    ActorM . State.StateT $ \(st, actor) ->
      State.runStateT action (modFn st, actor)

--------------------

deriving instance HasActor (RO_ActorM st)
deriving instance Reader.MonadReader st (RO_ActorM st)
instance GetState st (RO_ActorM st) where
  getState = RO_ActorM getState

--------------------

instance HasActor PreActorM where
  getActor = PreActorM Reader.ask

--------------------

instance ToActorKey String where
  toActorKey = id

instance ToActorKey a => ToActorKey (a, b) where
  toActorKey (actorKey, _) = toActorKey actorKey

instance ToActorKey a => ToActorKey (a, b, c) where
  toActorKey (actorKey, _, _) = toActorKey actorKey

instance ToActorKey (ActorDef st) where
  toActorKey actor =
    fromMaybe "root" (_actorChildKey actor)

instance Show (ActorDef st) where
  show = toActorKey

instance ToActorKey GenericActorDef where
  toActorKey (GenericActorDef actorDef) = toActorKey actorDef

instance Show GenericActorDef where
  show = toActorKey

instance ToActorKey Actor where
  toActorKey = _actorAbsoluteKey

instance ToLogger Actor where
  toLogger = _actorLogger

instance IDisposable Actor where
  dispose = dispose . _actorDisposable
  isDisposed = Disposable.isDisposed . _actorDisposable

instance ToDisposable Actor where
  toDisposable = Disposable.toDisposable . _actorDisposable

--------------------

instance Show SupervisorEvent where
  show (ActorSpawned gActorDef) =
    "ActorSpawned " ++ toActorKey gActorDef
  show (ActorTerminated gActorDef) =
    "ActorTerminated " ++ toActorKey gActorDef
  show supEv@(ActorFailedWithError {}) =
    let actorKey = toActorKey . _actorDef $ _supEvTerminatedActor supEv
        actorErr = _supEvTerminatedError supEv
    in "ActorFailedWithError " ++ actorKey ++ " " ++ show actorErr
  show supEv@(ActorFailedOnInitialize {}) =
    let actorKey = toActorKey . _actorDef $ _supEvTerminatedActor supEv
        actorErr = _supEvTerminatedError supEv
    in "ActorFailedOnInitialize " ++ actorKey ++ " " ++ show actorErr

instance Exception SupervisorEvent

--------------------

instance Show StartStrategy where
  show (ViaPreStart gActorDef) = "ViaPreStart " ++ show gActorDef
  show strategy@(ViaPreRestart {}) =
    "ViaPreRestart " ++ show (_startStrategyActorDef strategy)

--------------------

deriving instance Show ActorLogMsg

instance ToLogMsg ActorLogMsg where
  toLogMsg (ActorLogMsg actorKey payload0) =
    let payload = toLogMsg payload0
        sep = case LText.head payload of
                '[' -> ""
                ' ' -> ""
                _ -> " "
    in mappend (toLogMsg $ "[" ++ actorKey ++ "]" ++ sep)
               payload

--------------------------------------------------------------------------------
