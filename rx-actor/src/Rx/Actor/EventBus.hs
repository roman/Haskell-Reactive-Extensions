module Rx.Actor.EventBus where

import Data.Typeable (Typeable, TypeRep, cast, typeOf)
import Rx.Observable (IObserver, onNext)

import Rx.Actor.Types

emitEvent :: (IObserver o, Typeable ev) => o GenericEvent -> ev -> IO ()
emitEvent ob = onNext ob . toGenericEvent
{-# INLINE emitEvent #-}

typeOfEvent :: GenericEvent -> TypeRep
typeOfEvent (GenericEvent ev) = typeOf ev
{-# INLINE typeOfEvent #-}

fromGenericEvent :: Typeable a => GenericEvent -> Maybe a
fromGenericEvent (GenericEvent ev) = cast ev
{-# INLINE fromGenericEvent #-}

toGenericEvent :: Typeable a => a -> GenericEvent
toGenericEvent = GenericEvent
{-# INLINE toGenericEvent #-}

--------------------------------------------------------------------------------
