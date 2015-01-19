{-# LANGUAGE BangPatterns       #-}
{-# LANGUAGE DeriveDataTypeable #-}
module Rx.Observable.Types where

import Data.Monoid (mappend, mempty)
import Data.Typeable (Typeable)

import Control.Exception (AsyncException (ThreadKilled), Exception (..),
                          Handler (..), SomeException, catch, catches, throw,
                          throwIO)
import Control.Monad (forever, void)


import Control.Concurrent.Async (Async)
import Control.Concurrent.STM (TChan, atomically, newTChanIO, readTChan,
                               writeTChan)

import Rx.Disposable (Disposable, emptyDisposable, toDisposable,
                      newSingleAssignmentDisposable, setDisposable)

import Rx.Scheduler (IScheduler, Sync, newThread, schedule)
import qualified Rx.Scheduler as Rx (Async)

--------------------------------------------------------------------------------

class IObserver observer where
  onNext :: observer v -> v -> IO ()
  onNext ob v = emitNotification ob (OnNext v)
  {-# INLINE onNext #-}

  onError :: observer v -> SomeException -> IO ()
  onError ob err = emitNotification ob (OnError err)
  {-# INLINE onError #-}

  onCompleted :: observer v -> IO ()
  onCompleted ob = emitNotification ob OnCompleted
  {-# INLINE onCompleted #-}

  emitNotification :: observer v -> Notification v -> IO ()

class ToObserver observer where
  toObserver :: observer a -> Observer a

class IObservable observable where
  onSubscribe :: observable s a -> Observer a -> IO Disposable

class ToAsyncObservable observable where
  toAsyncObservable :: observable a -> Observable Rx.Async a

class ToSyncObservable observable where
  toSyncObservable :: observable a -> Observable Sync a

--------------------------------------------------------------------------------

data Notification v
  = OnNext v
  | OnError SomeException
  | OnCompleted
  deriving (Show, Typeable)

data Subject v =
  Subject {
    _subjectOnSubscribe        :: Observer v -> IO Disposable
  , _subjectOnEmitNotification :: Notification v -> IO ()
  , _subjectStateMachine       :: Async ()
  }
  deriving (Typeable)

newtype Observer v
  = Observer (Notification v -> IO ())
  deriving (Typeable)


newtype Observable s a =
  Observable { _onSubscribe :: Observer a -> IO Disposable }

data TimeoutError
  = TimeoutError
  deriving (Show, Typeable)

instance Exception TimeoutError

--------------------------------------------------------------------------------

instance ToObserver Subject where
  toObserver subject = Observer (_subjectOnEmitNotification subject)
  {-# INLINE toObserver #-}

instance ToAsyncObservable Subject where
  toAsyncObservable = Observable . _subjectOnSubscribe
  {-# INLINE toAsyncObservable #-}

instance ToSyncObservable Subject where
  toSyncObservable subject = Observable $ \observer -> do
      chan <- newTChanIO
      _disposable <-
        subscribeObserver
                  (toAsyncObservable subject)
                  (Observer $ atomically . writeTChan chan)
      syncLoop observer chan
        `catch` onError observer
      return mempty
    where
      syncLoop observer chan =
        forever $ do
          notification <- atomically $ readTChan chan
          emitNotification observer notification

instance IObserver Subject where
  emitNotification = _subjectOnEmitNotification
  {-# INLINE emitNotification #-}

instance ToObserver Observer where
  toObserver = id
  {-# INLINE toObserver #-}

instance IObserver Observer where
  emitNotification (Observer f) = f
  {-# INLINE emitNotification #-}

instance IObservable Observable where
  onSubscribe = _onSubscribe
  {-# INLINE onSubscribe #-}

instance ToAsyncObservable TChan where
  toAsyncObservable chan = Observable $ \observer ->
    schedule newThread $ forever $ do
      ev <- atomically $ readTChan chan
      onNext observer ev
  {-# INLINE toAsyncObservable #-}

instance ToSyncObservable TChan where
  toSyncObservable chan = Observable $ \observer -> do
    void
      $ forever
      $ atomically (readTChan chan) >>= onNext observer
    emptyDisposable
  {-# INLINE toSyncObservable #-}

--------------------------------------------------------------------------------

unsafeSubscribe :: (IObservable observable)
          => observable s v
          -> (v -> IO ())
          -> (SomeException -> IO ())
          -> IO ()
          -> IO Disposable
unsafeSubscribe !source !nextHandler !errHandler !complHandler =
    onSubscribe source $ Observer observerFn
  where
    observerFn (OnNext v) = nextHandler v
    observerFn (OnError err) = errHandler err
    observerFn OnCompleted = complHandler
{-# INLINE unsafeSubscribe #-}


subscribe :: (IObservable observable)
          => observable s v
          -> (v -> IO ())
          -> (SomeException -> IO ())
          -> IO ()
          -> IO Disposable
subscribe !source !nextHandler0 !errHandler0 !complHandler0 =
    unsafeSubscribe source nextHandler errHandler0 complHandler0
  where
    errHandler err = do
      print err
      errHandler0 err
    nextHandler v =
      (v `seq` nextHandler0 v)
        `catches` [ Handler (\err@ThreadKilled -> throw err)
                  , Handler errHandler ]
{-# INLINE subscribe #-}


subscribeOnNext :: (IObservable observable)
                => observable s v
                -> (v -> IO ())
                -> IO Disposable
subscribeOnNext !source !nextHandler =
  subscribe source nextHandler throwIO (return ())
{-# INLINE subscribeOnNext #-}

subscribeObserver
  :: (IObservable observable, ToObserver observer)
  => observable s a -> observer a -> IO Disposable
subscribeObserver !source !observer0 =
  let observer = toObserver observer0
  in subscribe source
               (onNext observer)
               (onError observer)
               (onCompleted observer)
{-# INLINE subscribeObserver #-}

--------------------------------------------------------------------------------

createObservable :: IScheduler scheduler
                 => scheduler s
                 -> (Observer a -> IO Disposable)
                 -> Observable s a
createObservable !scheduler !action = Observable $ \observer -> do
  actionDisposable <- newSingleAssignmentDisposable
  threadDisposable <-
    schedule scheduler (action observer >>=
                        setDisposable actionDisposable)

  return $ threadDisposable `mappend`
           toDisposable actionDisposable
{-# INLINE createObservable #-}
