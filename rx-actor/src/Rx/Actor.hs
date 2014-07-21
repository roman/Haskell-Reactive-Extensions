{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Rx.Actor
       ( GenericEvent, EventBus
       , ActorBuilder, ActorM, ActorDef, Actor, RestartDirective(..), InitResult(..)
       , SupervisorBuilder, SupervisorStrategy(..), SupervisorDef, Supervisor
       , ActorEvent(..), Typeable
       -- ^ * Actor Builder API
       , defActor, actorKey, preStart, postStop, preRestart, postRestart
       , onError, desc, receive, useBoundThread, decorateEventBus, startDelay
       -- ^ * Actor message handlers API
       , getState, setState, modifyState, getEventBus, emit
       -- ^ * SupervisorBuilder API
       , defSupervisor, strategy, backoff, maxRestarts, addChild, buildChild
       -- ^ * Supervisor API
       , startSupervisor, stopSupervisor
       , startSupervisorWithEventBus
       , startSupervisorWithLogger
       , startSupervisorWithEventBusAndLogger
       , emitEventToSupervisor, joinSupervisorThread
       -- ^ * EventBus API
       , fromGenericEvent, toGenericEvent, emitEvent, typeOfEvent, filterEvent, mapEvent
       -- ^ * Logger API
       , module Logger, Only(..)
       ) where

import Data.Typeable (Typeable)
import Rx.Logger (Only(..))
import Rx.Logger.Monad as Logger
import Rx.Actor.ActorBuilder
import Rx.Actor.Monad
import Rx.Actor.EventBus
import Rx.Actor.Supervisor
import Rx.Actor.Supervisor.SupervisorBuilder
import Rx.Actor.Types

--------------------------------------------------------------------------------
