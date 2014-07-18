module Main where

import qualified Control.Concurrent.Async as Async
import           Control.Monad            (void)

import Rx.Logger            (defaultSettings, newLogger, setupTracer, trace,
                             ttccFormat, withLogger)
import Rx.Logger.Serializer (serializeToHandle)
-- import qualified Rx.Logger.Serializer.Color as Color (serializeToHandle)

import Rx.Observable (onCompleted)
import System.IO     (stdout)

main :: IO ()
main = do
  logger <- newLogger
  void $ setupTracer defaultSettings logger
  void $ serializeToHandle stdout ttccFormat logger
  -- Color.serializeToHandle _logEntryThreadId ttccFormat stdout logger

  a1 <- Async.async $ do
    withLogger logger $ trace "Trace 1"
    withLogger logger $ trace "Logger 2"

  a2 <- Async.async $ do
    withLogger logger $ trace "Trace 1"
    withLogger logger $ trace "Logger 2"

  void $ Async.waitEither a1 a2

  onCompleted logger
