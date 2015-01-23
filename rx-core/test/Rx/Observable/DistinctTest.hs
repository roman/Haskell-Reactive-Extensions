module Rx.Observable.DistinctTest where

import qualified Rx.Observable as Rx

import Test.HUnit
import Test.Hspec

tests :: Spec
tests = do
  describe "Rx.Observable.distinct" $
    it "doesn't emit an item more than once" $ do
      let source =
            Rx.distinct
              $ Rx.fromList Rx.newThread (concat [[a,a] | a <- [1..10]])
      eResult <- Rx.toList source
      case eResult of
        Right result -> do
          assertEqual "didn't remove repeated values" [1..10 :: Int] (reverse result)
        Left err -> do
          assertFailure $ "source observable failed with: " ++ show err

  describe "Rx.Observable.distinctUntilChanged" $
    it "doesn't emit notifications if they are the same as last one" $ do
      let source =
            Rx.distinctUntilChanged
              $ Rx.fromList Rx.newThread (replicate 100 1)
      eResult <- Rx.toList source
      case eResult of
        Right result ->
          assertEqual "didn't remove repeated values" [1 :: Int] result
        Left err ->
          assertFailure $ "source observable failed with: " ++ show err
