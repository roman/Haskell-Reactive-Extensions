{-# LANGUAGE FlexibleContexts #-}
module Rx.Logger.Core where

import Data.Text.Format        (Format, format)
import Data.Text.Format.Params (Params)

import Rx.Subject (newPublishSubject)

import Rx.Logger.Types

--------------------------------------------------------------------------------

newLogger :: IO Logger
newLogger = newPublishSubject

--------------------------------------------------------------------------------

withLogger :: ( MonadIO m, HasLogger s )
      => s
      -> ReaderT Logger m result
      -> m result
withLogger s action = runReaderT action (getLogger s)

withLogger'
  :: ( MonadIO m, HasLogger s )
  => LogLevel
  -> s
  -> ReaderT (LogLevel, Logger) m result
  -> m result
withLogger' level s action =
  runReaderT action (level, getLogger s)

--------------------------------------------------------------------------------

logF :: (MonadLog m, Params p) => LogLevel -> Format -> p -> m ()
logF level txtFormat params = logMsg level $ format txtFormat params

traceF :: (MonadLog m, Params p) => Format -> p -> m ()
traceF = logF TRACE

loudF :: (MonadLog m, Params p) => Format -> p -> m ()
loudF = logF LOUD

noisyF :: (MonadLog m, Params p) => Format -> p -> m ()
noisyF = logF NOISY

configF :: (MonadLog m, Params p) => Format -> p -> m ()
configF = logF CONFIG

infoF :: (MonadLog m, Params p) => Format -> p -> m ()
infoF = logF INFO

warnF :: (MonadLog m, Params p) => Format -> p -> m ()
warnF = logF WARNING

severeF :: (MonadLog m, Params p) => Format -> p -> m ()
severeF = logF SEVERE

--------------------------------------------------------------------------------
