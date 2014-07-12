module Rx.Actor.EventBus where

import Data.Typeable (Typeable, TypeRep, cast, typeOf)
import Rx.Observable (IObserver, IObservable, Observable, onNext)

import qualified Rx.Observable as Observable

import Rx.Actor.Types

--------------------------------------------------------------------------------

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

mapEvent :: (IObservable observable, Typeable a, Typeable b)
         => (a -> b)
         -> observable s GenericEvent
         -> Observable s GenericEvent
mapEvent fn = Observable.map castEvent
  where
    castEvent gev =
      case fromGenericEvent gev of
        Just ev -> toGenericEvent $ fn ev
        Nothing -> gev

filterEvent :: (IObservable observable, Typeable a)
            => (a -> Bool)
            -> observable s GenericEvent
            -> Observable s GenericEvent
filterEvent fn = Observable.filter castEvent
  where
    castEvent gev =
      case fromGenericEvent gev of
        Just ev -> fn ev
        Nothing -> True
