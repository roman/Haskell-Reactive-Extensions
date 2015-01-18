module Rx.Observable.First where

import Prelude hiding (take)

import Control.Concurrent.MVar (newMVar, readMVar, swapMVar)
import Control.Exception (ErrorCall (..), toException)
import Control.Monad (void)

import Rx.Disposable (dispose, newSingleAssignmentDisposable, setDisposable,
                      toDisposable)

import Rx.Scheduler (Async)

import Rx.Observable.Take (take)
import Rx.Observable.Types

first :: Observable Async a -> Observable Async a
first = once . take 1

once :: Observable Async a -> Observable Async a
once source =
  Observable $ \observer -> do
    onceVar <- newMVar Nothing
    sourceDisposable <- newSingleAssignmentDisposable
    innerDisposable <-
      subscribe
          source
          (\v -> do
            mOnce <- readMVar onceVar
            case mOnce of
              Nothing -> do
                void $ swapMVar onceVar (Just v)
                onNext observer v
              Just _ -> do
                let err = toException
                             $ ErrorCall "once: expected to receive one element"
                onError observer err
                void $ dispose sourceDisposable)
          (\err -> do
            onError observer err
            void $ dispose sourceDisposable)
          (onCompleted observer)

    setDisposable sourceDisposable innerDisposable
    return $ toDisposable sourceDisposable
