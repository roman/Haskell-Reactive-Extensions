module Rx.Observable.Merge where

import Control.Monad (forM, when)
import Control.Concurrent.STM (atomically)
import Control.Concurrent.STM.TVar as TVar

import Data.Unique (newUnique, hashUnique)
import qualified Data.Set as Set

import Rx.Scheduler (Async)
import Rx.Disposable ( newCompositeDisposable
                     , newSingleAssignmentDisposable
                     , dispose
                     , toDisposable )
import qualified Rx.Disposable as Disposable
import Rx.Observable.Types

merge :: (IObservable source, IObservable observable)
      => source Async (observable Async a)
      -> Observable Async a
merge obsSource = Observable $ \outerObserver -> do
    sourceCompletedVar <- TVar.newTVarIO False
    dispSetVar         <- TVar.newTVarIO $ Set.empty
    sourceDisp         <- newSingleAssignmentDisposable
    allDisposables     <- newCompositeDisposable
    main outerObserver
         dispSetVar
         allDisposables
         sourceCompletedVar
         sourceDisp
  where
    main outerObserver
         dispSetVar
         allDisposables
         sourceCompletedVar
         sourceDisp = do

        obsSourceDisp_ <-
          safeSubscribe obsSource onNextSource onErrorSource onCompletedSource

        Disposable.set obsSourceDisp_ sourceDisp
        Disposable.append (toDisposable sourceDisp) allDisposables
        return $ toDisposable allDisposables
      where
        onNextSource source = do
          subId <- hashUnique `fmap` newUnique
          disp <- safeSubscribe source onNext_ onError_ (onCompleted_ subId)

          Disposable.append disp allDisposables
          atomically $ TVar.modifyTVar dispSetVar $ Set.insert subId

        onErrorSource err = do
          dispose allDisposables
          onError outerObserver err

        onCompletedSource =
          atomically $ TVar.writeTVar sourceCompletedVar True

        onNext_ = onNext outerObserver

        onError_ err = do
          dispose allDisposables
          onError outerObserver err

        onCompleted_ subId = do
          shouldComplete <- atomically $ checkShouldComplete subId
          when shouldComplete $ onCompleted outerObserver

        checkShouldComplete subId = do
          dispSet         <- TVar.readTVar dispSetVar
          sourceCompleted <- TVar.readTVar sourceCompletedVar
          let dispSet' = Set.delete subId dispSet
          if Set.null dispSet' && sourceCompleted
             then return $ True
             else do
               TVar.writeTVar dispSetVar dispSet'
               return False
