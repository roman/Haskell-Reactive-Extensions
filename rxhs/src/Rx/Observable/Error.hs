module Rx.Observable.Error where

import Control.Exception (Exception, fromException)
import Rx.Observable.Types

catch :: (IObservable source, Exception e)
         => (e -> IO ()) -> source s a -> Observable s a
catch errHandler source =
    Observable $ \observer -> do
      subscribe source
                    (onNext observer)
                    (onError_ observer)
                    (onCompleted observer)
  where
    onError_ observer err =
      case fromException err of
        Just castedErr -> errHandler castedErr
        Nothing -> onError observer err
