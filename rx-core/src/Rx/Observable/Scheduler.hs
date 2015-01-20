module Rx.Observable.Scheduler where

import Data.Monoid (mappend)

import Rx.Disposable (newBooleanDisposable, setDisposable, toDisposable)
import Rx.Scheduler (IScheduler, schedule)
import Rx.Observable.Types

scheduleOn :: (IScheduler scheduler, IObservable observable)
           => scheduler s
           -> observable s0 a
           -> Observable s a
scheduleOn scheduler source = Observable $ \observer -> do
  currentDisp <- newBooleanDisposable
  subDisp <- subscribe source
               (\v -> do
                 disp <- schedule scheduler (onNext observer v)
                 setDisposable currentDisp disp)
               (onError observer)
               (onCompleted observer)

  return $ toDisposable currentDisp `mappend`
           subDisp
