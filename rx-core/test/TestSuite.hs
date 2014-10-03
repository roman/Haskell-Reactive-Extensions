module Main where

import Test.Hspec (hspec)

import qualified Rx.Observable.FoldTest
import qualified Rx.Observable.MergeTest
import qualified Rx.Observable.TimeoutTest

main :: IO ()
main = hspec $ do
  Rx.Observable.FoldTest.tests
  Rx.Observable.MergeTest.tests
  Rx.Observable.TimeoutTest.tests
