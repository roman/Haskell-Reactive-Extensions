{-# LANGUAGE FlexibleContexts  #-}
{-# LANGUAGE FlexibleInstances #-}
module Rx.Logger.Monad where

import Data.Text.Format        (Format, format)
import Data.Text.Format.Params (Params)

import qualified Rx.Logger.Core  as Core
import           Rx.Logger.Types

--------------------------------------------------------------------------------

class MonadLog m where
  logMsg :: ToLogMsg a => LogLevel -> a -> m ()

trace :: (MonadLog m, ToLogMsg a) => a -> m ()
trace = logMsg TRACE

loud :: (MonadLog m, ToLogMsg a) => a -> m ()
loud = logMsg LOUD

noisy :: (MonadLog m, ToLogMsg a) => a -> m ()
noisy = logMsg NOISY

config :: (MonadLog m, ToLogMsg a) => a -> m ()
config = logMsg CONFIG

info :: (MonadLog m, ToLogMsg a) => a -> m ()
info = logMsg INFO

warn :: (MonadLog m, ToLogMsg a) => a -> m ()
warn = logMsg WARNING

severe :: (MonadLog m, ToLogMsg a) => a -> m ()
severe = logMsg SEVERE

--------------------

instance MonadIO m => MonadLog (ReaderT Logger m) where
  logMsg level msg = do
    logger <- ask
    liftIO $ Core.logMsg level msg logger

instance MonadIO m => MonadLog (ReaderT (LogLevel, Logger) m) where
  logMsg _ msg = do
    (level, logger) <- ask
    liftIO $ Core.logMsg level msg logger

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
