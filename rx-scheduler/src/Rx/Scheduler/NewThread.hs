module Rx.Scheduler.NewThread where

import Control.Concurrent (forkIO, killThread, threadDelay)
import Tiempo (toMicroSeconds)
import Rx.Disposable (newDisposable)

import Rx.Scheduler.Types

newThread :: Scheduler Async
newThread = Scheduler {
    _immediateSchedule = \action -> do
     tid <- forkIO action
     newDisposable "Scheduler.newThread" $ killThread tid

  , _timedSchedule = \interval action -> do
     tid <- forkIO $ threadDelay (toMicroSeconds interval) >> action
     newDisposable "Scheduler.newThread" $ killThread tid
  }
