{-# LANGUAGE BangPatterns #-}
module Rx.Observable.Interval where

import Tiempo (TimeInterval)

import Rx.Scheduler (Async, IScheduler, newThread, scheduleTimedRecursiveState)

import Rx.Observable.Types



interval' :: IScheduler scheduler
       => scheduler Async -> TimeInterval -> Observable Async Int
interval' scheduler !intervalDelay =
  Observable $ \observer -> do
    scheduleTimedRecursiveState
      scheduler intervalDelay (0 :: Int) $ \count -> do
        onNext observer count
        return $ Just (succ count, intervalDelay)

interval :: TimeInterval -> Observable Async Int
interval = interval' newThread
