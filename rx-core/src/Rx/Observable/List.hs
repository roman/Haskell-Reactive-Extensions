module Rx.Observable.List where

import Control.Exception (SomeException)
import Control.Monad (void)

import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Data.IORef (atomicModifyIORef', newIORef, readIORef)

import Rx.Observable.Types
import Rx.Scheduler (IScheduler, schedule)

toList
  :: Observable s a
  -> IO (Either ([a], SomeException) [a])
toList source = do
  doneVar <- newEmptyMVar
  accVar <- newIORef []
  void
    $ subscribe
        source
        (\v -> atomicModifyIORef' accVar (\acc -> (v:acc, ())))
        (\err -> do
           acc <- readIORef accVar
           putMVar doneVar (Left (acc, err)))
        (do acc <- readIORef accVar
            putMVar doneVar (Right acc))
  takeMVar doneVar


fromList :: IScheduler scheduler => scheduler s -> [a] -> Observable s a
fromList scheduler as = Observable $ \observer ->
  schedule scheduler $ do
    mapM_ (onNext observer) as
    onCompleted observer
