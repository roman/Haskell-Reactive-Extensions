{-# LANGUAGE NoImplicitPrelude #-}
module Rx.Observable.Merge where

import           Prelude.Compat

import           Control.Concurrent.MVar     (newEmptyMVar, putMVar, readMVar)
import           Control.Concurrent.STM      (atomically)
import           Control.Concurrent.STM.TVar (modifyTVar, newTVarIO, readTVar,
                                              writeTVar)
import           Control.Monad               (void, when)

import qualified Data.HashMap.Strict         as HashMap
import           Data.Unique                 (hashUnique, newUnique)

import           Rx.Disposable               (dispose, newDisposable,
                                              newSingleAssignmentDisposable,
                                              setDisposable, wrapDisposableIO)

import           Rx.Scheduler                (Async, currentThread)

import qualified Rx.Observable.List          as Observable
import           Rx.Observable.Types

merge :: Observable s (Observable Async a)
      -> Observable Async a
merge sources = Observable $ \outerObserver -> do
    mainDisposable     <- newSingleAssignmentDisposable
    sourceCompletedVar <- newTVarIO False
    disposableMapVar   <- newTVarIO HashMap.empty
    main outerObserver
         mainDisposable
         disposableMapVar
         sourceCompletedVar
  where
    main outerObserver
         mainDisposable
         disposableMapVar
         sourceCompletedVar = do

        sourceSubDisposable <-
          subscribe sources sourceOnNext sourceOnError sourceOnCompleted

        sourceDisposable <- wrapDisposableIO "Observable.merge" $ do
          disposableMap <- atomically (readTVar disposableMapVar)
          return (mconcat (sourceSubDisposable : HashMap.elems disposableMap))

        setDisposable mainDisposable sourceDisposable
        return sourceDisposable
      where
        sourceOnNext source = do
          sourceId <- hashUnique `fmap` newUnique

          -- BEFORE: sourceIdVar ensures that onCompleted is not called before
          -- we add the disposable to diposableMapVar
          sourceIdVar <- newEmptyMVar
          sourceDisposable <-
            subscribe source onNext_
                             (onError_ sourceIdVar)
                             (onCompleted_ sourceIdVar)

          atomically $ modifyTVar disposableMapVar
                     $ HashMap.insert sourceId sourceDisposable

          -- AFTER: After state is set up, onCompleted can be called
          putMVar sourceIdVar sourceId

        sourceOnError err = do
          dispose mainDisposable
          onError outerObserver err

        sourceOnCompleted = do
          subscribedCount <- atomically $ do
            writeTVar sourceCompletedVar True
            HashMap.size `fmap` readTVar disposableMapVar

          when (subscribedCount == 0)
            $ onCompleted outerObserver

        onNext_ = onNext outerObserver

        onError_ sourceIdVar err = do
          _ <- readMVar sourceIdVar
          onError outerObserver err
          void $ dispose mainDisposable

        onCompleted_ sourceIdVar = do
          sourceId <- readMVar sourceIdVar
          shouldComplete <- atomically $ checkShouldComplete sourceId
          when shouldComplete $ onCompleted outerObserver

        checkShouldComplete sourceId = do
          sourceCompleted <- readTVar sourceCompletedVar
          disposableMap <- HashMap.delete sourceId `fmap` readTVar disposableMapVar
          if sourceCompleted && HashMap.null disposableMap
             then return True
             else do
               writeTVar disposableMapVar disposableMap
               return False

mergeList :: [Observable Async a] -> Observable Async a
mergeList =
  merge . Observable.fromList currentThread
