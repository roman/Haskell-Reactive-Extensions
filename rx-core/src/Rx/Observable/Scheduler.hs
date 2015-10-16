{-# LANGUAGE NoImplicitPrelude #-}
module Rx.Observable.Scheduler where

import Prelude.Compat

import Rx.Disposable (newBooleanDisposable, setDisposable, toDisposable)
import Rx.Scheduler (Scheduler, schedule)
import Rx.Observable.Types

scheduleOn
  :: Scheduler s
    -> Observable s0 a
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
