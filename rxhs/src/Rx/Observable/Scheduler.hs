module Rx.Observable.Scheduler where

import Rx.Scheduler (IScheduler, schedule)

import Rx.Disposable (newBooleanDisposable, newCompositeDisposable, toDisposable)
import qualified Rx.Disposable as Disposable
import Rx.Observable.Types

scheduleOn :: (IScheduler scheduler, IObservable observable)
           => scheduler s
           -> observable s0 a
           -> Observable s a
scheduleOn scheduler source = Observable $ \observer -> do
  allDisp <- newCompositeDisposable
  currentDisp <- newBooleanDisposable
  subDisp <- subscribe source
               (\v -> do
                 disp <- schedule scheduler (onNext observer v)
                 Disposable.set disp currentDisp)
               (onError observer)
               (onCompleted observer)
  Disposable.append subDisp allDisp
  Disposable.append currentDisp allDisp
  return $ toDisposable allDisp
