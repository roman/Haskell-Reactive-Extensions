module Rx.Scheduler.CurrentThread where

import Control.Concurrent (threadDelay)
import Tiempo             (toMilliSeconds)

import Rx.Disposable      (emptyDisposable)
import Rx.Scheduler.Types

currentThread :: Scheduler Sync
currentThread = Scheduler {
    _immediateSchedule = \action -> do
        action
        emptyDisposable

  , _timedSchedule = \interval action -> do
       threadDelay (floor $ toMilliSeconds interval)
       action
       emptyDisposable
  }
