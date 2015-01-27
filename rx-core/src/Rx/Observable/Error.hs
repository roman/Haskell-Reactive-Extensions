{-# LANGUAGE BangPatterns #-}
module Rx.Observable.Error where

import Control.Exception (Exception, fromException)

import Rx.Disposable (newBooleanDisposable, setDisposable, toDisposable)

import Rx.Observable.Types

catch :: (IObservable source, Exception e)
         => (e -> IO ()) -> source s a -> Observable s a
catch !errHandler !source =
    newObservable $ \observer -> do
      subscribe source
                    (onNext observer)
                    (onError_ observer)
                    (onCompleted observer)
  where
    onError_ observer err =
      case fromException err of
        Just castedErr -> errHandler castedErr
        Nothing -> onError observer err
{-# INLINE catch #-}

handle :: (IObservable source, Exception e)
         => source s a -> (e -> IO ()) -> Observable s a
handle = flip catch
{-# INLINE handle #-}

onErrorReturn :: (IObservable source)
              => a -> source s a -> Observable s a
onErrorReturn !val !source =
  newObservable $ \observer -> do
    subscribe source
      (onNext observer)
      (\_ -> do
          onNext observer val
          onCompleted observer)
      (onCompleted observer)
{-# INLINE onErrorReturn #-}

onErrorResumeNext :: (IObservable errSource, IObservable source)
              => errSource s a -> source s a -> Observable s a
onErrorResumeNext !errSource !source =
  newObservable $ \observer -> do
    sourceDisposable <- newBooleanDisposable
    rootDisposable <-
      subscribe source
          (onNext observer)
          (\_ -> do
              errDisposable <-
                subscribe errSource
                          (onNext observer)
                          (onError observer)
                          (onCompleted observer)
              setDisposable sourceDisposable errDisposable)
          (onCompleted observer)

    setDisposable sourceDisposable rootDisposable
    return $ toDisposable sourceDisposable
{-# INLINE onErrorResumeNext #-}

retry :: (IObservable source)
      => Int -> source s a -> Observable s a
retry !attempts !source =
    newObservable $ \observer -> do
      sourceDisposable <- newBooleanDisposable
      retry_ sourceDisposable observer attempts
      return $ toDisposable sourceDisposable
  where
    retry_ sourceDisposable observer attempt = do
      disposable <-
        subscribe source
                  (onNext observer)
                  (\err -> do
                     if attempt > 0
                       then retry_ sourceDisposable observer (pred attempt)
                       else onError observer err)
                  (onCompleted observer)
      setDisposable sourceDisposable disposable
{-# INLINE retry #-}
