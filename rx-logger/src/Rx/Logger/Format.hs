{-# LANGUAGE OverloadedStrings #-}
module Rx.Logger.Format where

import Data.Monoid ((<>))
import Data.Text.Format (format, left)
import Data.Text.Lazy.Builder (toLazyText)
import Data.Time.Format (formatTime)
import System.Locale (defaultTimeLocale)
import qualified Data.Text.Lazy as LText

import Rx.Logger.Types

showFormat :: LogEntry -> LText.Text
showFormat = LText.pack . show

ttccFormat :: LogEntry -> LText.Text
ttccFormat logEntry =
  LText.pack (formatTime defaultTimeLocale
                         "%m-%e-%Y %I:%M:%S %p %q"
                         $ _logEntryTimestamp logEntry)
  <> " ["
  <> toLazyText (left 12 ' ' . show $ _logEntryThreadId logEntry)
  <> "] "
  <> toLazyText (left 6 ' ' . show $ _logEntryLevel logEntry)
  <> " - "
  <> toLogMsg (_logEntryMsg logEntry)
