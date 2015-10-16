{-# LANGUAGE BangPatterns #-}
module Rx.Observable.Distinct where

import Data.IORef (newIORef, atomicModifyIORef')
import Control.Monad (when)
import Rx.Observable.Types
import qualified Data.Set as Set


-- | Returns an `Observable` that emits all items emitted by the
-- source `Observable` that are distinct.
--
distinct
  :: (Eq a, Ord a)
     => Observable s a
     -> Observable s a
distinct !source =
    Observable $ \observer -> do
      cacheVar <- newIORef Set.empty
      subscribe source
        (onNext_ cacheVar observer)
        (onError observer)
        (onCompleted observer)
  where
    onNext_ cacheVar observer val = do
      shouldEmit <- atomicModifyIORef' cacheVar $ \cache ->
        if Set.member val cache
          then (cache, False)
          else (Set.insert val cache, True)
      when shouldEmit $ onNext observer val
{-# INLINE distinct #-}

-- | Returns an `Observable` that emits all items emitted by the
-- source `Observable` that are distinct from their immediate
-- predecessors, according to a key selector function.
--
distinctUntilChangedWith
  :: (Eq b)
     => (a -> b)
     -> Observable s a
     -> Observable s a
distinctUntilChangedWith !mapFn !source =
    Observable $ \observer -> do
      priorValVar <- newIORef Nothing
      subscribe source
                   (onNext_ priorValVar observer)
                   (onError observer)
                   (onCompleted observer)
  where
    onNext_ priorValVar observer val = do
      mPriorVal <-
        atomicModifyIORef' priorValVar $ \mPriorVal ->
          case mPriorVal of
            Nothing -> (Just val, Just val)
            Just priorVal
              | mapFn priorVal == mapFn val -> (Just val, Nothing)
              | otherwise -> (mPriorVal, Just val)
      maybe (return ()) (onNext observer) mPriorVal
{-# INLINE distinctUntilChangedWith #-}

-- | Returns an `Observable` that emits all items emitted by the source
-- `Observable` that are distinct from their immediate predecessors.
--
distinctUntilChanged
  :: (Eq a)
     => Observable s a
     -> Observable s a
distinctUntilChanged = distinctUntilChangedWith id
{-# INLINE distinctUntilChanged #-}
