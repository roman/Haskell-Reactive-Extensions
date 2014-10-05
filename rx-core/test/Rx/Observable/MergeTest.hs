module Rx.Observable.MergeTest (tests) where

import Test.HUnit
import Test.Hspec

import Control.Concurrent (threadDelay, yield)
import Control.Concurrent.Async (async, wait)
import Control.Monad (replicateM_)

import qualified Rx.Observable as Rx
import qualified Rx.Subject    as Rx

tests :: Spec
tests =
  describe "Rx.Observable.Merge" $
    describe "merge" $
      it "completes after all inner Observables are completed" $ do
        sourceSubject  <- Rx.newPublishSubject
        innerSubject0  <- Rx.newPublishSubject
        innerSubject1  <- Rx.newPublishSubject
        let source = Rx.foldLeft (+) 0
                       $ Rx.merge
                       $ Rx.toAsyncObservable sourceSubject


        aResult <- async $ Rx.toMaybe source

        Rx.onNext sourceSubject $ Rx.toAsyncObservable innerSubject0
        replicateM_ 100  $ Rx.onNext innerSubject0 (1 :: Int)
        Rx.onNext sourceSubject $ Rx.toAsyncObservable innerSubject1
        Rx.onCompleted sourceSubject

        -- If merge doesn't wait for inner observables
        -- this numbers should not be in the total count
        replicateM_ 50   $ Rx.onNext innerSubject1 (1 :: Int)
        replicateM_ 1000 $ Rx.onNext innerSubject0 1

        Rx.onCompleted innerSubject1
        Rx.onCompleted innerSubject0

        mResult <- wait aResult
        case mResult of
          Just result ->
            assertEqual "should be the same as folding"
                        1150
                        result
          Nothing ->
            assertFailure "Rx failed when it shouldn't have"
