{-# LANGUAGE NoImplicitPrelude #-}
module Rx.Observable.Timeout where

import Prelude.Compat

import Control.Exception (toException)
import Control.Monad (void, when)

import Tiempo (TimeInterval, seconds)

import Rx.Disposable (dispose, newBooleanDisposable,
                      newSingleAssignmentDisposable, setDisposable,
                      toDisposable)

import Rx.Scheduler (Async, Scheduler, newThread, scheduleTimed)

import Rx.Observable.Types

--------------------------------------------------------------------------------

data TimeoutOptions a
  = TimeoutOptions {
      _timeoutInterval        :: TimeInterval
    , _timeoutStartAfterFirst :: Bool
    , _completeOnTimeout      :: Bool
    , _resetTimeoutWhen       :: a -> Bool
    , _timeoutScheduler       :: Scheduler Async
    }

timeoutScheduler
  :: Scheduler Async -> TimeoutOptions a -> TimeoutOptions a
timeoutScheduler scheduler opts
  = opts { _timeoutScheduler = scheduler }

timeoutDelay
  :: TimeInterval -> TimeoutOptions a -> TimeoutOptions a
timeoutDelay interval opts
  = opts { _timeoutInterval = interval }

startAfterFirst
  :: TimeoutOptions a -> TimeoutOptions a
startAfterFirst opts
  = opts { _timeoutStartAfterFirst = True }

resetTimeoutWhen
  :: (a -> Bool) -> TimeoutOptions a -> TimeoutOptions a
resetTimeoutWhen resetQuery opts
  = opts { _resetTimeoutWhen = resetQuery }

completeOnTimeout :: TimeoutOptions a -> TimeoutOptions a
completeOnTimeout opts = opts { _completeOnTimeout = True }

--------------------------------------------------------------------------------

timeoutWith
  :: IObservable source
  => (TimeoutOptions a -> TimeoutOptions a)
  -> source Async a
  -> Observable Async a
timeoutWith modFn source =
    Observable $ \observer -> do
      sourceDisposable <- newSingleAssignmentDisposable
      timerDisposable  <- newBooleanDisposable
      subscription <-
        main sourceDisposable timerDisposable observer

      setDisposable sourceDisposable subscription

      return $ toDisposable sourceDisposable `mappend`
               toDisposable timerDisposable
  where
    defOpts = TimeoutOptions {
        _timeoutInterval = seconds 0
      , _timeoutStartAfterFirst = False
      , _completeOnTimeout = False
      , _resetTimeoutWhen = const True
      , _timeoutScheduler = newThread
      }
    opts = modFn defOpts
    scheduler = _timeoutScheduler opts
    interval  = _timeoutInterval opts
    shouldResetTimeout = _resetTimeoutWhen opts

    main sourceDisposable timerDisposable observer = do
        resetTimeout
        subscribe source onNext_ onError_ onCompleted_
      where
        onTimeout =
          if _completeOnTimeout opts
            then onCompleted observer
            else onError observer $ toException TimeoutError
        resetTimeout = do
          timer <- scheduleTimed scheduler interval $ do
            onTimeout
            void $ dispose sourceDisposable
          -- This will automatically dispose the previous timer
          setDisposable timerDisposable timer

        onNext_ v = do
          onNext observer v
          when (shouldResetTimeout v) resetTimeout
        onError_ = onError observer
        onCompleted_ = onCompleted observer

timeout
  :: IObservable source =>
     TimeInterval -> source Async a -> Observable Async a
timeout interval = timeoutWith (timeoutDelay interval)
