module Rx.Observable.Timeout where

import Control.Monad (when)
import Control.Exception (toException, fromException)
import Control.Concurrent.STM (atomically, newTVarIO, readTVar, writeTVar)

import Data.Time (getCurrentTime, diffUTCTime)

import Tiempo (TimeInterval, toNominalDiffTime)

import Rx.Scheduler (Async, Scheduler, scheduleTimed, newThread)

import Rx.Disposable ( dispose
                     , newBooleanDisposable
                     , newSingleAssignmentDisposable
                     , toDisposable )
import qualified Rx.Disposable as Disposable

import Rx.Observable.Types

--------------------------------------------------------------------------------

commonTimeout' :: IObservable source
               => (Observer a -> IO ())
               -> (a -> Bool)
               -> Scheduler Async
               -> TimeInterval
               -> source Async a
               -> Observable Async a
commonTimeout' onTimeout shouldResetTimeout scheduler interval source =
    Observable $ \observer -> do
      sourceDisposable  <- newSingleAssignmentDisposable
      timeoutDisposable <- newBooleanDisposable
      subscription <-
        main sourceDisposable timeoutDisposable observer

      Disposable.set subscription sourceDisposable
      return $ toDisposable sourceDisposable
  where
    main sourceDisposable timeoutDisposable observer = do
        resetTimeout
        subscribe source onNext_ onError_ onCompleted_
      where
        resetTimeout = do
          timer <- scheduleTimed scheduler interval $ do
            onTimeout observer
            dispose sourceDisposable
          -- This will automatically dispose the previos timer
          Disposable.set timer timeoutDisposable

        onNext_ v = do
          onNext observer v
          when (shouldResetTimeout v) resetTimeout
        onError_ = onError observer
        onCompleted_ = onCompleted observer


commonTimeoutAfterFirst'
  :: IObservable source
  => (Observer a -> IO ())
  -> (a -> Bool)
  -> Scheduler Async
  -> TimeInterval
  -> source Async a
  -> Observable Async a
commonTimeoutAfterFirst' onTimeout shouldResetTimeout scheduler interval source =
    Observable $ \observer -> do
      sourceDisposable <- newBooleanDisposable
      disposable <- main observer sourceDisposable
      Disposable.set disposable sourceDisposable
      return $ toDisposable sourceDisposable
  where
    main observer sourceDisposable =
        subscribe source onNext_ onError_ onCompleted_
      where
        onNext_ v = do
          onNext observer v
          when (shouldResetTimeout v) $ do
            newDisposable <-
              subscribe
                (commonTimeout' onTimeout shouldResetTimeout scheduler interval source)
                (onNext observer)
                (onError observer)
                (onCompleted observer)
            Disposable.set newDisposable sourceDisposable

        onError_ = onError observer
        onCompleted_ = onCompleted observer

completeOnTimeoutError
  :: IObservable source
  => source Async a
  -> Observable Async a
completeOnTimeoutError source =
    Observable $ \observer ->
      subscribe source
        (onNext observer)
        (onError_ observer)
        (onCompleted observer)
  where
    onError_ observer err =
      case fromException err of
        Just TimeoutError -> onCompleted observer
        Nothing -> onError observer err

--------------------------------------------------------------------------------

timeout' :: IObservable source
         => Scheduler Async
         -> TimeInterval
         -> source Async a
         -> Observable Async a
timeout' =
  commonTimeout' (`onError` (toException $ TimeoutError)) (const True)

timeoutSelect' :: IObservable source
                 => Scheduler Async
                 -> TimeInterval
                 -> (a -> Bool)
                 -> source Async a
                 -> Observable Async a
timeoutSelect' scheduler interval shouldResetTimeout =
  commonTimeout'
    (`onError` (toException $ TimeoutError)) shouldResetTimeout
    scheduler interval

timeoutAfterFirst'
  :: IObservable source
  => Scheduler Async
  -> TimeInterval
  -> source Async a
  -> Observable Async a
timeoutAfterFirst' =
  commonTimeoutAfterFirst'
    (`onError` (toException $ TimeoutError))
    (const True)

timeoutAfterFirstSelect'
  :: IObservable source
  => Scheduler Async
  -> TimeInterval
  -> (a -> Bool)
  -> source Async a
  -> Observable Async a
timeoutAfterFirstSelect' scheduler interval shouldResetTimeout =
  commonTimeoutAfterFirst'
    (`onError` (toException $ TimeoutError))
    shouldResetTimeout
    scheduler
    interval

--------------------

timeout :: IObservable source
        => TimeInterval
        -> source Async a
        -> Observable Async a
timeout = timeout' newThread

timeoutSelect
  :: IObservable source
  => TimeInterval
  -> (a -> Bool)
  -> source Async a
  -> Observable Async a
timeoutSelect = timeoutSelect' newThread

timeoutAfterFirst
  :: IObservable source
  => TimeInterval
  -> source Async a
  -> Observable Async a
timeoutAfterFirst = timeoutAfterFirst' newThread

timeoutAfterFirstSelect
  :: IObservable source
  => TimeInterval
  -> (a -> Bool)
  -> source Async a
  -> Observable Async a
timeoutAfterFirstSelect = timeoutAfterFirstSelect' newThread
