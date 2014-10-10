module Rx.BinaryTest where

import Control.Exception (finally)
import Control.Monad (void)

import System.Directory (getTemporaryDirectory, removeFile)
import System.FilePath (joinPath)

import qualified Rx.Binary     as Rxb (decode, encode, fromFile, toFile)
import qualified Rx.Observable as Rx (currentThread, fromList, newThread,
                                      toEither, toList)

import Test.HUnit (assertEqual, assertFailure)
import Test.Hspec


tests :: Spec
tests = do
  describe "Rx.Binary.encode/decode" $ do
    it "can serialize/deserialize" $ do
      dir <- getTemporaryDirectory
      let input = [1..100] :: [Int]
          filename = joinPath [dir, "encode_decode_test"]
          writeSource = Rxb.encode $ Rx.fromList Rx.newThread input
          readSource  = Rxb.decode $ Rxb.fromFile Rx.currentThread filename

      flip finally (removeFile filename) $ do
        void $ Rx.toEither (Rxb.toFile filename writeSource)
        result <- Rx.toList readSource
        case result of
          Right output ->
            assertEqual "serialization/deserialization doesn't work"
                        input (reverse output)
          Left (_, err) -> assertFailure $ show err
