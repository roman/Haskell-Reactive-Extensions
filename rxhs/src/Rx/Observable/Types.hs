{-# LANGUAGE RankNTypes #-}
module Rx.Observable.Types where

import Control.Applicative (Applicative(..))
import Control.Exception (SomeException, catch)
import Rx.Disposable (Disposable, emptyDisposable)

--------------------------------------------------------------------------------

class IObserver observer where
  onNext :: observer a -> a -> IO ()
  onError :: observer a -> SomeException -> IO ()
  onCompleted :: observer a -> IO ()

class IObservable observable where
  onSubscribe :: IObserver observer => observable s a -> observer a -> IO Disposable

--------------------------------------------------------------------------------

data Observer a =
  Observer {
    _onNext :: a -> IO ()
  , _onError :: SomeException -> IO ()
  , _onCompleted :: IO ()
  }

instance IObserver Observer where
  onNext = _onNext
  onError = _onError
  onCompleted = _onCompleted

--------------------------------------------------------------------------------

newtype Observable s a =
  Observable { _onSubscribe ::
                  forall observer . IObserver observer => observer a -> IO Disposable }

instance IObservable Observable where
  onSubscribe = _onSubscribe

--------------------------------------------------------------------------------

subscribe :: (IObservable observable)
          => observable s v
          -> (v -> IO ())
          -> (SomeException -> IO ())
          -> IO ()
          -> IO Disposable
subscribe source nextHandler errHandler complHandler =
  onSubscribe source $ Observer nextHandler errHandler complHandler

safeSubscribe :: (IObservable observable)
          => observable s v
          -> (v -> IO ())
          -> (SomeException -> IO ())
          -> IO ()
          -> IO Disposable
safeSubscribe source nextHandler0 errHandler0 complHandler0 =
    subscribe source nextHandler errHandler0 complHandler0
  where
    nextHandler v =
      nextHandler0 v `catch` errHandler0
