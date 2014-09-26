{-# LANGUAGE FlexibleInstances #-}
module Rx.Observable
       ( Scheduler
       , Sync
       , Async
       , currentThread
       , newThread

       , IObservable (..)
       , Observable (..)
       , IObserver (..)
       , ToObserver (..)
       , ToAsyncObservable (..)
       , ToSyncObservable (..)
       , unsafeSubscribe
       , subscribe
       , subscribeOnNext
       , subscribeObserver

       , Observer (..)
       , Notification (..)

       , Disposable
       , dispose

       , Observable.catch
       , Observable.concatMap
       , Observable.concatMapM
       , Observable.distinct
       , Observable.distinctUntilChanged
       , Observable.distinctUntilChangedWith
       , Observable.doAction
       , Observable.filter
       , Observable.first
       , Observable.foldLeft
       , Observable.foldMap
       , Observable.fromList
       , Observable.interval
       , Observable.map
       , Observable.mapConcurrentlyM
       , Observable.mapM
       , Observable.mapReduce
       , Observable.merge
       , Observable.mergeList
       , Observable.once
       , Observable.repeat
       , Observable.repeat'
       , Observable.repeatEvery
       , Observable.repeatEvery'
       , Observable.scanLeftM
       , Observable.scanLeft
       , Observable.scanLeftWithItemM
       , Observable.scanLeftWithItem
       , Observable.throttle

       , Observable.timeout
       , Observable.timeoutWith
       , Observable.timeoutScheduler
       , Observable.timeoutDelay
       , Observable.startAfterFirst
       , Observable.resetTimeoutWhen
       , Observable.completeOnTimeout

       , Observable.toList
       , Observable.toMaybe
       ) where

import Control.Applicative (Applicative (..))
import Control.Monad       (ap)

import qualified Rx.Observable.Distinct  as Observable
import qualified Rx.Observable.Do        as Observable
import qualified Rx.Observable.Error     as Observable
import qualified Rx.Observable.Filter    as Observable
import qualified Rx.Observable.First     as Observable
import qualified Rx.Observable.Fold      as Observable
import qualified Rx.Observable.Interval  as Observable
import qualified Rx.Observable.List      as Observable
import qualified Rx.Observable.Map       as Observable
import qualified Rx.Observable.MapReduce as Observable
import qualified Rx.Observable.Maybe     as Observable
import qualified Rx.Observable.Merge     as Observable
import qualified Rx.Observable.Repeat    as Observable
import qualified Rx.Observable.Scan      as Observable
import qualified Rx.Observable.Take      as Observable
import qualified Rx.Observable.Throttle  as Observable
import qualified Rx.Observable.Timeout   as Observable

import Rx.Disposable (Disposable, dispose)
import Rx.Scheduler  (Async, Scheduler, Sync, currentThread, newThread, schedule)

import Rx.Observable.Types

instance Functor (Observable s) where
  fmap = Observable.map

instance Applicative (Observable Async) where
  pure result =
    Observable $ \observer ->
      schedule newThread $
        onNext observer result
  (<*>) = ap

instance Monad (Observable Async) where
  return = pure
  (>>=)  = Observable.flatMap
