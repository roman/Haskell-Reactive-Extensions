{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module Rx.Actor.Monad where

import Control.Concurrent.STM (atomically, writeTChan)

import Control.Monad (liftM)
import Control.Monad.Trans (MonadIO (..))
import qualified Control.Monad.Reader       as Reader
import qualified Control.Monad.State.Strict as State

import Data.Typeable (Typeable)

import Rx.Observable (onNext)

import Rx.Logger (Logger)

import Rx.Actor.ActorBuilder (ActorBuilder, actorKey, defActor)
import Rx.Actor.EventBus (toGenericEvent)
import Rx.Actor.Types

--------------------------------------------------------------------------------

getEventBus :: (Monad m, HasActor m) => m EventBus
getEventBus = _actorEventBus `liftM` getActor

getActorKey :: (Monad m, HasActor m) => m ActorKey
getActorKey = _actorAbsoluteKey `liftM` getActor

getLogger :: (Monad m, HasActor m) => m Logger
getLogger = _actorLogger `liftM` getActor

sendSupervisionEvent :: (MonadIO m, HasActor m) => SupervisorEvent -> m ()
sendSupervisionEvent ev = do
  actor <- getActor
  liftIO . atomically $ writeTChan (_actorSupEvQueue actor) ev


modifyState :: (st -> st) -> ActorM st ()
modifyState fn = ActorM $ do
  (st, actor) <- State.get
  State.put (fn st, actor)

emit :: (MonadIO m, HasActor m, Typeable ev) => ev -> m ()
emit ev = do
  evBus <- getEventBus
  liftIO $ onNext evBus $ toGenericEvent ev

spawnChild :: (MonadIO m, HasActor m)
           => ChildKey -> ActorBuilder childSt -> m ()
spawnChild childKey childBuilder = do
  let childDef = defActor (childBuilder >> actorKey childKey)
  sendSupervisionEvent (ActorSpawned $ GenericActorDef childDef)

stopChild :: (MonadIO m, HasActor m)
          => ChildKey -> m ()
stopChild childKey =
  sendSupervisionEvent (TerminateChildFromSupervisor childKey)

--------------------------------------------------------------------------------

execActorM
  :: st -> Actor
  -> ActorM st a
  -> IO (st, Actor)
execActorM st actor (ActorM action) =
  State.execStateT action (st, actor)

evalActorM
  :: st -> Actor
  -> ActorM st a
  -> IO a
evalActorM st actor (ActorM action) =
  State.evalStateT action (st, actor)

runActorM
  :: st
  -> Actor
  -> ActorM st a
  -> IO (a, (st, Actor))
runActorM st actor (ActorM action) =
  State.runStateT action (st, actor)

evalReadOnlyActorM
  :: st -> Actor -> RO_ActorM st a -> IO a
evalReadOnlyActorM st actor (RO_ActorM action) =
  evalActorM st actor action

runPreActorM
   :: Actor -> PreActorM a -> IO a
runPreActorM actor (PreActorM action) =
  Reader.runReaderT action actor
