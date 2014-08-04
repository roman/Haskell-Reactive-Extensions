{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Rx.Actor
       ( GenericEvent(..), EventBus
       , ActorBuilder, ActorM, ActorDef, Actor, RestartDirective(..), InitResult(..)
       , SupervisorStrategy(..), ActorEvent(..), Typeable, Logger
       -- ^ * Actor Builder API
       , defActor, actorKey, preStart, postStop, preRestart, postRestart
       , onError, desc, receive, useBoundThread, decorateEventBus, startDelay
       , strategy, backoff, maxRestarts, addChild, buildChild
       -- ^ * Actor message handlers API
       , getState, setState, modifyState, getEventBus, emit
       -- ^ * EventBus API
       , fromGenericEvent, toGenericEvent, emitEvent, typeOfEvent, filterEvent, mapEvent
       -- ^ * Logger API
       , newLogger, Only(..)
       -- ^ * Extra API
       , liftIO, newEventBus, emitOnActor, startRootActor, stopRootActor, dispose, onNext
       ) where


import Control.Monad (void)
import Control.Monad.Trans (liftIO)
import Data.Typeable (Typeable, typeOf)
import Rx.Observable (onNext, dispose)
import Rx.Logger (Logger, Only(..), newLogger)
import Rx.Logger.Monad as Logger
import Rx.Subject (newPublishSubject)

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
