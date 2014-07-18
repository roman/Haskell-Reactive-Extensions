{-# LANGUAGE OverloadedStrings #-}
module Rx.Logger.Format where

import           Data.Monoid      ((<>))
import qualified Data.Text.Lazy   as LText
import           Data.Time.Format (formatTime)
import           System.Locale    (defaultTimeLocale)

import Rx.Logger.Types

showFormat :: LogEntry -> LText.Text
showFormat = LText.pack . show

ttccFormat :: LogEntry -> LText.Text
ttccFormat logEntry =
  LText.pack (formatTime defaultTimeLocale
                         "%m-%e-%Y %I:%M:%S %p %q"
                         $ _logEntryTimestamp logEntry)
  <> " [" <> LText.pack (show $ _logEntryThreadId logEntry) <> "] "
  <> LText.pack (show $ _logEntryLevel logEntry) <> " - "
  <> toLogMsg (_logEntryMsg logEntry)
