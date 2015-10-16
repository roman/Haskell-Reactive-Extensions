{-# LANGUAGE NoImplicitPrelude #-}
module Rx.Observable.Fold where

import Prelude.Compat

import Data.IORef (atomicModifyIORef', newIORef, readIORef)

import Rx.Observable.Types

foldLeft
  :: (acc -> a -> acc)
     -> acc
     -> Observable s a
     -> Observable s acc
foldLeft foldFn acc0 source =
  Observable $ \observer -> do
      accVar <- newIORef acc0
      main accVar observer
    where
      main accVar observer =
          subscribe source onNext_ onError_ onCompleted_
        where
          onNext_ v = do
            atomicModifyIORef' accVar $ \acc ->
              (foldFn acc v, ())
          onError_ = onError observer
          onCompleted_ = do
            acc <- readIORef accVar
            onNext observer acc
            onCompleted observer

foldMap
  :: (Monoid b)
     => (a -> b)
     -> Observable s a
     -> Observable s b
foldMap toMonoid = foldLeft foldFn mempty
  where
    foldFn acc a = acc `mappend` toMonoid a
