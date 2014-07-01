{-# LANGUAGE FlexibleInstances #-}
module Rx.Observable
       ( Scheduler
       , Observable (..)
       , IObserver (..)
       , Async
       , Sync
       , subscribe
       , safeSubscribe
       , module Observable
       ) where

import Control.Applicative (Applicative(..))
import Control.Monad (ap)

import Rx.Scheduler (Scheduler, Sync, Async, newThread, schedule)
import qualified Rx.Observable.Map as Observable
import qualified Rx.Observable.Filter as Observable
import qualified Rx.Observable.Merge as Observable
import qualified Rx.Observable.Timer as Observable

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
