module Rx.Observable.Fold where

import Data.Monoid (Monoid(..))
import Control.Concurrent.STM (atomically, newTVarIO, readTVar, writeTVar)
import Rx.Observable.Types

foldLeftM :: IObservable observable
         => (acc -> a -> IO acc)
         -> acc
         -> observable s a
         -> Observable s acc
foldLeftM foldFn acc source =
  Observable $ \observer -> do
      accVar <- newTVarIO acc
      main accVar observer
    where
      main accVar observer =
          subscribe source onNext_ onError_ onCompleted_
        where
          onNext_ v = do
            acc <- atomically $ readTVar accVar
            foldFn acc v >>= atomically . writeTVar accVar
          onError_ = onError observer
          onCompleted_ = do
            acc <- atomically $ readTVar accVar
            onNext observer acc
            onCompleted observer

foldLeft :: IObservable observable
         => (acc -> a -> acc)
         -> acc
         -> observable s a
         -> Observable s acc
foldLeft foldFn = foldLeftM (\acc a -> return $ foldFn acc a)



foldMapM :: (IObservable source, Monoid b)
        => (a -> IO b)
        -> source s a
        -> Observable s b
foldMapM toMonoid = foldLeftM foldFn mempty
  where
    foldFn acc a = toMonoid a >>= return . (acc `mappend`)


foldMap :: (IObservable source, Monoid b)
        => (a -> b)
        -> source s a
        -> Observable s b
foldMap fn = foldMapM (return . fn)
