module Rx.Actor.Monad where

import Control.Monad.Trans (liftIO)
import qualified Control.Monad.State.Strict as State

import Data.Typeable (Typeable)

import Rx.Observable (onNext)

import Rx.Actor.Types

getState :: ActorM st st
getState = ActorM $ fst `fmap` State.get

setState :: st -> ActorM st ()
setState st = ActorM $ do
  (_, evBus) <- State.get
  State.put (st, evBus)

modifyState :: (st -> st) -> ActorM st ()
modifyState fn = ActorM $ do
  (st, evBus) <- State.get
  State.put (fn st, evBus)

getEventBus :: ActorM st EventBus
getEventBus = ActorM $ snd `fmap` State.get

emit :: Typeable ev => ev -> ActorM st ()
emit ev = ActorM $ do
  (_, evBus) <- State.get
  liftIO $ onNext evBus $ toGenericEvent ev
