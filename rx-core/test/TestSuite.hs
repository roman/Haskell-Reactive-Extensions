module Main where

import Test.Hspec (hspec)

import qualified Rx.Observable.FoldTest
import qualified Rx.Observable.TimeoutTest

main :: IO ()
main = hspec $ do
  Rx.Observable.FoldTest.tests
  Rx.Observable.TimeoutTest.tests
