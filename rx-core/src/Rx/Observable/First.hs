module Rx.Observable.First where

import Prelude hiding (take)

import Control.Monad (void)
import Control.Exception (SomeException(..), ErrorCall(..))
import qualified Control.Concurrent.MVar as MVar

import Rx.Scheduler (Async)
import Rx.Observable.Take (take)
import Rx.Disposable (dispose, newSingleAssignmentDisposable, toDisposable)
import qualified Rx.Disposable as Disposable

import Rx.Observable.Types

first :: Observable Async a -> Observable Async a
first = once . take 1

once :: Observable Async a -> Observable Async a
once source =
  Observable $ \observer -> do
    completedOrErredVar <- MVar.newMVar Nothing
    onceVar <- MVar.newMVar Nothing
    sad <- newSingleAssignmentDisposable
    sub <-
      subscribe
          source
          (\v -> do
            monce  <- MVar.readMVar onceVar
            case monce of
              Nothing -> do
                void $ MVar.swapMVar onceVar (Just v)
                onNext observer v
              Just _ -> do
                let err = SomeException
                            $ ErrorCall "once: expected to receive one element"
                void $ MVar.swapMVar completedOrErredVar (Just err)
                onError observer err
                dispose sad)
          (\err -> do
            onError observer err
            dispose sad)
          (onCompleted observer)

    Disposable.set sub sad
    return $ toDisposable sad
