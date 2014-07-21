module Rx.Observable.Distinct where

import qualified Control.Concurrent.MVar as MVar
import qualified Data.Set as Set
import Rx.Observable.Types


-- | Returns an `Observable` that emits all items emitted by the source
-- `Observable` that are distinct.
--
--
distinct :: (Eq a, Ord a)
         => Observable s a
         -> Observable s a
distinct source =
  Observable $ \observer -> do
    cacheVar <- MVar.newMVar Set.empty
    subscribe source
      (\v ->
        MVar.modifyMVar_ cacheVar $ \cache ->
          if Set.member v cache
            then return cache
            else do
              onNext observer v
              return $ Set.insert v cache)
      (onError observer)
      (onCompleted observer)

-- | Returns an `Observable` that emits all items emitted by the source
-- `Observable` that are distinct from their immediate predecessors,
-- according to a key selector function.
--
--
distinctUntilChangedWith :: (Eq b)
                         => (a -> b)
                         -> Observable s a
                         -> Observable s a
distinctUntilChangedWith transfn source =
    Observable $ \observer -> do
      priorValVar <- MVar.newEmptyMVar
      subscribe source
                   (\val -> do
                     mpriorVal <- MVar.tryTakeMVar priorValVar
                     case mpriorVal of
                       Nothing -> do
                         MVar.putMVar priorValVar val
                         onNext observer val
                       Just priorVal
                         | transfn priorVal == transfn val -> do
                           MVar.putMVar priorValVar priorVal
                           return ()
                         | otherwise -> do
                           MVar.putMVar priorValVar val
                           onNext observer val)
                   (onError observer)
                   (onCompleted observer)


-- | Returns an `Observable` that emits all items emitted by the source
-- `Observable` that are distinct from their immediate predecessors.
--
--
distinctUntilChanged :: (Eq a)
                     => Observable s a -> Observable s a
distinctUntilChanged = distinctUntilChangedWith id
