{-# LANGUAGE BangPatterns #-}
module Rx.Observable.Interval where

import Rx.Observable.Types
import Rx.Scheduler        (Async, IScheduler, newThread,
                            scheduleTimedRecursiveState)
import Tiempo              (TimeInterval)


interval' :: IScheduler scheduler
       => scheduler Async -> TimeInterval -> Observable Async Int
interval' scheduler !interval = Observable $ \observer -> do
  scheduleTimedRecursiveState scheduler interval (0 :: Int) $ \count -> do
    onNext observer count
    return $ Just (succ count, interval)

interval :: TimeInterval -> Observable Async Int
interval = interval' newThread
