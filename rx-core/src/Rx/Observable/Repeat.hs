module Rx.Observable.Repeat where

import Prelude hiding (repeat)

import Control.Concurrent (yield)
import Control.Monad      (forever)

import Tiempo (TimeInterval)

import Rx.Scheduler (IScheduler, Sync, currentThread, scheduleTimedRecursive)

import Rx.Observable.Types


repeat' :: IScheduler scheduler => scheduler s -> IO a -> Observable s a
repeat' scheduler action = newObservableScheduler scheduler $ \observer ->
  forever $ (action >>= onNext observer) >> yield

repeatEvery' :: IScheduler scheduler
                => scheduler s -> TimeInterval -> IO a -> Observable s a
repeatEvery' scheduler interval action = Observable $ \observer ->
  scheduleTimedRecursive scheduler interval $ do
    action >>= onNext observer
    return $ Just interval

repeat :: IO a -> Observable Sync a
repeat = repeat' currentThread

repeatEvery :: TimeInterval -> IO a -> Observable Sync a
repeatEvery  = repeatEvery' currentThread
