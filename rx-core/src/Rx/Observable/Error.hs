{-# LANGUAGE BangPatterns #-}
module Rx.Observable.Error where

import Control.Exception (Exception, fromException)

import Rx.Disposable (newBooleanDisposable, setDisposable, toDisposable)

import Rx.Observable.Types

catch :: (Exception e)
         => (e -> Observable s a) -> Observable s a -> Observable s a
catch !errHandler !source =
    newObservable $ \observer -> do
      disposable <- newBooleanDisposable
      main disposable observer
      return $ toDisposable disposable
  where
    main disposable observer = do
        disposable_ <-
            subscribe source (onNext observer)
                             onError_
                             (onCompleted observer)
        setDisposable disposable disposable_
      where
        onError_ err =
          case fromException err of
            Just castedErr -> do
              let newSource = errHandler castedErr
              disposable_ <-
                subscribe newSource
                          (onNext observer)
                          (onError observer)
                          (onCompleted observer)
              setDisposable disposable disposable_
            Nothing -> onError observer err
{-# INLINE catch #-}

handle
  :: (Exception e)
     => Observable s a
     -> (e -> Observable s a)
     -> Observable s a
handle = flip catch
{-# INLINE handle #-}

onErrorReturn :: a -> Observable s a -> Observable s a
onErrorReturn !val !source =
  newObservable $ \observer -> do
    subscribe source
      (onNext observer)
      (\_ -> do
          onNext observer val
          onCompleted observer)
      (onCompleted observer)
{-# INLINE onErrorReturn #-}

onErrorResumeNext
  :: Observable s a
     -> Observable s a
     -> Observable s a
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

retry :: Int -> Observable s a -> Observable s a
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
