module Rx.Observable.Map where

import Prelude hiding (map, mapM)

import Rx.Scheduler (Async)
import qualified Rx.Observable.Merge as Observable
import Rx.Observable.Types

--------------------------------------------------------------------------------

concatMapM :: (IObservable observable)
           => (a -> IO [b])
           -> observable s a
           -> Observable s b
concatMapM mapFn source =
  Observable $ \observer -> do
    safeSubscribe source
      (\a -> do bs <- mapFn a; mapM_ (onNext observer) bs)
      (onError observer)
      (onCompleted observer)

concatMap :: (IObservable observable)
          => (a -> [b])
          -> observable s a
          -> Observable s b
concatMap mapFn = concatMapM (return . mapFn)

--------------------------------------------------------------------------------

mapM :: (IObservable observable)
     => (a -> IO b)
     -> observable s a
     -> Observable s b
mapM mapFn =
  concatMapM (\a -> return `fmap` mapFn a)

map :: (IObservable observable)
    => (a -> b)
    -> observable s a
    -> Observable s b
map mapFn =
  mapM (return . mapFn)

--------------------------------------------------------------------------------

flatMap :: (IObservable observableSource, IObservable observableResult)
        => observableSource Async a
        -> (a -> observableResult Async b)
        -> Observable Async b
flatMap source mapFn = Observable.merge $ map mapFn source
