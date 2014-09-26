module Rx.Observable.TimeoutTest (tests) where

import Test.Hspec (Spec, describe, it)
import Test.HUnit (assertBool, assertFailure)
import Tiempo     (microSeconds)

import qualified Rx.Observable as Rx

tests :: Spec
tests =
  describe "Rx.Observable.Timeout" $ do

    describe "timeout" $
      it "fails after a period of time" $ do
        let source = Rx.foldLeft (+) 0
                       $ Rx.timeout (microSeconds 0)
                       $ Rx.doAction print
                       $ Rx.fromList Rx.newThread ([1..] :: [Int])
        mResult <- Rx.toMaybe source
        case mResult of
          Nothing -> assertBool "" True
          Just _  ->
            assertFailure "Expected Observable to fail after period but didn't"

    describe "timeoutWith" $
      it "doesn't fail when 'completeOnTimeout' is used" $ do
        let source = Rx.foldLeft (+) 0
                       $ Rx.timeoutWith (Rx.completeOnTimeout .
                                         Rx.timeoutDelay (microSeconds 0))
                       $ Rx.doAction print
                       $ Rx.fromList Rx.newThread ([1..] :: [Int])
        mResult <- Rx.toMaybe source
        case mResult of
          Nothing ->
            assertFailure "Expected Observable to complete after period but didn't"
          Just _  ->
            assertBool "" True
