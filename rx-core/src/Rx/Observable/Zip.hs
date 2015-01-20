{-# LANGUAGE RankNTypes #-}
module Rx.Observable.Zip where

import Prelude hiding (zip, zipWith)

import Data.Monoid (mappend)

import Control.Concurrent (yield)
import Control.Concurrent.STM (TQueue, atomically, isEmptyTQueue, modifyTVar,
                               newTQueueIO, newTVarIO, readTQueue, readTVar,
                               writeTQueue, writeTVar)
import Control.Monad (unless, when)

import Rx.Scheduler (Async)

import Rx.Observable.Types


zipWith :: (IObservable sourceA, IObservable sourceB)
        => (a -> b -> c)
        -> sourceA Async a
        -> sourceB Async b
        -> Observable Async c
zipWith zipFn sourceA sourceB = Observable $ \observer -> do
    queue1 <- newTQueueIO
    queue2 <- newTQueueIO

    isCompletedVar <- newTVarIO False
    completedCountVar <- newTVarIO (0 :: Int)

    main observer
         queue1 queue2
         isCompletedVar completedCountVar
  where
    next :: forall a . TQueue a -> IO a
    next = atomically . readTQueue

    conj :: forall a . TQueue a -> a -> IO ()
    conj queue a = atomically $ writeTQueue queue a
    isEmpty = isEmptyTQueue

    main observer
         queue1 queue2
         isCompletedVar completedCountVar = do

        disposableA <-
          subscribe sourceA onNextA
                            onError_
                            onCompleted_

        disposableB <-
          subscribe sourceB onNextB
                            onError_
                            onCompleted_

        return $ disposableB `mappend` disposableA
      where
        whileNotCompleted action = do
          wasCompleted <- atomically $ readTVar isCompletedVar
          unless wasCompleted $ action

        isAnyQueueEmpty = atomically $ do
          q1IsEmpty <- isEmpty queue1
          q2IsEmpty <- isEmpty queue2
          return $ q1IsEmpty || q2IsEmpty

        emptyQueues = do
          anyQueueEmpty <- isAnyQueueEmpty
          unless anyQueueEmpty $ do
            onNext_
            emptyQueues

        onNext_ = do
          anyQueueEmpty <- isAnyQueueEmpty
          unless anyQueueEmpty $ do
            val1 <- next queue1
            val2 <- next queue2
            onNext observer $ zipFn val1 val2

        onNextA a = whileNotCompleted $ do
          yield
          conj queue1 a
          onNext_

        onNextB b = whileNotCompleted $ do
          conj queue2 b
          onNext_

        onError_ err = whileNotCompleted $ do
          onError observer err

        onCompleted_ = whileNotCompleted $ do
          isCompleted <- atomically $ do
            modifyTVar completedCountVar succ
            completedCount <- readTVar completedCountVar
            if (completedCount == 2)
              then do
                writeTVar isCompletedVar True
                return True
              else
                return False

          when isCompleted $ do
            emptyQueues
            onCompleted observer

zip :: (IObservable sourceA, IObservable sourceB)
       => sourceA Async a
       -> sourceB Async b
       -> Observable Async (a,b)
zip = zipWith (\a b -> (a, b))
