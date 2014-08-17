{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Rx.Logger.Monad where

import Control.Applicative (Applicative, (<$>))
import Control.Monad       (liftM)

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

--------------------------------------------------------------------------------

newtype LogT m a
  = LogT (ReaderT Logger m a)
  deriving (Functor, Applicative, Monad, MonadIO)

instance (MonadIO m) => MonadLog (LogT m) where
  logMsg level msg = LogT $ do
    logger <- ask
    liftIO $ Core.logMsg level logger msg

withLogger :: (ToLogger logger, MonadIO m)
      => logger
      -> LogT m result
      -> m result
withLogger logger (LogT action) =
  runReaderT action $ toLogger logger

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
