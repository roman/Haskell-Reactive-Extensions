{-# LANGUAGE BangPatterns #-}
module Rx.Scheduler
       (
         Scheduler(..)
       , IScheduler(..)
       , Sync
       , Async

       -- ^ Functions to Schedule actions
       , schedule
       , scheduleTimed
       , scheduleRecursive
       , scheduleRecursiveState
       , scheduleTimedRecursive
       , scheduleTimedRecursiveState

       -- ^ Different scheduler implementations
       , currentThread
       , newThread
       , singleThread
       , singleBoundThread
       )
       where

import Control.Monad (when)
import Tiempo (TimeInterval, seconds)

import Rx.Disposable ( Disposable
                     , newBooleanDisposable
                     , toDisposable, emptyDisposable, createDisposable)
import qualified Rx.Disposable as Disposable

import Rx.Scheduler.CurrentThread
import Rx.Scheduler.NewThread
import Rx.Scheduler.SingleThread
import Rx.Scheduler.Types

schedule :: (IScheduler scheduler) => scheduler s -> IO () -> IO Disposable
schedule = immediateSchedule

scheduleTimed ::
  (IScheduler scheduler)
  => scheduler Async
  -> TimeInterval
  -> IO ()
  -> IO Disposable
scheduleTimed = timedSchedule

scheduleRecursive :: (IScheduler scheduler) => scheduler s -> IO Bool -> IO Disposable
scheduleRecursive scheduler action = do
    outerDisp <- newBooleanDisposable
    main outerDisp
    return $ toDisposable outerDisp
  where
    main outerDisp = do
      innerDisp <- immediateSchedule scheduler $ do
          result <- action
          when result $ main outerDisp
      Disposable.set innerDisp outerDisp

scheduleRecursiveState ::
  (IScheduler scheduler)
  => scheduler s
  -> st
  -> (st -> IO (Maybe st))
  -> IO Disposable
scheduleRecursiveState scheduler !st action = do
    outerDisp <- newBooleanDisposable
    main outerDisp st
    return $ toDisposable outerDisp
  where
    main outerDisp !st = do
      innerDisp <- immediateSchedule scheduler $ do
          result <- action st
          case result of
            Nothing -> return ()
            Just newSt -> main outerDisp newSt
      Disposable.set innerDisp outerDisp

scheduleTimedRecursive ::
  (IScheduler scheduler)
  => scheduler s
  -> TimeInterval
  -> IO (Maybe TimeInterval)
  -> IO Disposable
scheduleTimedRecursive scheduler !interval action = do
    outerDisp <- newBooleanDisposable
    main outerDisp interval
    return $ toDisposable outerDisp
  where
    main outerDisp !interval = do
      innerDisp <- timedSchedule scheduler interval $ do
          result <- action
          case result of
            Nothing -> return ()
            Just newInterval -> main outerDisp newInterval
      Disposable.set innerDisp outerDisp

scheduleTimedRecursiveState ::
  (IScheduler scheduler)
  => scheduler Async
  -> TimeInterval
  -> st
  -> (st -> IO (Maybe (st, TimeInterval)))
  -> IO Disposable
scheduleTimedRecursiveState scheduler interval st action = do
    outerDisp <- newBooleanDisposable
    main outerDisp interval st
    return $ toDisposable outerDisp
  where
    main outerDisp !interval !st = do
      innerDisp <- timedSchedule scheduler interval $ do
          result <- action st
          case result of
            Nothing -> return ()
            Just (newSt, newInterval) -> main outerDisp newInterval newSt
      Disposable.set innerDisp outerDisp
