module Rx.Observable.Replicate where

import Prelude hiding (replicate)

import Control.Concurrent (yield)
import Control.Monad      (forever)

import Tiempo (TimeInterval)

import Rx.Scheduler (IScheduler, Sync, currentThread, scheduleTimedRecursive)

import Rx.Observable.Timer (timer')
import Rx.Observable.Types


replicate' :: IScheduler scheduler => scheduler s -> IO a -> Observable s a
replicate' scheduler action = createObservable scheduler $ \observer ->
  forever $ (action >>= onNext observer) >> yield

replicateEvery' :: IScheduler scheduler
                => scheduler s -> TimeInterval -> IO a -> Observable s a
replicateEvery' scheduler interval action = Observable $ \observer ->
  scheduleTimedRecursive scheduler interval $ do
    action >>= onNext observer
    return $ Just interval

replicate :: IO a -> Observable Sync a
replicate = replicate' currentThread

replicateEvery :: TimeInterval -> IO a -> Observable Sync a
replicateEvery  = replicateEvery' currentThread
