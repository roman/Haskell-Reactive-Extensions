module Rx.Observable.Types where

import Control.Applicative (Applicative (..))
import Control.Exception   (AsyncException (ThreadKilled), Handler (..),
                            SomeException, catches, throw)

import           Rx.Disposable (Disposable, emptyDisposable,
                                newCompositeDisposable,
                                newSingleAssignmentDisposable)
import qualified Rx.Disposable as Disposable
import           Rx.Scheduler  (Async, Scheduler, Sync, currentThread, schedule)

--------------------------------------------------------------------------------

class IObserver observer where
  onNext :: observer a -> a -> IO ()
  onError :: observer a -> SomeException -> IO ()
  onCompleted :: observer a -> IO ()

class IObservable observable where
  onSubscribe :: observable s a -> Observer a -> IO Disposable

--------------------------------------------------------------------------------

data Observer a =
  Observer {
    _onNext      :: a -> IO ()
  , _onError     :: SomeException -> IO ()
  , _onCompleted :: IO ()
  }

instance IObserver Observer where
  onNext = _onNext
  onError = _onError
  onCompleted = _onCompleted

--------------------------------------------------------------------------------

newtype Observable s a =
  Observable { _onSubscribe :: Observer a -> IO Disposable }

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
      nextHandler0 v `catches` [ Handler (\err@ThreadKilled -> throw err)
                               , Handler errHandler0]

createObservable :: Scheduler s
                 -> (Observer a -> IO Disposable)
                 -> Observable s a
createObservable scheduler action = Observable $ \observer -> do
  obsDisposable    <- newCompositeDisposable
  actionDisposable <- newSingleAssignmentDisposable
  threadDisposable <-
    schedule scheduler $ action observer >>=
      flip Disposable.set actionDisposable

  Disposable.append threadDisposable obsDisposable
  Disposable.append actionDisposable obsDisposable

  return $ Disposable.toDisposable obsDisposable

syncObservable :: Scheduler Sync
               -> (Observer a -> IO Disposable)
               -> Observable Sync a
syncObservable action = createObservable currentThread
