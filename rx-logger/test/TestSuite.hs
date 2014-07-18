module Main where

import qualified Rx.Logger.TestCore
import Test.Hspec

main :: IO ()
main = hspec Rx.Logger.TestCore.tests
