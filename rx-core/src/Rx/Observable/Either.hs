module Rx.Observable.Either where

import Control.Concurrent (yield)
import Control.Concurrent.MVar (newEmptyMVar, takeMVar, tryPutMVar)
import Control.Exception (SomeException)
import Control.Monad (void)

import Rx.Scheduler (Async)

import Rx.Observable.First (first)
import Rx.Observable.Types

toEither :: Observable Async a -> IO (Either SomeException a)
toEither source = do
    completedVar <- newEmptyMVar
    _disposable <-
      subscribe (first source)
                (void . tryPutMVar completedVar . Right)
                (void . tryPutMVar completedVar . Left)
                (return ())
    yield
    result <- takeMVar completedVar
    return result
