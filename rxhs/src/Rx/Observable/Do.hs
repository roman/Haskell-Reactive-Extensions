module Rx.Observable.Do where

import Rx.Observable.Types

doAction :: IObservable source
         => (a -> IO ())
         -> source s a
         -> Observable s a
doAction action source =
  Observable $ \observer -> do
    safeSubscribe
      source (\v -> action v >> onNext observer v)
             (onError observer)
             (onCompleted observer)
