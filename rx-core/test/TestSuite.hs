module Main where

import Test.Hspec (hspec)

import qualified Rx.Observable.FoldTest
import qualified Rx.Observable.MergeTest
import qualified Rx.Observable.TimeoutTest
import qualified Rx.Subject.PublishSubjectTest

main :: IO ()
main = hspec $ do
  Rx.Observable.FoldTest.tests
  Rx.Observable.MergeTest.tests
  Rx.Observable.TimeoutTest.tests
  Rx.Subject.PublishSubjectTest.tests
