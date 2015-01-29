module Rx.Observable.FilterTest where

import qualified Rx.Observable as Rx

import Test.Hspec
import Test.HUnit

tests :: Spec
tests = do
  describe "Rx.Observable.filterM" $ do
    it "filters elements that return True on predicate function" $ do
      let source =
            Rx.filterM (\v -> return $ v `mod` 2 == 0)
              $ Rx.fromList Rx.currentThread [1..10]
      result <- Rx.toList source
      case result of
        Right val -> do
          assertEqual
            "filter didn't work, should only have pair numbers"
            (reverse [2,4,6,8,10] :: [Int])
            val
        Left err ->
          assertFailure $ "received unexpected error: " ++ show err

  describe "Rx.Observable.filter" $
    it "filters elements that return True on predicate function" $ do
      let source =
            Rx.filter (\v -> v `mod` 2 == 0)
              $ Rx.fromList Rx.currentThread [1..10]
      result <- Rx.toList source
      case result of
        Right val -> do
          assertEqual
            "filter didn't work, should only have pair numbers"
            (reverse [2,4,6,8,10] :: [Int])
            val
        Left err ->
          assertFailure $ "received unexpected error: " ++ show err
