module Rx.Observable.Scan where

import Control.Concurrent.STM (atomically, newTVarIO, readTVar, writeTVar)
import Rx.Observable.Types

scanLeftM :: IObservable source
         => (acc -> a -> IO acc)
         -> acc
         -> source s a
         -> Observable s acc
scanLeftM foldFn acc0 source =
  Observable $ \observer -> do
      accVar <- newTVarIO acc0
      main accVar observer
    where
      main accVar observer =
          subscribe source onNext_ onError_ onCompleted_
        where
          onNext_ v = do
            acc <- atomically $ readTVar accVar
            acc' <- foldFn acc v
            atomically $ writeTVar accVar acc'
            onNext observer acc'
          onError_ = onError observer
          onCompleted_ = onCompleted observer

scanLeft :: IObservable source
         => (acc -> a -> acc)
         -> acc
         -> source s a
         -> Observable s acc
scanLeft foldFn = scanLeftM (\acc a -> return $ foldFn acc a)

scanLeftWithItemM
  :: IObservable source
  => (acc -> a -> IO acc)
  -> acc
  -> source s a
  -> Observable s (acc, a)
scanLeftWithItemM foldFn acc0 source =
  Observable $ \observer -> do
      accVar <- newTVarIO acc0
      main accVar observer
    where
      main accVar observer =
          subscribe source onNext_ onError_ onCompleted_
        where
          onNext_ v = do
            acc <- atomically $ readTVar accVar
            acc' <- foldFn acc v
            atomically $ writeTVar accVar acc'
            onNext observer (acc', v)
          onError_ = onError observer
          onCompleted_ = onCompleted observer


scanLeftWithItem
  :: IObservable source
  => (acc -> a -> acc)
  -> acc
  -> source s a
  -> Observable s (acc, a)
scanLeftWithItem foldFn = scanLeftWithItemM (\acc a -> return $ foldFn acc a)
