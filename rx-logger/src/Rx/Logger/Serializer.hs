{-# LANGUAGE FlexibleContexts #-}
module Rx.Logger.Serializer where

import Control.Exception (throw)
import Control.Monad     (when)

import qualified Data.Text.Lazy.IO as LText


import           Rx.Disposable (Disposable, createDisposable,
                                newCompositeDisposable)
import qualified Rx.Disposable as Disposable
import qualified Rx.Observable as Ob

import System.IO (BufferMode (LineBuffering), Handle, IOMode (AppendMode),
                  hClose, hIsOpen, hSetBuffering, openFile)

import Rx.Logger.Types

serializeToHandle :: (Ob.IObservable logger)
                  => Handle
                  -> LogEntryFormatter
                  -> logger Ob.Async LogEntry
                  -> IO Disposable
serializeToHandle handle entryF source = do
  hSetBuffering handle LineBuffering
  Ob.subscribe source
    (\output -> do
      isOpen <- hIsOpen handle
      when isOpen $
        LText.hPutStrLn handle $ entryF output)
    (\err -> throw err)
    (return ())

serializeToFile :: (Ob.IObservable logger)
                => FilePath
                -> LogEntryFormatter
                -> logger Ob.Async LogEntry
                -> IO Disposable
serializeToFile filepath entryF source = do
  allDisposables <- newCompositeDisposable
  handle <- openFile filepath AppendMode
  hSetBuffering handle LineBuffering
  loggerSub <-
    Ob.subscribe source
                (\output -> do
                    isOpen <- hIsOpen handle
                    when isOpen $
                      LText.hPutStrLn handle $ entryF output)
                (\err -> hClose handle >> throw err)
                (hClose handle)


  Disposable.append loggerSub allDisposables
  createDisposable (hClose handle) >>= flip Disposable.append allDisposables
  return $ Disposable.toDisposable allDisposables
