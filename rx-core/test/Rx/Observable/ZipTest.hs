module Rx.Observable.ZipTest (tests) where

import Rx.Scheduler (newThread, schedule)
import qualified Rx.Observable as Rx

import Test.HUnit (assertEqual, assertFailure)
import Test.Hspec (Spec, describe, it)


tests :: Spec
tests =
  describe "Rx.Observable.zipWith" $ do
    it "is thread safe" $ do
      let input = replicate 1000000 (1 :: Int)
          (as, bs) = splitAt 500000 input

      let ob1 = Rx.Observable $ \observer -> do
            schedule newThread $ do
              mapM_ (Rx.onNext observer) as
              Rx.onCompleted observer

          ob2 = Rx.Observable $ \observer -> do
            schedule newThread $ do
              mapM_ (Rx.onNext observer) bs
              Rx.onCompleted observer

          source = Rx.foldLeft (+) 0 $ Rx.zipWith (+) ob1 ob2


      mResult <- Rx.toMaybe source
      case mResult of
        Just result ->
          assertEqual "should work correctly"
                      (1000000 :: Int)
                      result
        Nothing ->
          assertFailure "Rx failed on test"
