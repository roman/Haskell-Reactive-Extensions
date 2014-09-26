module Rx.Observable.MergeTest (tests) where

import Test.HUnit
import Test.Hspec

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (async, wait)

import qualified Rx.Observable as Rx
import qualified Rx.Subject    as Rx

tests :: Spec
tests =
  describe "Rx.Observable.Merge" $
    describe "merge" $
      it "completes after all inner Observables are completed" $ do
        outerSubject  <- Rx.newPublishSubject
        innerSubject0 <- Rx.newPublishSubject
        innerSubject1 <- Rx.newPublishSubject
        let source = Rx.foldLeft (+) 0
                       $ Rx.merge
                       $ Rx.toAsyncObservable outerSubject
            emit subject =
              Rx.onNext outerSubject $ Rx.toAsyncObservable subject
            work subject =
              mapM_ (Rx.onNext subject)

        aResult <- async $ Rx.toMaybe source
        threadDelay 100

        emit innerSubject0
        work innerSubject0 $ replicate 100 (1 :: Int)
        emit innerSubject1

        Rx.onCompleted outerSubject

        -- If merge doesn't wait for inner observables
        -- this numbers should not be in the total count
        work innerSubject1 $ replicate 50 (1 :: Int)
        Rx.onCompleted innerSubject1

        work innerSubject0 $ replicate 1000 (1 :: Int)
        Rx.onCompleted innerSubject0


        mResult <- wait aResult
        case mResult of
          Just result ->
            assertEqual "should be the same as folding"
                        1150
                        result
          Nothing ->
            assertFailure "Rx failed when it shouldn't have"
