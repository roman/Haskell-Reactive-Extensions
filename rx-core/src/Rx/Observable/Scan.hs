module Rx.Observable.Scan where

import Control.Concurrent (modifyMVar, newMVar)
import Data.IORef (atomicModifyIORef', newIORef)
import Rx.Observable.Types

scanLeft
  :: (acc -> a -> acc)
     -> acc
     -> Observable s a
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
  :: (acc -> a -> acc)
     -> acc
     -> Observable s a
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

scanLeftItemM
  :: (acc -> a -> IO acc)
     -> acc
     -> Observable s a
     -> Observable s (acc, a)
scanLeftItemM foldFn acc0 source =
  Observable $ \observer -> do
      accVar <- newMVar acc0
      main accVar observer
    where
      main accVar observer =
          subscribe source onNext_ onError_ onCompleted_
        where
          onNext_ v = do
            newAcc <- modifyMVar accVar $ \acc -> do
              newAcc <- foldFn acc v
              return (newAcc, newAcc)
            onNext observer (newAcc, v)
          onError_ = onError observer
          onCompleted_ = onCompleted observer
