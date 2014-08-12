{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Rx.Actor
       ( GenericEvent(..), EventBus
       , ActorBuilder, ActorM, ActorDef, Actor, RestartDirective(..), InitResult(..)
       , SupervisorStrategy(..), ActorEvent(..), Typeable, Logger
       -- ^ * Actor API
       , defActor, actorKey, preStart, postStop, preRestart, postRestart
       , onError, desc, receive, useBoundThread, decorateEventBus, startDelay
       , strategy, backoff, maxRestarts, addChild, buildChild, stopDelay
       , startRootActor, stopRootActor, joinRootActor
       -- ^ * ActorM API
       , getState, setState, modifyState, getEventBus, emit, spawnChild
       -- ^ * EventBus API
       , fromGenericEvent, toGenericEvent, emitEvent, typeOfEvent, filterEvent, mapEvent
       , newEventBus, emitOnActor
       -- ^ * Logger API
       , newLogger, Only(..)
       -- ^ * Extra API
       , liftIO,  dispose, onNext
       ) where


import Control.Monad (void)
import Control.Monad.Trans (liftIO)
import Data.Typeable (Typeable, typeOf)
import Rx.Observable (onNext, dispose)
import Rx.Logger (Logger, Only(..), newLogger)
import Rx.Logger.Monad as Logger
import Rx.Subject (newPublishSubject)

import qualified Control.Monad.State as State

import Rx.Actor.Internal
import Rx.Actor.ActorBuilder
import Rx.Actor.Monad
import Rx.Actor.EventBus
import Rx.Actor.Types

--------------------------------------------------------------------------------

newEventBus :: IO EventBus
newEventBus = newPublishSubject

emitOnActor :: Typeable ev => ev -> Actor -> IO ()
emitOnActor ev actor = do
  let runActorCtx = runPreActorM (toActorKey actor)
                                 (_actorEventBus actor)
                                 (_actorLogger actor)
  void $ runActorCtx $ Logger.noisyF "Emit event {}" (Only $ show $ typeOf ev)
  onNext (_actorEventBus actor) (toGenericEvent ev)

spawnChild :: ChildKey -> ActorBuilder childSt () -> ActorM st ()
spawnChild childKey childBuilder = ActorM $ do
  let childDef = defActor (childBuilder >> actorKey childKey)
  (_, _, actor) <- State.get
  liftIO $
    sendSupEventToActor
      actor
      (ActorSpawned $ GenericActorDef childDef)
