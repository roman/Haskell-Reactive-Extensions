module Rx.Observable.Maybe where

import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar, tryPutMVar)
import Control.Monad (void)

import Rx.Disposable (dispose)

import Rx.Scheduler (Async)

import Rx.Observable.First (first)
import Rx.Observable.Types

toMaybe :: Observable Async a -> IO (Maybe a)
toMaybe source = do
    completedVar <- newEmptyMVar
    sub <- subscribe
             (first source)
             (putMVar completedVar . Just)
             (const $ putMVar completedVar Nothing)
             (void $ tryPutMVar completedVar Nothing)
    result <- takeMVar completedVar
    dispose sub
    return result
