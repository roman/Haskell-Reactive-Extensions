{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ExistentialQuantification #-}
module Rx.Actor.Types where


import Unsafe.Coerce (unsafeCoerce)


import Control.Concurrent (ThreadId, forkIO, killThread, threadDelay, myThreadId)
import Control.Concurrent.STM ( TVar, TChan, atomically
                              , newTChanIO, readTChan, writeTChan
                              , newTVarIO, readTVar, modifyTVar, writeTVar )

import Control.Exception (SomeException, try, finally, throw)

import Control.Monad (forM_, unless, void, when)
import Control.Monad.Trans (liftIO)
import Control.Monad.State (StateT, execStateT, get)

import qualified Control.Monad.State as State

import Data.Typeable (Typeable, cast)
import Data.HashMap.Strict (HashMap)
import Data.Maybe (fromJust)

import Tiempo (TimeInterval, seconds, toMicroSeconds)

import Rx.Disposable ( BooleanDisposable, CompositeDisposable, Disposable
                     , IDisposable, IDisposableContainer, ToDisposable
                     , createDisposable, newCompositeDisposable, newBooleanDisposable
                     , emptyDisposable, dispose )
import Rx.Subject (Subject, newPublishSubject)
import Rx.Observable ( Async, IObserver(..), Observable
                     , safeSubscribe, toAsyncObservable )


import qualified Rx.Observable as Observable
import qualified Rx.Disposable as Disposable

--------------------------------------------------------------------------------


data GenericEvent = forall a . Typeable a => GenericEvent a

type ActorKeyVal = String
type ActorKey = Maybe ActorKeyVal
type ActorM st = StateT st IO
type EventBus = Subject GenericEvent
type AttemptCount = Int

data InitResult st
  = InitOk st
  | InitFailure SomeException
  deriving (Show)

instance Functor InitResult where
  fmap f (InitOk s) = InitOk (f s)
  fmap _ (InitFailure err) = InitFailure err

data EventHandler st
  = forall t . Typeable t => EventHandler String (t -> ActorM st ())

data RestartDirective
  = Stop
  | Resume
  | Raise
  | Restart
  deriving (Show, Eq, Ord)

data SupervisorStrategy
  = OneForOne
  | AllForOne
  deriving (Show, Eq, Ord)

data ActorDef st
  = ActorDef {
    _actorChildKey           :: ActorKey
  , _actorForker             :: IO () -> IO ThreadId
  , _actorPreStart           :: IO (InitResult st)
  , _actorPostStop           :: IO ()
  , _actorPreRestart         :: st -> SomeException -> GenericEvent -> IO ()
  , _actorPostRestart        :: st -> SomeException -> GenericEvent -> IO (InitResult st)
  , _actorRestartDirective   :: SomeException -> RestartDirective
  , _actorDelayAfterStart    :: TimeInterval
  , _actorReceive            :: HashMap String (EventHandler st)
  , _actorRestartAttempt     :: Int
  }

data GenericActorDef = forall st . GenericActorDef (ActorDef st)

data Actor
  = Actor {
    _sendToActor          :: GenericEvent -> IO ()
  , _actorQueue           :: TChan GenericEvent
  , _actorCleanup         :: Disposable
  , _actorDef             :: GenericActorDef
  }

instance ToDisposable Actor where
  toDisposable = Disposable.toDisposable . _actorCleanup

instance IDisposable Actor where
  dispose = Disposable.dispose . Disposable.toDisposable
  isDisposed = Disposable.isDisposed . Disposable.toDisposable

data SpawnInfo
  = NewActor {
    _spawnActorDef   :: GenericActorDef
  }
  | forall st . RestartActor {
    _spawnQueue       :: TChan GenericEvent
  , _spawnPrevState   :: st
  , _spawnError       :: SomeException
  , _spawnFailedEvent :: GenericEvent
  , _spawnActorDef    :: GenericActorDef
  , _spawnDelay       :: TimeInterval
  }

data SupervisionEvent
  = ActorSpawned { _supEvInitActorDef :: GenericActorDef }
  | ActorTerminated {
      _supEvTerminatedActorDef :: GenericActorDef
    }
  | forall st . ActorFailedWithError {
      _supEvTerminatedState       :: st
    , _supEvTerminatedFailedEvent :: GenericEvent
    , _supEvTerminatedError       :: SomeException
    , _supEvTerminatedActor       :: Actor
    , _supEvTerminatedDirective   :: RestartDirective
    }
  | ActorFailedOnInitialize {
      _supEvTerminatedError :: SomeException
    , _supEvTerminatedActor :: Actor
    }
  | ActorTerminatedByKill {
      _supEvTerminatedActorDef :: GenericActorDef
    }

data SupervisorDef
  = SupervisorDef {
    _supervisorStrategy           :: SupervisorStrategy
  , _supervisorBackoffDelayFn     :: AttemptCount -> TimeInterval
  -- ^ TODO: Move this attribute to ActorDef
  , _supervisorMaxRestartAttempts :: AttemptCount
  , _supervisorDefChildren        :: [GenericActorDef]
  }

data Supervisor
  = Supervisor {
    _supervisorDef        :: SupervisorDef
  , _supervisorEventBus   :: EventBus
  , _supervisorDisposable :: Disposable
  , _supervisorChildren   :: TVar (HashMap ActorKeyVal Actor)
  , _sendToSupervisor     :: SupervisionEvent -> IO ()
  , _supervisorJoin       :: IO ()
  }

instance IDisposable Supervisor where
  dispose = dispose . _supervisorDisposable
  isDisposed = Disposable.isDisposed . _supervisorDisposable

instance ToDisposable Supervisor where
  toDisposable = Disposable.toDisposable . _supervisorDisposable

--------------------------------------------------------------------------------

fromGenericEvent :: Typeable a => GenericEvent -> Maybe a
fromGenericEvent (GenericEvent v) = cast v

toGenericEvent :: Typeable a => a -> GenericEvent
toGenericEvent = GenericEvent

--------------------------------------------------------------------------------

getActorKey :: GenericActorDef -> String
getActorKey (GenericActorDef actorDef) =
  fromJust $ _actorChildKey actorDef

getRestartAttempts :: GenericActorDef -> Int
getRestartAttempts (GenericActorDef actorDef) = _actorRestartAttempt actorDef

incRestartAttempt :: GenericActorDef -> IO GenericActorDef
incRestartAttempt (GenericActorDef actorDef) =
    return $ GenericActorDef
           $ actorDef { _actorRestartAttempt = succ restartAttempt }
  where
    restartAttempt = _actorRestartAttempt actorDef


getRestartDelay :: GenericActorDef -> TimeInterval
getRestartDelay = error "TODO"

--------------------------------------------------------------------------------

getActorState :: ActorM a a
getActorState = State.get

setActorState :: a -> ActorM a ()
setActorState = State.put

modifyActorState :: (a -> a) -> ActorM a ()
modifyActorState = State.modify

createActorQueue :: SpawnInfo -> IO (TChan GenericEvent)
createActorQueue (NewActor {}) = newTChanIO
createActorQueue spawn@(RestartActor {}) = return $ _spawnQueue spawn
