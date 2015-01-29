module Rx.Observable.First where

import Prelude hiding (take)

import Control.Exception (ErrorCall (..), toException)
import Data.IORef (atomicModifyIORef', newIORef)

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
    onceVar <- newIORef False
    disposable <- newSingleAssignmentDisposable
    main onceVar disposable observer
    return $ toDisposable disposable
  where
    main onceVar disposable observer = do
        disposable_ <- subscribe source
                                 onNext_
                                 onError_
                                 (onCompleted observer)
        setDisposable disposable disposable_
      where
        onNext_ v = do
          alreadyEmitted <- atomicModifyIORef' onceVar $ \onceVal ->
            if onceVal
              then (True, True)
              else (True, False)

          if alreadyEmitted
            then do
              let err = toException
                           $ ErrorCall "once: expected to receive one element"
              onError observer err
              dispose disposable
            else onNext observer v

        onError_ err = do
          onError observer err
          dispose disposable
