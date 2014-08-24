module Main where

import qualified Control.Concurrent.Async as Async
import           Control.Monad            (void)

import Rx.Logger            (defaultSettings, newLogger, setupLogTracer,
                             ttccFormat)
import Rx.Logger.Monad      (trace, withLogger)
import Rx.Logger.Serializer (serializeToHandle)

import Rx.Observable (onCompleted, toAsyncObservable)
import System.IO     (stdout)

main :: IO ()
main = do
  logger <- newLogger
  void $ setupLogTracer defaultSettings logger
  void $ serializeToHandle stdout ttccFormat $ toAsyncObservable logger

  a1 <- Async.async $ do
    withLogger logger $ trace "Trace 1"
    withLogger logger $ trace "Logger 2"

  a2 <- Async.async $ do
    withLogger logger $ trace "Trace 1"
    withLogger logger $ trace "Logger 2"

  void $ Async.waitEither a1 a2

  onCompleted logger
