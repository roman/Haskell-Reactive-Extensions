module Rx.Observable.Fold where

import Control.Concurrent.STM (atomically, newTVarIO, readTVar, writeTVar)
import Rx.Observable.Types

foldLeft :: IObservable observable
         => (acc -> a -> IO acc)
         -> acc
         -> observable s a
         -> Observable s acc
foldLeft foldFn acc source =
  Observable $ \observer -> do
      accVar <- newTVarIO acc
      main accVar observer
    where
      main accVar observer =
          safeSubscribe source onNext_ onError_ onCompleted_
        where
          onNext_ v = do
            acc <- atomically $ readTVar accVar
            foldFn acc v >>= atomically . writeTVar accVar
          onError_ = onError observer
          onCompleted_ = do
            acc <- atomically $ readTVar accVar
            onNext observer acc
            onCompleted observer
