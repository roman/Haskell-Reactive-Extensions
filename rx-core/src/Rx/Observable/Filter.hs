module Rx.Observable.Filter where

import Prelude hiding (filter)

import Rx.Observable.Map (concatMapM)
import Rx.Observable.Types

filterM :: IObservable observable
        => (a -> IO Bool)
        -> observable s a
        -> Observable s a
filterM filterFn =
  concatMapM $ \a -> do
    result <- filterFn a
    return $ if result then [a] else []

filter :: IObservable observable
       => (a -> Bool)
       -> observable s a
       -> Observable s a
filter filterFn =
  filterM (return . filterFn)
