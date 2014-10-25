module Rx.Observable.ZipTest (tests) where

import Rx.Scheduler (newThread, schedule)
import qualified Rx.Observable as Rx

import Test.HUnit (assertEqual, assertFailure)
import Test.Hspec (Spec, describe, it)

tests :: Spec
tests =
  describe "Rx.Observable.zipWith" $
    it "is thread safe" $ do
      let size = 1000000 :: Int
          input = replicate size (1 :: Int)
          (as, bs) = splitAt (size `div` 2) input

      let ob1 = Rx.Observable $ \observer ->
            schedule newThread $ do
              mapM_ (Rx.onNext observer) as
              Rx.onCompleted observer

          ob2 = Rx.Observable $ \observer ->
            schedule newThread $ do
              mapM_ (Rx.onNext observer) bs
              Rx.onCompleted observer

          source =
            Rx.foldLeft (+) 0
              $ Rx.zipWith (+) ob1 ob2


      eResult <- Rx.toEither source
      case eResult of
        Right result ->
          assertEqual "should work correctly" size result
        Left err ->
          assertFailure $ "Rx failed on test: " ++ show err
