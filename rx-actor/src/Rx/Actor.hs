{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE RankNTypes                 #-}
{-# LANGUAGE ScopedTypeVariables        #-}
module Rx.Actor
       (
         HasActor, GetState(..)
       , GenericEvent(..), EventBus, ActorLogMsg
       , ActorBuilder, ActorM, ActorDef, Actor, RestartDirective(..), InitResult(..)
       , SupervisorStrategy(..), ActorEvent(..), Typeable, Logger
       -- ^ * Actor API
       , defActor, actorKey, preStart, postStop, preRestart, postRestart
       , onError, desc, receive, useBoundThread, decorateEventBus, startDelay
       , strategy, backoff, maxRestarts, addChild, stopDelay
       , startRootActor, stopRootActor, joinRootActor
       -- ^ * ActorM API
       , getActorKey, getEventBus, getLogger, setState, modifyState
       , emit, spawnChild, stopChild, State.put, State.get, State.modify
       , Reader.ask, actorLogMsg
       -- ^ * EventBus API
       , fromGenericEvent, toGenericEvent, emitEvent, typeOfEvent, filterEvent, mapEvent
       , newEventBus, emitOnActor, castFromGenericEvent
       -- ^ * Logger API
       , newLogger, Only(..)
       , Logger.noisy, Logger.noisyF
       , Logger.loud, Logger.loudF
       , Logger.trace, Logger.traceF
       , Logger.config, Logger.configF
       , Logger.info, Logger.infoF
       , Logger.warn, Logger.warnF
       , Logger.severe, Logger.severeF
       -- ^ * Extra API
       , MonadIO(..), dispose, onNext
       ) where


import Control.Monad (void)
import Control.Monad.Trans (MonadIO (..))
import Data.Typeable (Typeable, typeOf)
import Rx.Logger (Logger, Only (..), newLogger)
import Rx.Logger.Monad as Logger
import Rx.Observable (dispose, onNext)
import Rx.Subject (newPublishSubject)

import qualified Control.Monad.Reader as Reader
import qualified Control.Monad.State  as State

import Rx.Actor.ActorBuilder
import Rx.Actor.EventBus
import Rx.Actor.Internal hiding (stopChild)
import Rx.Actor.Monad
import Rx.Actor.Types

--------------------------------------------------------------------------------

newEventBus :: IO EventBus
newEventBus = newPublishSubject

receiveAndEmit
  :: forall a b st . (Typeable a, Typeable b)
  => (a -> ActorM st [b])
  -> ActorBuilder st
receiveAndEmit mapFn = receive $ \a -> do
  bs <- mapFn a
  mapM_ (\b -> b `seq` emit b) bs

emitOnActor :: Typeable ev => ev -> Actor -> IO ()
emitOnActor ev actor = do
  let runActorCtx = runPreActorM actor
  void $ runActorCtx $ Logger.noisyF "Emit event {}" (Only $ show $ typeOf ev)
  onNext (_actorEventBus actor) (toGenericEvent ev)
