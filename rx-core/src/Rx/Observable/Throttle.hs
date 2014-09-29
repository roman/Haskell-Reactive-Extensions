module Rx.Observable.Throttle where

import Control.Concurrent.STM (atomically, newTVarIO, readTVar, writeTVar)
import Control.Monad (when)
import Data.Time (diffUTCTime, getCurrentTime)

import Tiempo (TimeInterval, toNominalDiffTime)

import Rx.Observable.Filter (filterM)
import Rx.Observable.Types

--------------------------------------------------------------------------------

throttle :: IObservable observable
         => TimeInterval
         -> observable s a
         -> Observable s a
throttle delay source =
    Observable $ \observer -> do
      mlastOnNextVar <- newTVarIO Nothing
      let source' = filterM (throttleFilter mlastOnNextVar)
                            source
      subscribeObserver source' observer
  where
    throttleFilter mlastOnNextVar _ = do
      mlastOnNext <- atomically $ readTVar mlastOnNextVar
      case mlastOnNext of
        Nothing -> do
          now <- getCurrentTime
          atomically $ writeTVar mlastOnNextVar (Just now)
          return True
        Just backThen -> do
          now <- getCurrentTime
          let diff = diffUTCTime now backThen
              passedDelay = diff > toNominalDiffTime delay
          when passedDelay
             $ atomically
             $ writeTVar mlastOnNextVar (Just now)
          return passedDelay
