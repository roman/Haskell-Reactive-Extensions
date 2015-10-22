{-# LANGUAGE NoImplicitPrelude #-}
module Rx.Observable.Maybe where

import           Prelude.Compat

import           Control.Concurrent.MVar (newEmptyMVar, takeMVar, tryPutMVar)
import           Control.Monad           (void)

import           Rx.Disposable           (dispose)

import           Rx.Scheduler            (Async)

import           Rx.Observable.First     (first)
import           Rx.Observable.Types

toMaybe :: Observable Async a -> IO (Maybe a)
toMaybe source = do
    completedVar <- newEmptyMVar
    subDisposable <-
      subscribe
             (first source)
             (void . tryPutMVar completedVar . Just)
             (\_ -> void $ tryPutMVar completedVar Nothing)
             (void $ tryPutMVar completedVar Nothing)

    result <- takeMVar completedVar
    dispose subDisposable
    return result
