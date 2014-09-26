module Rx.Observable.List where

import Control.Exception (SomeException)
import Control.Monad (void)
import qualified Control.Concurrent.MVar as MVar

import Rx.Scheduler (Scheduler, schedule)
import Rx.Observable.Types

toList
  :: IObservable source
  => source s a
  -> IO (Either ([a], SomeException) [a])
toList source = do
  doneVar <- MVar.newEmptyMVar
  accVar <- MVar.newMVar []
  disposable <-
    subscribe
      source
      (\v -> MVar.modifyMVar_ accVar (return . (v:)))
      (\err -> do
         acc <- MVar.takeMVar accVar
         MVar.putMVar doneVar (Left (acc, err)))
      (do acc <- MVar.takeMVar accVar
          MVar.putMVar doneVar (Right acc))
  MVar.takeMVar doneVar


fromList :: Scheduler s -> [a] -> Observable s a
fromList scheduler as = Observable $ \observer ->
  schedule scheduler $ do
    mapM_ (onNext observer) as
    onCompleted observer
