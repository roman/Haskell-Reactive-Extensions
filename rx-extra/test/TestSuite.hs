module Main where

import Test.Hspec (hspec)
import qualified Rx.BinaryTest

main :: IO ()
main = hspec Rx.BinaryTest.tests
