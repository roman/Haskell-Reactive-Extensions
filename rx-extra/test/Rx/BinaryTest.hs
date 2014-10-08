module Rx.BinaryTest where

import Control.Exception (finally)
import Control.Monad (void)

import System.Directory (getTemporaryDirectory, removeFile)
import System.FilePath (joinPath)

import qualified Rx.Binary     as Rx (decode, encode, fromFile, toFile)
import qualified Rx.Observable as Rx (currentThread, fromList, toList)

import Test.HUnit (assertEqual, assertFailure)
import Test.Hspec


tests :: Spec
tests = do
  describe "Rx.Binary.encode/decode" $ do
    it "can serialize/deserialize" $ do
      dir <- getTemporaryDirectory
      let input = [1..100] :: [Int]
          filename = joinPath [dir, "encode_decode_test"]
          writeSource = Rx.encode $ Rx.fromList Rx.currentThread input
          readSource  = Rx.decode $ Rx.fromFile Rx.currentThread filename

      flip finally (removeFile filename) $ do
        void $ Rx.toFile writeSource filename
        result <- Rx.toList readSource
        case result of
          Right output ->
            assertEqual "serialization/deserialization doesn't work"
                        input (reverse output)
          Left (_, err) -> assertFailure $ show err
