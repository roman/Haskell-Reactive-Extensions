{-# LANGUAGE BangPatterns #-}
module Rx.Observable.Timer where

import Rx.Observable.Types
import Rx.Scheduler        (Async, Scheduler, newThread,
                            scheduleTimedRecursiveState)
import Tiempo              (TimeInterval)


timer' :: Scheduler Async -> TimeInterval -> Observable Async Int
timer' scheduler !interval = Observable $ \observer -> do
  scheduleTimedRecursiveState scheduler interval (0 :: Int) $ \count -> do
    onNext observer count
    return $ Just (succ count, interval)

timer :: TimeInterval -> Observable Async Int
timer = timer' newThread
