{-# LANGUAGE FlexibleContexts #-}
module Rx.Logger.Serializer where

import Control.Exception (throw)
import Control.Monad     (when)

import qualified Data.Text.Lazy.IO as LText


import           Rx.Disposable (Disposable, createDisposable,
                                newCompositeDisposable)
import qualified Rx.Disposable as Disposable

import           Rx.Observable (toAsyncObservable)
import qualified Rx.Observable as Observable

import System.IO (BufferMode (LineBuffering), Handle, IOMode (AppendMode),
                  hClose, hIsOpen, hSetBuffering, openFile)

import Rx.Logger.Types

serializeToHandle :: (HasLogger logger)
                  => Handle
                  -> LogEntryFormatter
                  -> logger
                  -> IO Disposable
serializeToHandle handle entryF source = do
  hSetBuffering handle LineBuffering
  Observable.safeSubscribe (toAsyncObservable (getLogger source))
    (\output -> do
      isOpen <- hIsOpen handle
      when isOpen $
        LText.hPutStrLn handle $ entryF output)
    (\err -> throw err)
    (return ())

serializeToFile :: (HasLogger logger)
                => FilePath
                -> LogEntryFormatter
                -> logger
                -> IO Disposable
serializeToFile filepath entryF source = do
  allDisposables <- newCompositeDisposable
  handle <- openFile filepath AppendMode
  hSetBuffering handle LineBuffering
  loggerSub <- Observable.safeSubscribe (toAsyncObservable (getLogger source))
    (\output -> do
      isOpen <- hIsOpen handle
      when isOpen $
        LText.hPutStrLn handle $ entryF output)
    (\err -> hClose handle >> throw err)
    (hClose handle)


  Disposable.append loggerSub allDisposables
  createDisposable (hClose handle) >>= flip Disposable.append allDisposables
  return $ Disposable.toDisposable allDisposables
