{-# LANGUAGE BangPatterns #-}
module Rx.Observable.Distinct where

import Control.Concurrent.MVar (modifyMVar_, newMVar)
import Rx.Observable.Types
import qualified Data.Set as Set


-- | Returns an `Observable` that emits all items emitted by the source
-- `Observable` that are distinct.
--
--
distinct :: (IObservable source, Eq a, Ord a)
         => source s a
         -> Observable s a
distinct !source =
  Observable $ \observer -> do
    cacheVar <- newMVar Set.empty
    subscribe source
      (\v ->
        modifyMVar_ cacheVar $ \cache ->
          if Set.member v cache
            then return cache
            else do
              onNext observer v
              return $ Set.insert v cache)
      (onError observer)
      (onCompleted observer)
{-# INLINE distinct #-}

-- | Returns an `Observable` that emits all items emitted by the source
-- `Observable` that are distinct from their immediate predecessors,
-- according to a key selector function.
--
--
distinctUntilChangedWith :: (IObservable source, Eq b)
                         => (a -> b)
                         -> source s a
                         -> Observable s a
distinctUntilChangedWith !mapFn !source =
    Observable $ \observer -> do
      priorValVar <- newMVar Nothing
      subscribe source
                   (\val -> do
                     modifyMVar_ priorValVar $ \mpriorVal -> do
                       case mpriorVal of
                         Nothing -> do
                           onNext observer val
                           return $! Just val
                         Just priorVal
                           | mapFn priorVal == mapFn val ->
                             return $! Just priorVal
                           | otherwise -> do
                             onNext observer val
                             return $! Just val)
                   (onError observer)
                   (onCompleted observer)
{-# INLINE distinctUntilChangedWith #-}

-- | Returns an `Observable` that emits all items emitted by the source
-- `Observable` that are distinct from their immediate predecessors.
--
--
distinctUntilChanged :: (IObservable source, Eq a)
                     => source s a -> Observable s a
distinctUntilChanged = distinctUntilChangedWith id
{-# INLINE distinctUntilChanged #-}
