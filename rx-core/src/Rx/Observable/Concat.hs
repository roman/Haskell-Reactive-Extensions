{-# LANGUAGE NoImplicitPrelude #-}
module Rx.Observable.Concat where

import           Prelude.Compat                hiding (concat)

import           Control.Concurrent.STM        (atomically)
import           Control.Concurrent.STM.TQueue (isEmptyTQueue, newTQueueIO,
                                                readTQueue, writeTQueue)
import           Control.Concurrent.STM.TVar   (newTVarIO, readTVar, writeTVar)
import           Control.Monad                 (when)
import           Data.Monoid                   ((<>))


import           Rx.Disposable                 (dispose, newBooleanDisposable,
                                                setDisposable, toDisposable)
import           Rx.Observable.List            (fromList)
import           Rx.Observable.Types
import           Rx.Scheduler                  (currentThread)

concat :: Observable s1 (Observable s2 a) -> Observable s2 a
concat sources = newObservable $ \outerObserver -> do
    outerCompletedVar <- newTVarIO False
    hasCurrentVar     <- newTVarIO False
    currentVar        <- newTVarIO Nothing
    currentDisposable <- newBooleanDisposable
    pendingVar        <- newTQueueIO
    main outerObserver
         outerCompletedVar
         hasCurrentVar
         currentVar
         currentDisposable
         pendingVar
  where
    main outerObserver
         outerCompletedVar
         hasCurrentVar
         currentVar
         currentDisposable
         pendingVar = do

        outerDisposable <-
              subscribe sources outerOnNext outerOnError outerOnCompleted

        return (outerDisposable <> toDisposable currentDisposable)
      where
        fetchHasCurrent = readTVar hasCurrentVar
        fetchHasPending = not <$> isEmptyTQueue pendingVar
        fetchOuterCompleted = readTVar outerCompletedVar

        accquireCurrent = atomically $ do
          hasCurrent <- readTVar hasCurrentVar
          if hasCurrent
            then return False
            else do
              writeTVar hasCurrentVar True
              return True

        resetCurrentSTM = do
          current <- readTVar currentVar
          writeTVar currentVar Nothing
          writeTVar hasCurrentVar False
          return current

        resetCurrent = atomically resetCurrentSTM

        disposeCurrent = do
          mDisposable <- resetCurrent
          case mDisposable of
            Just disposable -> dispose disposable
            Nothing -> return ()

        outerOnNext source = do
          currentAcquired <- accquireCurrent
          if currentAcquired
            then do
              innerDisposable <-
                    subscribe source innerOnNext innerOnError innerOnCompleted
              setDisposable currentDisposable innerDisposable
              atomically (writeTVar currentVar (Just innerDisposable))
            else atomically (writeTQueue pendingVar source)

        outerOnError err = do
          disposeCurrent
          onError outerObserver err

        outerOnCompleted = do
          -- need to wait for all inner observables to complete
          shouldComplete <- atomically $ do
              writeTVar outerCompletedVar True
              not <$> (((||)) <$> fetchHasCurrent <*> fetchHasPending)
          when shouldComplete (onCompleted outerObserver)

        innerOnNext = onNext outerObserver

        innerOnError err = do
          disposeCurrent
          onError outerObserver err

        innerOnCompleted = do
          mNextSource <- atomically $ do
            outerCompleted <- fetchOuterCompleted
            hasPending     <- fetchHasPending
            if outerCompleted && not hasPending
              then return Nothing
              else do
                _ <- resetCurrentSTM
                Just <$> readTQueue pendingVar
          case mNextSource of
            Nothing -> onCompleted outerObserver
            Just source -> outerOnNext source

concatList :: [Observable s a] -> Observable s a
concatList os = concat (fromList currentThread os)
