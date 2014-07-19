module Rx.Actor.Monad where

import Control.Monad.Trans (MonadIO(..))
import qualified Control.Monad.State.Strict as State
import qualified Control.Monad.Reader as Reader

import Data.Typeable (Typeable)

import Rx.Observable (onNext)

import Rx.Logger (Logger)

import Rx.Actor.EventBus (toGenericEvent)
import Rx.Actor.Types

getState :: ActorM st st
getState = ActorM $ (\(st, _, _) -> st) `fmap` State.get

setState :: st -> ActorM st ()
setState st = ActorM $ do
  (_, evBus, actor) <- State.get
  State.put (st, evBus, actor)

modifyState :: (st -> st) -> ActorM st ()
modifyState fn = ActorM $ do
  (st, evBus, actor) <- State.get
  State.put (fn st, evBus, actor)

emit :: (MonadIO m, GetEventBus m, Typeable ev) => ev -> m ()
emit ev = do
  evBus <- getEventBus
  liftIO $ onNext evBus $ toGenericEvent ev

execActorM
  :: st -> EventBus -> Actor
  -> ActorM st a
  -> IO (st, EventBus, Actor)
execActorM st evBus actor (ActorM action) =
  State.execStateT action (st, evBus, actor)

runActorM
  :: st
  -> EventBus -> Actor
  -> ActorM st a
  -> IO (a, (st, EventBus, Actor))
runActorM st evBus actor (ActorM action) =
  State.runStateT action (st, evBus, actor)

runPreActorM
   :: ActorKeyVal -> EventBus -> Logger -> PreActorM a -> IO a
runPreActorM actorKey evBus logger (PreActorM action) =
  Reader.runReaderT action (actorKey, evBus, logger)
