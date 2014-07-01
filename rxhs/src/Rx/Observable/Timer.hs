{-# LANGUAGE BangPatterns #-}
module Rx.Observable.Timer where

import Tiempo (TimeInterval)
import Rx.Scheduler (Scheduler, Async, newThread, scheduleTimedRecursiveState)
import Rx.Observable.Types


timerWithScheduler :: Scheduler Async -> TimeInterval -> Observable Async Int
timerWithScheduler scheduler !interval = Observable $ \observer -> do
  scheduleTimedRecursiveState scheduler interval (0 :: Int) $ \count -> do
    onNext observer count
    return $ Just (succ count, interval)


timer :: TimeInterval -> Observable Async Int
timer = timerWithScheduler newThread
