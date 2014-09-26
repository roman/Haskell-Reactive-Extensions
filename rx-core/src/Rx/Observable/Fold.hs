module Rx.Observable.Fold where

import Data.IORef (atomicModifyIORef', atomicWriteIORef, newIORef, readIORef, writeIORef)
import Data.Monoid (Monoid (..))

import Rx.Observable.Types

foldLeft :: IObservable source
         => (acc -> a -> acc)
         -> acc
         -> source s a
         -> Observable s acc
foldLeft foldFn acc source =
  Observable $ \observer -> do
      accVar <- newIORef acc
      main accVar observer
    where
      main accVar observer =
          subscribe source onNext_ onError_ onCompleted_
        where
          onNext_ v = do
            atomicModifyIORef' accVar $ \acc ->
              (foldFn acc v, ())
          onError_ = onError observer
          onCompleted_ = do
            acc <- readIORef accVar
            onNext observer acc
            onCompleted observer

foldMap :: (IObservable source, Monoid b)
        => (a -> b)
        -> source s a
        -> Observable s b
foldMap toMonoid = foldLeft foldFn mempty
  where
    foldFn acc a = (acc `mappend` toMonoid a)
