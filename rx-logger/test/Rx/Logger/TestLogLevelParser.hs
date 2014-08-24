{-# LANGUAGE OverloadedStrings #-}
module Rx.Logger.TestLogLevelParser where

import           Control.Monad (forM_)
import qualified Data.Set      as Set
import qualified Data.Text     as Text

import Test.Hspec
import Test.HUnit (assertBool, assertFailure)

import Rx.Logger.LogLevelParser
import Rx.Logger.Types


allLogLevels = Set.fromList $ enumFrom NOISY

assertLogLevelParser
  :: Text.Text
  -> [LogLevel]
  -> IO ()
assertLogLevelParser input expected0 = do
    case parseLogLevel input of
      Just pred -> do
        forM_ (Set.toList expected) $ \level->
          assertBool ("'"
                      ++ inputS
                      ++ "' should match level " ++ show level)
                     (pred level)
        forM_ (Set.toList unexpected) $ \level->
          assertBool ("'"
                      ++ inputS
                      ++ "' should not match level " ++ show level)
                     (not $ pred level)
      Nothing -> assertFailure $ "'" ++ inputS ++ "' is an invalid input"
  where
    inputS = Text.unpack input
    expected   = Set.fromList expected0
    unexpected = Set.difference expected allLogLevels



tests :: Spec
tests = do
  describe "parseLogLevel" $ do
    describe "when only one log level is given" $
      it "parses specified log level only" $ do
        assertLogLevelParser "noisy" [NOISY]
        assertLogLevelParser "NoIsY" [NOISY]

    describe "when many log levels are given" $
      it "parses every specified log level" $
        assertLogLevelParser "info, trace" [INFO, TRACE]

    describe "when input includes a comparision operator" $
      it "parses every LogLevel in the given range" $
        assertLogLevelParser "<= loud, >= warning" [NOISY, LOUD, WARNING, SEVERE]

    describe "when multiple log level and comparision operators" $
      it "parses every LogLevel correctly" $
        assertLogLevelParser "< loud, >= warning, trace" [NOISY, TRACE, WARNING, SEVERE]

    describe "when none is given" $
      it "no LogLevel should match" $ do
        assertLogLevelParser "none" []
        assertLogLevelParser "none, trace" []
        assertLogLevelParser "none, >= trace" []
