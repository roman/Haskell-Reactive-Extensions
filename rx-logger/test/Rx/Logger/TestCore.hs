{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE TemplateHaskell #-}
module Rx.Logger.TestCore where

import Control.Monad (void)
import Data.Monoid ((<>))
import Data.Typeable (Typeable)
import qualified Data.Text.Lazy as Text
import Control.Concurrent.MVar (newMVar, takeMVar, modifyMVar_)

import Test.HUnit (assertEqual)
import Test.Hspec

import qualified Rx.Observable as Observable
import Rx.Logger.Types
import Rx.Logger.Core

--------------------------------------------------------------------------------

data User
  = User {
    _userName  :: String
  , _userEmail :: String
  }
  deriving (Show, Typeable)

instance ToLogMsg User where
  toLogMsg (User name email) =
     Text.pack "User log message with name "
     <> Text.pack name
     <> Text.pack " and email "
     <> Text.pack email

--------------------------------------------------------------------------------

assertLogScope :: String -> LogEntry -> IO ()
assertLogScope scopeVal =
  assertEqual "should have same scope" scopeVal
        . show . _logEntryScope

assertLogMsg :: ToLogMsg a => a -> LogEntry -> IO ()
assertLogMsg msg =
  assertEqual "should have same message" (toLogMsg msg) . toLogMsg . _logEntryMsg

assertLogLevel :: LogLevel -> LogEntry -> IO ()
assertLogLevel level =
  assertEqual "should have same log level" level
        . _logEntryLevel

testLogScope :: (Logger -> IO a) -> ([LogEntry] -> IO b) -> IO b
testLogScope loggerAction assertionAction = do
  logger <- newLogger
  accVar <- newMVar []
  void $ Observable.subscribeOnNext logger
    $ \v -> modifyMVar_ accVar (return . (v:))
  void $ loggerAction logger
  Observable.onCompleted logger
  result <- takeMVar accVar
  assertionAction result

--------------------------------------------------------------------------------

tests :: Spec
tests = do
  describe "scope" $ do
    it "emits messages to the logger subject" $
      testLogScope
        (\logger ->
          scope logger 'tests $ do
            trace "message 1"
            trace "message 2")
        (\(result1:result2:_) -> do
          assertLogLevel FINE result1
          assertLogLevel FINE result2
          assertLogMsg "message 2" result1
          assertLogMsg "message 1" result2
          assertLogScope "Rx.Logger.TestCore.tests" result1
          assertLogScope "Rx.Logger.TestCore.tests" result2)

    it "respects log levels specified" $
      testLogScope
        (\logger ->
          scope logger 'tests $ do
            trace "message 1"
            warn  "message 2")
        (\(result1:result2:_) -> do
          assertLogLevel WARNING result1
          assertLogLevel FINE result2
          assertLogMsg "message 1" result2
          assertLogMsg "message 2" result1
          assertLogScope "Rx.Logger.TestCore.tests" result1
          assertLogScope "Rx.Logger.TestCore.tests" result2)

  describe "scopeWithLevel" $ do
    it "emits messages to the logger subject" $
      testLogScope
        (\logger ->
          scopeWithLevel SEVERE logger 'tests $ do
            trace "message 1"
            trace "message 2")
        (\(result1:result2:_) -> do
          assertLogMsg "message 2" result1
          assertLogMsg "message 1" result2
          assertLogScope "Rx.Logger.TestCore.tests" result1
          assertLogScope "Rx.Logger.TestCore.tests" result2)

    it "does not respect log levels specified on trace fn" $
      testLogScope
        (\logger ->
          scopeWithLevel SEVERE logger 'tests $ do
            trace "message 1"
            warn  "message 2")
        (\(result1:result2:_) -> do
          assertLogLevel SEVERE result1
          assertLogLevel SEVERE result2)

  describe "ToLogMsg" $ do
    it "allow to log records that implement ToLogMsg" $ do
      testLogScope
        (\logger ->
          scope logger 'tests $ do
            trace (User "Roman" "romanandreg@gmail.com"))
        (\(result:_) -> do
          assertLogMsg
            "User log message with name Roman and email romanandreg@gmail.com"
            result)
