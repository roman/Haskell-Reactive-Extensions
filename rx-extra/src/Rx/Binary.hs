module Rx.Binary where


import Control.Concurrent.Async (async, cancel)
import Control.Exception (SomeException, catch, mask, throwIO)
import Control.Monad (unless, void)


import Data.IORef (atomicModifyIORef', newIORef, readIORef)
import qualified Data.ByteString         as BS
import qualified Data.Streaming.FileRead as FR

import Rx.Disposable (createDisposable)
import Rx.Observable (Async, Observable (..), onCompleted, onError, onNext)
import qualified Rx.Observable as Rx

bracketWithException
  :: IO h -> (h -> IO b) -> (SomeException -> IO ()) -> (h -> IO b) -> IO b
bracketWithException accquire release onErrorCb perform =
    mask $ \restore -> do
      h <- accquire `catch` onErrorAndRaise restore
      r <- restore (perform h)
           `catch` \err -> do
             void $ release h `catch` onErrorAndRaise restore
             onErrorAndRaise restore err
      void $ release h `catch` onErrorAndRaise restore
      return r
  where
    onErrorAndRaise restore err = restore (onErrorCb err) >> throwIO err


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

lines :: Observable s BS.ByteString -> Observable s BS.ByteString
lines source = Observable $ \observer -> do
    bufferVar <- newIORef id
    main bufferVar observer
  where
    main bufferVar observer =
        Rx.subscribe
          source onNext_ onError_ onCompleted_
      where
        newline = 10
        onNext_ inputBS = do
          let (current, rest0) = BS.breakByte newline inputBS
          -- split the newline from rest0
          case BS.uncons rest0 of
            Just (_, rest) -> do
              outputBS <-
                atomicModifyIORef' bufferVar
                  $ \appendPrev -> (BS.append rest, appendPrev current)
              onNext observer outputBS
            Nothing -> do
              atomicModifyIORef' bufferVar
                 $ \appendPrev -> (BS.append current . appendPrev, ())

        emitRemaining = do
          appendRemaining <- readIORef bufferVar
          let outputBS = appendRemaining BS.empty
          unless (BS.null outputBS) $ onNext observer outputBS

        onError_ err = do
          emitRemaining
          onError observer err

        onCompleted_ = do
          emitRemaining
          onCompleted observer



unlines :: Observable s BS.ByteString -> Observable s BS.ByteString
unlines _ = undefined
