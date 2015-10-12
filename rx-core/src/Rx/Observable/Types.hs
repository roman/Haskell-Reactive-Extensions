{-# LANGUAGE BangPatterns       #-}
{-# LANGUAGE DeriveDataTypeable #-}
module Rx.Observable.Types where

import Data.IORef (atomicModifyIORef', newIORef, readIORef)
import Data.Typeable (Typeable)

import Control.Exception (AsyncException (ThreadKilled), Exception (..),
                          Handler (..), SomeException, catch, catches, throw,
                          throwIO, try)
import Control.Monad (forever, void, when, unless)


import Control.Concurrent.Async (Async)
import Control.Concurrent.STM (TChan, atomically, newTChanIO, readTChan,
                               writeTChan)

import Rx.Disposable (Disposable, dispose, emptyDisposable,
                      newSingleAssignmentDisposable, setDisposable,
                      toDisposable)

import Rx.Scheduler (IScheduler, Sync, currentThread, newThread, schedule)
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

data ConnectableObservable a
  = ConnectableObservable {
    _coOnSubscribe   :: Observer a -> IO Disposable
  , _coConnect       :: IO ()
  , _coDisposeSource :: IO ()
  }

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

instance ToAsyncObservable ConnectableObservable where
  toAsyncObservable = Observable . _coOnSubscribe
  {-# INLINE toAsyncObservable #-}

--------------------

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

--------------------

ioToObservable :: IScheduler scheduler
               => scheduler s
               -> IO a
               -> Observable s a
ioToObservable scheduler action =
  newObservableScheduler scheduler $ \observer -> do
      result <- try action
      case result of
        Right v -> do
          onNext observer v
          onCompleted observer
        Left err ->
          onError observer err
      emptyDisposable
{-# INLINE ioToObservable #-}

instance ToAsyncObservable IO where
  toAsyncObservable = ioToObservable newThread
  {-# INLINE toAsyncObservable #-}

instance ToSyncObservable IO where
  toSyncObservable = ioToObservable currentThread
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
subscribe !source !nextHandler0 !errHandler0 !complHandler0 = do
    completedVar <- newIORef False
    disposable   <- newSingleAssignmentDisposable
    main completedVar disposable
    return $ toDisposable disposable
  where
    main completedVar disposable = do
        disposable_ <-
          unsafeSubscribe source nextHandler errHandler complHandler
        setDisposable disposable disposable_
     where
        checkCompletion = atomicModifyIORef' completedVar $ \wasCompleted ->
          if wasCompleted
            then (wasCompleted, False)
            else (True, True)

        nextHandler v = do
          wasCompleted <- readIORef completedVar
          unless wasCompleted $
              v `seq` nextHandler0 v

        errHandler err = do
          shouldComplete <- checkCompletion
          when shouldComplete $ do
            errHandler0 err
            dispose disposable

        complHandler = do
          shouldComplete <- checkCompletion
          when shouldComplete $ do
            complHandler0
            dispose disposable
{-# INLINE subscribe #-}

safeSubscribe :: IObservable observable
  => observable s v
  -> (v -> IO ())
  -> (SomeException -> IO ())
  -> IO ()
  -> IO Disposable
safeSubscribe !source nextHandler errHandler complHandler =
    subscribe (secureSource source) nextHandler errHandler complHandler
  where
    secureSource :: IObservable source => source s v -> Observable s v
    secureSource source' = Observable $ \observer ->
        main observer
      where
        main observer =
            subscribe source' onNext_ (onError observer) (onCompleted observer)
          where
            onNext_ v =
              onNext observer v `catches` [ Handler (\err@ThreadKilled -> throw err)
                                          , Handler (onError observer) ]


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

newObserver :: (v -> IO ()) -> (SomeException -> IO ()) -> IO () -> Observer v
newObserver onNext_ onError_ onCompleted_ =
    Observer observerFn
  where
    observerFn (OnNext v) = onNext_ v
    observerFn (OnError err) = onError_ err
    observerFn OnCompleted = onCompleted_
{-# INLINE newObserver #-}

newObservable :: (Observer a -> IO Disposable) -> Observable s a
newObservable = Observable
{-# INLINE newObservable #-}

newObservableScheduler :: IScheduler scheduler
                 => scheduler s
                 -> (Observer a -> IO Disposable)
                 -> Observable s a
newObservableScheduler !scheduler !action = newObservable $ \observer -> do
  actionDisposable <- newSingleAssignmentDisposable
  threadDisposable <-
    schedule scheduler (action observer >>=
                        setDisposable actionDisposable)

  return $ threadDisposable `mappend`
           toDisposable actionDisposable
{-# INLINE newObservableScheduler #-}
