{-# LANGUAGE NoImplicitPrelude #-}
module Rx.Observable.Either where

import           Prelude.Compat

import           Control.Concurrent.MVar (newEmptyMVar, readMVar, takeMVar,
                                          tryPutMVar)
import           Control.Exception       (SomeException)
import           Control.Monad           (void)

import           Rx.Scheduler            (Async)

import           Rx.Observable.First     (first)
import           Rx.Observable.Types

toEither :: Observable Async a -> IO (Either SomeException a)
toEither source = do
    completedVar <- newEmptyMVar
    resultVar <- newEmptyMVar
    _disposable <-
      subscribe (first source)
                (void . tryPutMVar resultVar . Right)
                (\err -> do
                   void (tryPutMVar resultVar (Left err))
                   void (tryPutMVar completedVar ()))
                (void (tryPutMVar completedVar ()))

    takeMVar completedVar
    readMVar resultVar
