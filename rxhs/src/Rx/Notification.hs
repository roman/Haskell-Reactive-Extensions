{-# LANGUAGE FlexibleContexts #-}
module Rx.Notification where

import Rx.Observable.Types

getValue :: Notification v -> Maybe v
getValue (OnNext v) = Just v
getValue _ = Nothing

hasThrowable :: Notification v -> Bool
hasThrowable (OnError _) = True
hasThrowable _ = False

accept :: Notification v -> Observer v -> IO ()
accept notification (Observer observerFn) =
  observerFn notification
