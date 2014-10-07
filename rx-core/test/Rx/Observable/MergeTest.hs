module Rx.Observable.MergeTest (tests) where

import Test.HUnit
import Test.Hspec

import Control.Concurrent.Async (async, wait)
import Control.Monad (forM_, replicateM, replicateM_)

import qualified Rx.Observable as Rx
import qualified Rx.Subject    as Rx

tests :: Spec
tests =
  describe "Rx.Observable.Merge" $
    describe "merge" $
      it "completes after all inner Observables are completed" $ do
        let innerSubjectCount = 10
        subjects@(firstSubject:subjects1) <-
          replicateM innerSubjectCount Rx.newPublishSubject

        sourceSubject  <- Rx.newPublishSubject

        let source = Rx.foldLeft (+) 0
                       $ Rx.merge
                       $ Rx.toAsyncObservable sourceSubject


        aResult <- async $ Rx.toMaybe source


        forM_  subjects $ \subject -> do
          Rx.onNext sourceSubject $ Rx.toAsyncObservable subject
          replicateM_ 100 $ Rx.onNext subject (1 :: Int)

        Rx.onCompleted sourceSubject

        -- If merge doesn't wait for inner observables
        -- this numbers should not be in the total count
        mapM_ Rx.onCompleted subjects1
        replicateM_ 50 $ Rx.onNext firstSubject 1
        mapM_ Rx.onCompleted subjects

        mResult <- wait aResult
        case mResult of
          Just result ->
            assertEqual "should be the same as folding"
                        (innerSubjectCount * 100 + 50)
                        result
          Nothing ->
            assertFailure "Rx failed when it shouldn't have"
