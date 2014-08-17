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
       -> logger
       -> msg
       -> IO ()
logMsg level logger0 msg = do
  let logger = toLogger logger0
  time   <- getCurrentTime
  tid    <- myThreadId
  onNext logger $! LogEntry time (LogMsg msg) level tid

trace :: (ToLogger logger, ToLogMsg msg) => logger -> msg -> IO ()
trace = logMsg TRACE

loud :: (ToLogger logger, ToLogMsg msg) => logger -> msg -> IO ()
loud = logMsg LOUD

noisy :: (ToLogger logger, ToLogMsg msg) => logger -> msg -> IO ()
noisy = logMsg NOISY

config :: (ToLogger logger, ToLogMsg msg) => logger -> msg -> IO ()
config = logMsg CONFIG

info :: (ToLogger logger, ToLogMsg msg) => logger -> msg -> IO ()
info = logMsg INFO

warn :: (ToLogger logger, ToLogMsg msg) => logger -> msg -> IO ()
warn = logMsg WARNING

severe :: (ToLogger logger, ToLogMsg msg) => logger -> msg -> IO ()
severe = logMsg SEVERE

logF ::
  (ToLogger logger, Params params)
  => LogLevel -> logger -> Format -> params -> IO ()
logF level logger txtFormat params =
  logMsg level logger (format txtFormat params)

traceF ::
  (ToLogger logger, Params params) => logger -> Format -> params -> IO ()
traceF = logF TRACE

loudF ::
  (ToLogger logger, Params params) => logger -> Format -> params -> IO ()
loudF = logF LOUD

noisyF ::
  (ToLogger logger, Params params) => logger -> Format -> params -> IO ()
noisyF = logF NOISY

configF ::
  (ToLogger logger, Params params) => logger -> Format -> params -> IO ()
configF = logF CONFIG

infoF ::
  (ToLogger logger, Params params) => logger -> Format -> params -> IO ()
infoF = logF INFO

warnF ::
  (ToLogger logger, Params params) => logger -> Format -> params -> IO ()
warnF = logF WARNING

severeF ::
  (ToLogger logger, Params params) => logger -> Format -> params -> IO ()
severeF = logF SEVERE
