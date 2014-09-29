module Rx.Observable.Scan where

import Data.IORef (atomicModifyIORef', newIORef)
import Rx.Observable.Types

scanLeft :: IObservable source
         => (acc -> a -> acc)
         -> acc
         -> source s a
         -> Observable s acc
scanLeft foldFn acc0 source =
  Observable $ \observer -> do
      accVar <- newIORef acc0
      main accVar observer
    where
      main accVar observer =
          subscribe source onNext_ onError_ onCompleted_
        where
          onNext_ v = do
            newAcc <- atomicModifyIORef' accVar $ \acc ->
              let newAcc = foldFn acc v
              in (newAcc, newAcc)
            onNext observer newAcc
          onError_ = onError observer
          onCompleted_ = onCompleted observer

scanLeftItem
  :: IObservable source
  => (acc -> a -> acc)
  -> acc
  -> source s a
  -> Observable s (acc, a)
scanLeftItem foldFn acc0 source =
  Observable $ \observer -> do
      accVar <- newIORef acc0
      main accVar observer
    where
      main accVar observer =
          subscribe source onNext_ onError_ onCompleted_
        where
          onNext_ v = do
            newAcc <- atomicModifyIORef' accVar $ \acc ->
              let newAcc = foldFn acc v
              in (newAcc, newAcc)
            onNext observer (newAcc, v)
          onError_ = onError observer
          onCompleted_ = onCompleted observer
