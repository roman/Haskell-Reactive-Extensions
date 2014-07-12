module Rx.Observable.Scan where

import Control.Concurrent.STM (atomically, newTVarIO, readTVar, writeTVar)
import Rx.Observable.Types

scanLeft :: IObservable observable
         => (acc -> a -> IO acc)
         -> acc
         -> observable s a
         -> Observable s acc
scanLeft foldFn acc0 source =
  Observable $ \observer -> do
      accVar <- newTVarIO acc0
      main accVar observer
    where
      main accVar observer =
          safeSubscribe source onNext_ onError_ onCompleted_
        where
          onNext_ v = do
            acc <- atomically $ readTVar accVar
            acc' <- foldFn acc v
            atomically $ writeTVar accVar acc'
            onNext observer acc'
          onError_ = onError observer
          onCompleted_ = onCompleted observer

scanLeftWithItem
  :: IObservable observable
  => (acc -> a -> IO acc)
  -> acc
  -> observable s a
  -> Observable s (acc, a)
scanLeftWithItem foldFn acc0 source =
  Observable $ \observer -> do
      accVar <- newTVarIO acc0
      main accVar observer
    where
      main accVar observer =
          safeSubscribe source onNext_ onError_ onCompleted_
        where
          onNext_ v = do
            acc <- atomically $ readTVar accVar
            acc' <- foldFn acc v
            atomically $ writeTVar accVar acc'
            onNext observer (acc', v)
          onError_ = onError observer
          onCompleted_ = onCompleted observer
