module Rx.Observable.Merge where

import Prelude hiding (mapM)

import Control.Concurrent.STM (atomically)
import Control.Concurrent.STM.TVar (modifyTVar, newTVarIO, readTVar, writeTVar)
import Control.Monad (void, when)

import Data.Traversable (mapM)
import Data.Unique (hashUnique, newUnique)
import qualified Data.HashMap.Strict as HashMap
import qualified Data.Set            as Set

import Rx.Disposable (createDisposable, dispose, emptyDisposable,
                      newSingleAssignmentDisposable, toDisposable)
import qualified Rx.Disposable as Disposable

import Rx.Scheduler (Async, newThread)

import Rx.Observable.Types
import qualified Rx.Observable.List as Observable

merge :: (IObservable source, IObservable observable)
      => source Async (observable Async a)
      -> Observable Async a
merge obsSource = Observable $ \outerObserver -> do
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

        innerDisposable <-
          subscribe obsSource onNextSource onErrorSource onCompletedSource

        sourceDisposable <- createDisposable $ do
          dispose innerDisposable
          disposableMap <- atomically $ readTVar disposableMapVar
          void $ mapM dispose disposableMap

        Disposable.set sourceDisposable mainDisposable
        return sourceDisposable
      where
        onNextSource source = do
          sourceId <- hashUnique `fmap` newUnique
          sourceDisposable <-
            subscribe source onNext_ onError_ (onCompleted_ sourceId)

          atomically $ modifyTVar disposableMapVar
                     $ HashMap.insert sourceId sourceDisposable

        onErrorSource err = do
          dispose mainDisposable
          onError outerObserver err

        onCompletedSource = do
          shouldComplete <- atomically $ do
            writeTVar sourceCompletedVar True
            HashMap.null `fmap` readTVar disposableMapVar
          when shouldComplete $ onCompleted outerObserver

        onNext_ = onNext outerObserver

        onError_ err = do
          dispose mainDisposable
          onError outerObserver err

        onCompleted_ sourceId = do
          shouldComplete <- atomically $ checkShouldComplete sourceId
          when shouldComplete $ onCompleted outerObserver

        checkShouldComplete sourceId = do
          disposableMap   <- readTVar disposableMapVar
          sourceCompleted <- readTVar sourceCompletedVar
          let disposableMap' = HashMap.delete sourceId disposableMap
          if HashMap.null disposableMap' && sourceCompleted
             then return $ True
             else do
               writeTVar disposableMapVar disposableMap'
               return False

mergeList
  :: (IObservable observable)
  => [observable Async a]
  -> Observable Async a
mergeList sourceList =
  merge $ Observable.fromList newThread sourceList
