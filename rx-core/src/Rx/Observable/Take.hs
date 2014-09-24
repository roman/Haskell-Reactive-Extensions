module Rx.Observable.Take where

import Prelude hiding (take, takeWhile)

import Control.Concurrent.STM      (atomically)
import Control.Concurrent.STM.TVar (modifyTVar, newTVarIO, readTVar)
import Control.Monad               (when)

import           Rx.Disposable (dispose, newSingleAssignmentDisposable)
import qualified Rx.Disposable as Disposable

import Rx.Scheduler (Async)

import Rx.Observable.Types

take :: IObservable observable
     => Int
     -> observable Async a
     -> Observable Async a
take n source = Observable $ \observer -> do
    sourceDisposable <- newSingleAssignmentDisposable
    countdownVar <- newTVarIO n
    subscription <- main sourceDisposable observer countdownVar

    Disposable.set subscription sourceDisposable
    return $ Disposable.toDisposable sourceDisposable
  where
    main sourceDisposable observer countdownVar =
        subscribe source onNext_ onError_ onCompleted_
      where
        onNext_ v = do
          shouldFinish <- atomically $ do
            countdown <- pred `fmap` readTVar countdownVar
            if countdown == 0
              then return True
              else modifyTVar countdownVar pred >> return False
          onNext observer v
          when shouldFinish $ do
            onCompleted observer
            dispose sourceDisposable
        onError_ = onError observer
        onCompleted_ = onCompleted observer

takeWhileIO :: IObservable observable
            => (a -> IO Bool)
            -> observable Async a
            -> Observable Async a
takeWhileIO pred source = Observable $ \observer -> do
    sourceDisposable <- newSingleAssignmentDisposable
    subscription     <- main sourceDisposable observer

    Disposable.set subscription sourceDisposable
    return $ Disposable.toDisposable sourceDisposable
  where
    main sourceDisposable observer =
        subscribe source onNext_ onError_ onCompleted_
      where
        onNext_ v = do
          shouldContinue <- pred v
          if shouldContinue
             then onNext observer v
             else do
               onCompleted observer
               dispose sourceDisposable
        onError_ = onError observer
        onCompleted_ = onCompleted observer

takeWhile :: IObservable observable
          => (a -> Bool)
          -> observable Async a
          -> Observable Async a
takeWhile pred = takeWhileIO (return . pred)
