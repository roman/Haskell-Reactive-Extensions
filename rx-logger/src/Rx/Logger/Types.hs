{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE ExistentialQuantification  #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Rx.Logger.Types
       ( module Rx.Logger.Types
       , MonadIO(..)
       , LText.Text
       , ReaderT
       , lift
       , ask
       , local
       , runReaderT
       ) where


import Data.Typeable (Typeable)
import GHC.Generics  (Generic)

import Control.Concurrent         (ThreadId)
import Control.Monad.Trans        (MonadIO (..), lift)
import Control.Monad.Trans.Reader (ReaderT, ask, local, runReaderT)

import qualified Data.Text      as Text
import qualified Data.Text.Lazy as LText
import           Data.Time      (UTCTime)

import Rx.Subject (Subject)

--------------------------------------------------------------------------------

type Logger = Subject LogEntry
type LogEntryFormatter = LogEntry -> LText.Text

data LogMsg
  = forall a. ToLogMsg a => LogMsg a
  deriving (Typeable)

data LogEntry
  = LogEntry {
    _logEntryTimestamp :: !UTCTime
  , _logEntryMsg       :: !LogMsg
  , _logEntryLevel     :: !LogLevel
  , _logEntryThreadId  :: !ThreadId
  }
  deriving (Show, Typeable, Generic)

data LogLevel
  = TRACE   -- ^ Indicates normal tracing information.

  | LOUD    -- ^ Indicates a fairly detailed tracing message. By
            -- default logging calls for entering, returning, or
            -- throwing an exception are traced at this level

  | NOISY   -- ^ Indicates a highly detailed tracing message

  | CONFIG  -- ^ Intended to provide a variety of static configuration
            -- information, to assist in debugging problems that may be
            -- associated with particular configurations.

  | INFO    -- ^ Describe events to be used for reasonably
            -- significant messages that will make sense to end users
            -- and system administrators

  | WARNING -- ^ Describe events that will be of interest to
            -- end users or system managers, or which indicate
            -- potential problems

  | SEVERE  -- ^ Describe events that are of considerable importance
            -- and which will prevent normal program execution. They
            -- should be reasonably intelligible to end users and to
            -- system administrators

  | NONE    -- ^ Special level that can be used to turn off logging
  deriving (Show, Eq, Ord, Enum, Generic, Typeable)

--------------------------------------------------------------------------------
-- * class definitions

class (Show a, Typeable a) => ToLogMsg a where
  toLogMsg :: a -> LText.Text
  toLogMsg = LText.pack . show

class ToLogger a where
  toLogger :: a -> Logger

--------------------------------------------------------------------------------
-- * instances

instance ToLogger (Subject LogEntry) where
  toLogger = id

instance ToLogMsg LText.Text where
  toLogMsg = id

instance ToLogMsg Text.Text where
  toLogMsg = LText.fromChunks . (:[])

instance ToLogMsg String where
  toLogMsg = LText.pack

instance ToLogMsg LogMsg where
  toLogMsg (LogMsg a) = toLogMsg a

instance Show LogMsg where
  show (LogMsg a) = show a

--------------------------------------------------------------------------------
