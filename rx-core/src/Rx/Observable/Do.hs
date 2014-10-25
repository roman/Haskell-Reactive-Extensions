{-# LANGUAGE BangPatterns #-}
module Rx.Observable.Do where

import Control.Exception (SomeException)
import Rx.Observable.Types

doAction :: IObservable source
         => (a -> IO ())
         -> source s a
         -> Observable s a
doAction !action !source =
  Observable $ \observer -> do
    subscribe
      source (\v -> action v >> onNext observer v)
             (onError observer)
             (onCompleted observer)
{-# INLINE doAction #-}

doOnCompleted :: IObservable source
         => IO ()
         -> source s a
         -> Observable s a
doOnCompleted !action !source =
  Observable $ \observer -> do
    subscribe
      source (onNext observer)
             (onError observer)
             (action >> onCompleted observer)
{-# INLINE doOnCompleted #-}

doOnError :: IObservable source
         => (SomeException -> IO ())
         -> source s a
         -> Observable s a
doOnError !action !source =
  Observable $ \observer -> do
    subscribe
      source (onNext observer)
             (\err -> action err >> onError observer err)
             (onCompleted observer)
{-# INLINE doOnError #-}
