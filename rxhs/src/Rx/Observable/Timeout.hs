module Rx.Observable.Timeout where

import Data.Time (getCurrentTime, diffUTCTime)
import Control.Concurrent.STM (atomically, newTVarIO, readTVar, writeTVar)

import Tiempo (TimeInterval, toNominalDiffTime)

import Rx.Observable.Types

import Rx.Scheduler (Async, Scheduler, scheduleTimed, newThread)

import Rx.Disposable ( dispose
                     , newBooleanDisposable
                     , newSingleAssignmentDisposable )
import qualified Rx.Disposable as Disposable

--------------------------------------------------------------------------------

commonTimeout' :: IObservable observable
               => (Observer a -> IO ())
               -> Scheduler Async
               -> TimeInterval
               -> observable Async a
               -> Observable Async a
commonTimeout' onReset scheduler interval source = Observable $ \observer -> do
    sourceDisposable  <- newSingleAssignmentDisposable
    timeoutDisposable <- newBooleanDisposable
    subscription <-
      main sourceDisposable timeoutDisposable observer

    Disposable.set subscription sourceDisposable
    return $ Disposable.toDisposable sourceDisposable
  where
    main sourceDisposable timeoutDisposable observer = do
        resetTimeout
        safeSubscribe source onNext_ onError_ onCompleted_
      where
        resetTimeout = do
          timer <- scheduleTimed scheduler interval $ do
            onReset observer
            dispose sourceDisposable
          Disposable.set timer timeoutDisposable

        onNext_ v = do
          onNext observer v
          resetTimeout
        onError_ = onError observer
        onCompleted_ = onCompleted observer

completeTimeout' :: IObservable observable
                 => Scheduler Async
                 -> TimeInterval
                 -> observable Async a
                 -> Observable Async a
completeTimeout' = commonTimeout' onCompleted

completeTimeout :: IObservable observable
                => TimeInterval
                -> observable Async a
                -> Observable Async a
completeTimeout = completeTimeout' newThread
