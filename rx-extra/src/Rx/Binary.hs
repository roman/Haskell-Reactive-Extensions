module Rx.Binary where

import Prelude hiding (lines, unlines)

import Control.Exception (SomeException, catch, mask, throwIO, try)
import Control.Monad (unless, void)

import Data.ByteString.Lazy.Internal (defaultChunkSize)
import Data.IORef (atomicModifyIORef', newIORef, readIORef)
import qualified Data.Binary             as B
import qualified Data.ByteString         as BS
import qualified Data.ByteString.Lazy    as LB
import qualified Data.Streaming.FileRead as FR

import qualified System.IO as IO

import Rx.Disposable (createDisposable, newCompositeDisposable, toDisposable)
import Rx.Observable (Observable (..), onCompleted, onError, onNext)
import qualified Rx.Disposable as Disposable
import qualified Rx.Observable as Rx
import qualified Rx.Scheduler  as Rx (IScheduler, schedule)

--------------------------------------------------------------------------------

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


fileObservable
  :: Rx.IScheduler scheduler
     => scheduler s -> FilePath -> Observable s BS.ByteString
fileObservable scheduler path = Observable $ \observer ->
      Rx.schedule scheduler $
        bracketWithException (FR.openFile path)
                             FR.closeFile
                             (onError observer)
                             (loop observer)
  where
    loop observer h = do
      bs <- FR.readChunk h
      if BS.null bs
        then onCompleted observer
        else onNext observer bs >> loop observer h

handleObservable
  :: Rx.IScheduler scheduler
     => scheduler s -> IO.Handle -> Observable s BS.ByteString
handleObservable scheduler h = Observable $ \observer ->
      Rx.schedule scheduler $ loop observer
  where
    loop observer = do
      result <- try $ BS.hGetSome h defaultChunkSize
      case result of
        Right bs
          | BS.null bs -> onCompleted observer
          | otherwise  -> onNext observer bs
        Left err -> onError observer err


toHandle
  :: Rx.IObservable source => source s BS.ByteString -> IO.Handle -> IO Rx.Disposable
toHandle source h = Rx.subscribeOnNext source (BS.hPutStr h)

toFile
  :: Rx.IObservable source => source s BS.ByteString -> FilePath -> IO Rx.Disposable
toFile source filepath = do
  h <- IO.openFile filepath IO.WriteMode
  mainDisposable <- newCompositeDisposable
  sourceDisposable <-
    Rx.subscribe source (BS.hPutStr h)
                        (\err -> IO.hClose h >> throwIO err)
                        (IO.hClose h)
  fileDisposable <- createDisposable $ IO.hClose h
  Disposable.append sourceDisposable mainDisposable
  Disposable.append fileDisposable mainDisposable
  return $ toDisposable mainDisposable

--------------------------------------------------------------------------------

lines
  :: Rx.IObservable source
     => source s BS.ByteString
     -> Observable s BS.ByteString
lines source = Observable $ \observer -> do
    bufferVar <- newIORef id
    main bufferVar observer
  where
    newline = 10
    main bufferVar observer =
        Rx.subscribe
          source (onNext_ id) onError_ onCompleted_
      where
        onNext_ appendPrev inputBS = do
          let (first, second) = BS.breakByte newline inputBS
          case BS.uncons second of
            Just (_, withoutNL) -> do
              onNext observer (appendPrev first)
              onNext_ id withoutNL
            Nothing ->
              atomicModifyIORef' bufferVar
                 $ \_ ->
                 let rest = appendPrev inputBS
                 in (BS.append rest, ())


        emitRemaining = do
          appendPrev <- readIORef bufferVar
          let outputBS = appendPrev BS.empty
          unless (BS.null outputBS) $ onNext observer outputBS

        onError_ err = do
          emitRemaining
          onError observer err

        onCompleted_ = do
          emitRemaining
          onCompleted observer

unlines
  :: Rx.IObservable source
     => source s BS.ByteString -> Observable s BS.ByteString
unlines = Rx.concatMap $ \input -> [input, newline]
  where
    newline = BS.pack [10]


encode :: (B.Binary b, Rx.IObservable source)
       => source s b
       -> Observable s BS.ByteString
encode =
  unlines
  . Rx.concatMap (LB.toChunks . B.encode)

decode :: (B.Binary b, Rx.IObservable source)
       => source s BS.ByteString
       -> Observable s b
decode =
  Rx.map (B.decode . LB.fromChunks . return)
  . lines
