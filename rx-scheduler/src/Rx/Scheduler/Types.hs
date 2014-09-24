{-# LANGUAGE EmptyDataDecls #-}
module Rx.Scheduler.Types where

import Rx.Disposable (Disposable)
import Tiempo (TimeInterval)

data Async
data Sync

data Scheduler s
  = Scheduler {
    _immediateSchedule :: IO () -> IO Disposable
  , _timedSchedule     :: TimeInterval -> IO () -> IO Disposable
  }


class IScheduler scheduler where
  immediateSchedule :: scheduler s -> IO () -> IO Disposable
  timedSchedule     :: scheduler s -> TimeInterval -> IO () -> IO Disposable

instance IScheduler Scheduler where
  immediateSchedule = _immediateSchedule
  timedSchedule = _timedSchedule
