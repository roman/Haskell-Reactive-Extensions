module Main where

import Test.Hspec (hspec)

import qualified Rx.Observable.DistinctTest
import qualified Rx.Observable.DoTest
import qualified Rx.Observable.ErrorTest
import qualified Rx.Observable.FilterTest
import qualified Rx.Observable.FirstTest
import qualified Rx.Observable.FoldTest
import qualified Rx.Observable.MergeTest
import qualified Rx.Observable.TimeoutTest
import qualified Rx.Observable.ZipTest
import qualified Rx.Subject.PublishSubjectTest

main :: IO ()
main = hspec $ do
  Rx.Observable.DistinctTest.tests
  Rx.Observable.DoTest.tests
  Rx.Observable.ErrorTest.tests
  Rx.Observable.FoldTest.tests
  Rx.Observable.FilterTest.tests
  Rx.Observable.FirstTest.tests
  Rx.Observable.MergeTest.tests
  Rx.Observable.TimeoutTest.tests
  Rx.Observable.ZipTest.tests
  Rx.Subject.PublishSubjectTest.tests
