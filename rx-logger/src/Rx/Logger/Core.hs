{-# LANGUAGE FlexibleContexts #-}
module Rx.Logger.Core where

import Control.Concurrent (myThreadId)

import Data.Text.Format        (Format, format)
import Data.Text.Format.Params (Params)
import Data.Time               (getCurrentTime)

import Rx.Observable (onNext)
import Rx.Subject    (newPublishSubject)

import Rx.Logger.Types

--------------------------------------------------------------------------------

newLogger :: IO Logger
newLogger = newPublishSubject


logMsg :: (ToLogger logger, ToLogMsg msg)
       => LogLevel
       -> msg
       -> logger
       -> IO ()
logMsg level msg logger0 = do
  let logger = toLogger logger0
  time   <- getCurrentTime
  tid    <- myThreadId
  onNext logger $! LogEntry time (LogMsg msg) level tid

trace :: (ToLogger logger, ToLogMsg msg) => msg -> logger -> IO ()
trace = logMsg TRACE

loud :: (ToLogger logger, ToLogMsg msg) => msg -> logger -> IO ()
loud = logMsg LOUD

noisy :: (ToLogger logger, ToLogMsg msg) => msg -> logger -> IO ()
noisy = logMsg NOISY

config :: (ToLogger logger, ToLogMsg msg) => msg -> logger -> IO ()
config = logMsg CONFIG

info :: (ToLogger logger, ToLogMsg msg) => msg -> logger -> IO ()
info = logMsg INFO

warn :: (ToLogger logger, ToLogMsg msg) => msg -> logger -> IO ()
warn = logMsg WARNING

severe :: (ToLogger logger, ToLogMsg msg) => msg -> logger -> IO ()
severe = logMsg SEVERE

logF ::
  (ToLogger logger, Params params)
  => LogLevel -> Format -> params -> logger -> IO ()
logF level txtFormat params = logMsg level (format txtFormat params)

traceF ::
  (ToLogger logger, Params params) => Format -> params -> logger -> IO ()
traceF = logF TRACE

loudF ::
  (ToLogger logger, Params params) => Format -> params -> logger -> IO ()
loudF = logF LOUD

noisyF ::
  (ToLogger logger, Params params) => Format -> params -> logger -> IO ()
noisyF = logF NOISY

configF ::
  (ToLogger logger, Params params) => Format -> params -> logger -> IO ()
configF = logF CONFIG

infoF ::
  (ToLogger logger, Params params) => Format -> params -> logger -> IO ()
infoF = logF INFO

warnF ::
  (ToLogger logger, Params params) => Format -> params -> logger -> IO ()
warnF = logF WARNING

severeF ::
  (ToLogger logger, Params params) => Format -> params -> logger -> IO ()
severeF = logF SEVERE
