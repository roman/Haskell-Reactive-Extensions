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


logMsg :: (HasLogger logger, ToLogMsg msg)
       => LogLevel
       -> msg
       -> logger
       -> IO ()
logMsg level msg logger0 = do
  let logger = getLogger logger0
  time   <- getCurrentTime
  tid    <- myThreadId
  onNext logger $! LogEntry time (LogMsg msg) level tid

trace :: (HasLogger logger, ToLogMsg msg) => msg -> logger -> IO ()
trace = logMsg TRACE

loud :: (HasLogger logger, ToLogMsg msg) => msg -> logger -> IO ()
loud = logMsg LOUD

noisy :: (HasLogger logger, ToLogMsg msg) => msg -> logger -> IO ()
noisy = logMsg NOISY

config :: (HasLogger logger, ToLogMsg msg) => msg -> logger -> IO ()
config = logMsg CONFIG

info :: (HasLogger logger, ToLogMsg msg) => msg -> logger -> IO ()
info = logMsg INFO

warn :: (HasLogger logger, ToLogMsg msg) => msg -> logger -> IO ()
warn = logMsg WARNING

severe :: (HasLogger logger, ToLogMsg msg) => msg -> logger -> IO ()
severe = logMsg SEVERE

logF ::
  (HasLogger logger, Params params)
  => LogLevel -> Format -> params -> logger -> IO ()
logF level txtFormat params = logMsg level (format txtFormat params)

traceF ::
  (HasLogger logger, Params params) => Format -> params -> logger -> IO ()
traceF = logF TRACE

loudF ::
  (HasLogger logger, Params params) => Format -> params -> logger -> IO ()
loudF = logF LOUD

noisyF ::
  (HasLogger logger, Params params) => Format -> params -> logger -> IO ()
noisyF = logF NOISY

configF ::
  (HasLogger logger, Params params) => Format -> params -> logger -> IO ()
configF = logF CONFIG

infoF ::
  (HasLogger logger, Params params) => Format -> params -> logger -> IO ()
infoF = logF INFO

warnF ::
  (HasLogger logger, Params params) => Format -> params -> logger -> IO ()
warnF = logF WARNING

severeF ::
  (HasLogger logger, Params params) => Format -> params -> logger -> IO ()
severeF = logF SEVERE
