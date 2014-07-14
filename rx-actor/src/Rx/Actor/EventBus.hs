{-# LANGUAGE ExistentialQuantification #-}
module Rx.Actor.EventBus where

import Control.Exception (throwIO)
import Data.Maybe (fromJust)
import Data.Typeable (Typeable, cast, typeOf)


import qualified Data.HashMap.Strict as HashMap
import qualified Data.Set as Set

import Rx.Observable ( Disposable, IObserver, IObservable, Observable
                     , onNext, safeSubscribe, toAsyncObservable )
import qualified Rx.Observable as Observable

import Rx.Actor.Util (getHandlerParamType1)
import Rx.Actor.Types

--------------------------------------------------------------------------------

data MatchHandler = forall ev . Typeable ev => MatchHandler (ev -> IO ())

match :: Typeable ev => (ev -> IO ()) -> MatchHandler
match = MatchHandler

handleEvents :: EventBus -> [MatchHandler] -> IO Disposable
handleEvents eventBus handlers = do
    safeSubscribe (toAsyncObservable eventBus)
                  handleEvent
                  throwIO
                  (return ())
  where
    handlerMap = toHandlerMap handlers
    toHandlerMap = foldr (flip appendHandler) HashMap.empty
    appendHandler acc handler@(MatchHandler handlerFn) =
      case getHandlerParamType1 handlerFn of
        Just evType -> HashMap.insertWith (\_ _ -> handler) evType handler acc
        Nothing     -> acc
    handleEvent gev =
      case HashMap.lookup (typeOfEvent gev) handlerMap of
        Just (MatchHandler handlerFn) -> handlerFn $ fromJust $ fromGenericEvent gev
        Nothing -> return ()

--------------------------------------------------------------------------------

emitEvent :: (IObserver o, Typeable ev) => o GenericEvent -> ev -> IO ()
emitEvent ob = onNext ob . toGenericEvent
{-# INLINE emitEvent #-}

typeOfEvent :: GenericEvent -> String
typeOfEvent (GenericEvent ev) = show $ typeOf ev
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

filterActorEvents :: (IObservable observable)
                  => ActorDef st
                  -> observable s GenericEvent
                  -> Observable s GenericEvent
filterActorEvents actorDef = Observable.filter doesActorHandlesEvent
  where
    actorHandlerTypes = Set.fromList . HashMap.keys $ _actorReceive actorDef
    doesActorHandlesEvent gev = Set.member (typeOfEvent gev) actorHandlerTypes

--------------------------------------------------------------------------------
