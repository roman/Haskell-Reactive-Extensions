module Rx.Observable.Maybe where

import Control.Monad (void)
import qualified Control.Concurrent.MVar as MVar

import Rx.Scheduler (Async)
import Rx.Disposable (dispose)
import Rx.Observable.First (first)
import Rx.Observable.Types

toMaybe :: Observable Async a -> IO (Maybe a)
toMaybe source = do
    completedVar <- MVar.newEmptyMVar
    sub <- subscribe
             (first source)
             (MVar.putMVar completedVar . Just)
             (const $ MVar.putMVar completedVar Nothing)
             (void $ MVar.tryPutMVar completedVar Nothing)
    result <- MVar.takeMVar completedVar
    dispose sub
    return result
