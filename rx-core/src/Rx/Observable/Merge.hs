module Rx.Observable.Merge where

import Prelude hiding (mapM)

import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Concurrent.STM (atomically)
import Control.Concurrent.STM.TVar (modifyTVar, newTVarIO, readTVar, writeTVar)
import Control.Monad (void, when)

import Data.Traversable (mapM)
import Data.Unique (hashUnique, newUnique)
import qualified Data.HashMap.Strict as HashMap

import Rx.Disposable (createDisposable, dispose, newSingleAssignmentDisposable)
import qualified Rx.Disposable as Disposable

import Rx.Scheduler (Async, newThread)

import Rx.Observable.Types
import qualified Rx.Observable.List as Observable

merge :: (IObservable source, IObservable observable)
      => source Async (observable Async a)
      -> Observable Async a
merge sources = Observable $ \outerObserver -> do
    mainDisposable     <- newSingleAssignmentDisposable
    sourceCompletedVar <- newTVarIO False
    disposableMapVar   <- newTVarIO $ HashMap.empty
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

        sourceDisposable <- createDisposable $ do
          dispose sourceSubDisposable
          disposableMap <- atomically $ readTVar disposableMapVar
          void $ mapM dispose disposableMap

        Disposable.set sourceDisposable mainDisposable
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
          _ <- takeMVar sourceIdVar
          onError outerObserver err
          dispose mainDisposable

        onCompleted_ sourceIdVar = do
          sourceId <- takeMVar sourceIdVar
          shouldComplete <- atomically $ checkShouldComplete sourceId
          when shouldComplete $ onCompleted outerObserver

        checkShouldComplete sourceId = do
          sourceCompleted <- readTVar sourceCompletedVar

          disposableMap <- readTVar disposableMapVar
          let disposableMap1 = HashMap.delete sourceId disposableMap

          if sourceCompleted && HashMap.null disposableMap1
             then return True
             else do
               writeTVar disposableMapVar disposableMap1
               return False

mergeList
  :: (IObservable observable)
  => [observable Async a]
  -> Observable Async a
mergeList =
  merge . Observable.fromList newThread
