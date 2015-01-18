{-# LANGUAGE RankNTypes #-}
module Rx.Scheduler.SingleThread where

import Control.Monad (join, forever)
import Control.Concurrent (ThreadId, forkIO, forkOS, killThread, threadDelay, yield)
import Control.Concurrent.STM (atomically)
import qualified Control.Concurrent.STM.TChan as TChan
import Tiempo (toMicroSeconds)

import Rx.Disposable ( Disposable, IDisposable(..), ToDisposable(..)
                     , newDisposable, emptyDisposable )
import Rx.Scheduler.Types

--------------------------------------------------------------------------------

-- ^ A special Scheduler that works on a single thread, this type
-- implements both the IScheduler and the IDisposable classtypes.
data SingleThreadScheduler s
  = SingleThreadScheduler {
    _scheduler  :: Scheduler s
  , _disposable :: Disposable
  }

type Forker = IO () -> IO ThreadId

instance IScheduler SingleThreadScheduler where
  immediateSchedule = immediateSchedule . _scheduler
  timedSchedule = timedSchedule . _scheduler

instance IDisposable (SingleThreadScheduler s) where
  dispose = dispose . _disposable

instance ToDisposable (SingleThreadScheduler s) where
  toDisposable = _disposable

--------------------------------------------------------------------------------

_singleThread :: Forker -> IO (SingleThreadScheduler Async)
_singleThread fork = do
  reqChan <- TChan.newTChanIO
  tid <- fork $ forever $ do
    join $ atomically $ TChan.readTChan reqChan
    yield
  disposable <- newDisposable "Scheduler.singleThread" $ killThread tid

  let scheduler =
        Scheduler {
          _immediateSchedule = \action -> do
            atomically $ TChan.writeTChan reqChan action
            emptyDisposable

        , _timedSchedule = \interval innerAction -> do
            let action = threadDelay (toMicroSeconds interval) >> innerAction
            atomically $ TChan.writeTChan reqChan action
            emptyDisposable
        }

  return $ SingleThreadScheduler scheduler disposable

--------------------------------------------------------------------------------

-- ^ Creates a @Scheduler@ that performs work on a single unbound
-- thread
singleThread :: IO (SingleThreadScheduler Async)
singleThread = _singleThread forkIO

-- ^ Creates a @Scheduler@ that performs work on a single bound
-- thread. This is particularly useful when working with async
-- actions and FFI calls.
singleBoundThread :: IO (SingleThreadScheduler Async)
singleBoundThread = _singleThread forkOS
