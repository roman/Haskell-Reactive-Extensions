{-# LANGUAGE BangPatterns       #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE NoImplicitPrelude  #-}
module Rx.Binary (
    fromFile
  , toFile
  , fromHandle
  , toHandle
  , sepBy
  , joinWith
  , encode
  , decode
  , lines
  , unlines
  ) where

import           Control.Exception             (Exception (..), SomeException,
                                                catch, mask, throwIO, try)
import           Control.Monad                 (unless, void)
import           Data.ByteString.Lazy.Internal (defaultChunkSize)
import           Data.IORef                    (atomicModifyIORef', newIORef,
                                                readIORef)
import           Data.Monoid                   ((<>))
import           Data.Typeable                 (Typeable)
import           Prelude.Compat                hiding (lines, unlines)

import qualified Data.Binary                   as B
import qualified Data.ByteString               as BS
import qualified Data.ByteString.Lazy          as LB
import qualified Data.Streaming.FileRead       as FR
import qualified System.IO                     as IO

import           Rx.Observable                 (Observable (..), onCompleted,
                                                onError, onNext)
import qualified Rx.Observable                 as Rx

--------------------------------------------------------------------------------

data DecodeError
  = DecodeError String
  deriving (Show, Typeable)

instance Exception DecodeError

--------------------------------------------------------------------------------

bracketWithException
  :: IO h -> (h -> IO b) -> (SomeException -> IO ()) -> (h -> IO b) -> IO b
bracketWithException !accquire !release !onErrorCb !perform =
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
{-# INLINE bracketWithException #-}

fromFile
  :: Rx.IScheduler scheduler
     => scheduler s -> FilePath -> Observable s BS.ByteString
fromFile !scheduler !path = Observable $ \observer ->
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
{-# INLINE fromFile #-}

fromHandle
  :: Rx.IScheduler scheduler
     => scheduler s -> IO.Handle -> Observable s BS.ByteString
fromHandle !scheduler !h = Observable $ \observer ->
      Rx.schedule scheduler $ loop observer
  where
    loop observer = do
      result <- try $ BS.hGetSome h defaultChunkSize
      case result of
        Right bs
          | BS.null bs -> onCompleted observer
          | otherwise  -> onNext observer bs >> loop observer
        Left err -> onError observer err
{-# INLINE fromHandle #-}

--------------------

toHandle
  :: IO.Handle -> Observable s BS.ByteString -> Observable s ()
toHandle !h !source = Observable $ \observer ->
  Rx.subscribe source (BS.hPutStr h)
                      (onError observer)
                      (do onNext observer ()
                          onCompleted observer)
{-# INLINE toHandle #-}

toFile :: FilePath -> Observable s BS.ByteString -> Observable s ()
toFile !filepath !source = Observable $ \observer -> do
  h <- IO.openFile filepath IO.WriteMode
  sourceDisposable <-
    Rx.subscribe source (BS.hPutStr h)
                        (\err -> do
                            IO.hClose h
                            onError observer err)
                        (do IO.hClose h
                            onNext observer ()
                            onCompleted observer)
  fileDisposable <- Rx.newDisposable "Observable.toFile" $ IO.hClose h
  return $ sourceDisposable <> fileDisposable
{-# INLINE toFile #-}


--------------------

sepBy
  :: B.Word8
     -> Observable s BS.ByteString
     -> Observable s BS.ByteString
sepBy !sepByte !source = Observable $ \observer -> do
    bufferVar <- newIORef id
    main bufferVar observer
  where
    main bufferVar observer =
        Rx.subscribe
          source (onNext_ id) onError_ onCompleted_
      where
        onNext_ appendPrev inputBS = do
          let (first, second) = BS.break (sepByte ==) inputBS
          case BS.uncons second of
            Just (_, rest) -> do
              onNext observer (appendPrev first)
              onNext_ id rest
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
{-# INLINE sepBy #-}

joinWith
  :: B.Word8
     -> Observable s BS.ByteString
     -> Observable s BS.ByteString
joinWith !sepByte = Rx.map $ \input -> input <> sepBS
  where
    sepBS = BS.pack [sepByte]
{-# INLINE joinWith #-}

--------------------

lines
  :: Observable s BS.ByteString
     -> Observable s BS.ByteString
lines = sepBy 10
{-# INLINE lines #-}

unlines
  :: Observable s BS.ByteString
     -> Observable s BS.ByteString
unlines = joinWith 10
{-# INLINE unlines #-}

--------------------

encode :: (B.Binary b)
       => Observable s b
       -> Observable s BS.ByteString
encode =
  joinWith 0
  . Rx.concatMap (LB.toChunks . B.encode)
{-# INLINE encode #-}

decode :: (B.Binary b)
       => Observable s BS.ByteString
       -> Observable s b
decode !source0 = Observable $ \observer -> main observer
  where
    main observer = do
        let source = Rx.map (LB.fromChunks . return) source0
        Rx.subscribe source onNext_ onError_ onCompleted_
      where
        onNext_ inputBS =
          case B.decodeOrFail inputBS of
            Left  (_, _, errMsg) -> throwIO $ DecodeError errMsg
            Right (remainder0, _, b) -> do
              onNext observer b
              let remainder = LB.tail remainder0
              unless (LB.null remainder) $ onNext_ remainder
        onError_ = onError observer
        onCompleted_ = onCompleted observer
{-# INLINE decode #-}
