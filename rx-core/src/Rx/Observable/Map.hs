module Rx.Observable.Map where

import Prelude hiding (map, mapM)

import Rx.Scheduler (Async)
import qualified Rx.Observable.Merge as Observable
import Rx.Observable.Types

--------------------------------------------------------------------------------

concatMapM :: (a -> IO [b])
           -> Observable s a
           -> Observable s b
concatMapM mapFn source =
  Observable $ \observer -> do
    subscribe source
      (\a -> do bs <- mapFn a; mapM_ (onNext observer) bs)
      (onError observer)
      (onCompleted observer)

concatMap :: (a -> [b])
          -> Observable s a
          -> Observable s b
concatMap mapFn = concatMapM (return . mapFn)

--------------------------------------------------------------------------------

mapM :: (a -> IO b)
     -> Observable s a
     -> Observable s b
mapM mapFn =
  concatMapM (\a -> return `fmap` mapFn a)

map :: (a -> b)
    -> Observable s a
    -> Observable s b
map mapFn =
  mapM (return . mapFn)

--------------------------------------------------------------------------------

flatMap :: Observable Async a
        -> (a -> Observable Async b)
        -> Observable Async b
flatMap source mapFn = Observable.merge $ map mapFn source
