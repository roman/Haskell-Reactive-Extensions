{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE FlexibleInstances #-}
module Rx.Observable
       ( IScheduler
       , Scheduler
       , Sync
       , Async
       , currentThread
       , newThread
       , schedule

       , IObservable (..)
       , Observable (..)
       , ConnectableObservable
       , IObserver (..)
       , ToObserver (..)
       , ToAsyncObservable (..)
       , ToSyncObservable (..)
       , newObservable
       , newObservableScheduler
       , newObserver
       , unsafeSubscribe
       , safeSubscribe
       , subscribe
       , subscribeOnNext
       , subscribeObserver

       , Observer (..)
       , Notification (..)

       , Disposable
       , dispose
       , disposeWithResult
       , newDisposable
       , emptyDisposable

       , Observable.catch
       , Observable.concat
       , Observable.concatList
       , Observable.concatMap
       , Observable.concatMapM
       , Observable.distinct
       , Observable.distinctUntilChanged
       , Observable.distinctUntilChangedWith
       , Observable.doAction
       , Observable.doOnCompleted
       , Observable.doOnError
       , Observable.filter
       , Observable.filterM
       , Observable.first
       , Observable.foldLeft
       , Observable.foldMap
       , Observable.fromList
       , Observable.interval
       , Observable.map
       , Observable.mapM
       , Observable.merge
       , Observable.mergeList
       , Observable.once
       , Observable.onErrorReturn
       , Observable.onErrorResumeNext
       , Observable.repeat
       , Observable.repeat'
       , Observable.repeatEvery
       , Observable.repeatEvery'
       , Observable.retry
       , Observable.scanLeft
       , Observable.scanLeftItem
       , Observable.scanLeftItemM
       , Observable.take
       , Observable.takeWhile
       , Observable.takeWhileM
       , Observable.throttle
       , Observable.zip
       , Observable.zipWith

       , Observable.publish
       , Observable.connect

       , Observable.timeout
       , Observable.timeoutWith
       , Observable.timeoutScheduler
       , Observable.timeoutDelay
       , Observable.startAfterFirst
       , Observable.resetTimeoutWhen
       , Observable.completeOnTimeout

       , Observable.toList
       , Observable.toMaybe
       , Observable.toEither
       ) where

import Prelude.Compat

import Control.Applicative (Alternative (..))
import Control.Exception (ErrorCall (..), toException, try)
import Control.Monad (MonadPlus (..))
import Control.Monad.Trans (MonadIO(..))

import qualified Rx.Observable.Concat   as Observable
import qualified Rx.Observable.Distinct as Observable
import qualified Rx.Observable.Do       as Observable
import qualified Rx.Observable.Either   as Observable
import qualified Rx.Observable.Error    as Observable
import qualified Rx.Observable.Filter   as Observable
import qualified Rx.Observable.First    as Observable
import qualified Rx.Observable.Fold     as Observable
import qualified Rx.Observable.Interval as Observable
import qualified Rx.Observable.List     as Observable
import qualified Rx.Observable.Map      as Observable
import qualified Rx.Observable.Maybe    as Observable
import qualified Rx.Observable.Merge    as Observable
import qualified Rx.Observable.Repeat   as Observable
import qualified Rx.Observable.Scan     as Observable
import qualified Rx.Observable.Publish  as Observable
import qualified Rx.Observable.Take     as Observable
import qualified Rx.Observable.Throttle as Observable
import qualified Rx.Observable.Timeout  as Observable
import qualified Rx.Observable.Zip      as Observable

import Rx.Disposable (Disposable, dispose, disposeWithResult, emptyDisposable, newDisposable)
import Rx.Scheduler (Async, IScheduler, Scheduler, Sync, currentThread,
                     newThread, schedule)

import Rx.Observable.Types

instance Functor (Observable s) where
  fmap = Observable.map

instance Applicative (Observable Async) where
  pure result =
    Observable $ \observer -> do
      onNext observer result
      emptyDisposable

  obF <*> obV = Observable.zipWith ($) obF obV

instance Alternative (Observable Async) where
  empty = fail "Alternative.empty"
  sourceA <|> sourceB = Observable.onErrorResumeNext sourceB sourceA

instance MonadPlus (Observable Async) where
  mzero = empty
  mplus = (<|>)

instance MonadIO (Observable Async) where
  liftIO action =
    newObservableScheduler newThread $ \observer -> do
      result <- try action
      case result of
        Right val -> onNext observer val
        Left err  -> onError observer err
      emptyDisposable

instance Monad (Observable Async) where
  fail msg =
    newObservableScheduler newThread $ \observer -> do
       onError observer
               (toException $ ErrorCall msg)
       emptyDisposable

  return result =
    newObservableScheduler newThread $ \observer -> do
      onNext observer result
      onCompleted observer
      emptyDisposable

  (>>=)  = Observable.flatMap
