module Rx.Binary where

import Control.Concurrent.Async (async, cancel)
import Control.Exception (SomeException, mask, catch, finally, throwIO)
import qualified Data.ByteString as BS
import qualified Data.Streaming.FileRead as FR
import Rx.Disposable (Disposable, createDisposable)
import Rx.Observable (Observable(..), Async, onCompleted, onNext, onError)

bracketWithException
  :: IO h -> (h -> IO b) -> (SomeException -> IO ()) -> (h -> IO b) -> IO b
bracketWithException accquire release onErrorCb perform =
    mask $ \restore -> do
      h <- accquire `catch` onErrorAndRaise
      r <- restore (perform h)
           `catch` \err -> do
             release h `catch` onErrorAndRaise
             onErrorCb err
             throwIO err
      release h `catch` onErrorAndRaise
      return r
  where
    onErrorAndRaise err = onErrorCb err >> throwIO err


fileObservable :: FilePath -> Observable Async BS.ByteString
fileObservable path = Observable $ \observer -> do
    fileAsync <-
      async $
        bracketWithException (FR.openFile path)
                             FR.closeFile
                             (onError observer)
                             (loop observer)
    createDisposable $ cancel fileAsync
  where
    loop observer h = do
      bs <- FR.readChunk h
      if (BS.null bs)
        then onCompleted observer
        else onNext observer bs
