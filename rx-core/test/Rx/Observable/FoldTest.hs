module Rx.Observable.FoldTest (tests) where

import Control.Concurrent       (threadDelay)
import Control.Concurrent.Async (async, wait)
import Control.Monad            (void)

import qualified Rx.Observable as Rx
import qualified Rx.Subject    as Rx

import Test.Hspec (Spec, describe, it)
import Test.HUnit (assertEqual, assertFailure)


tests :: Spec
tests =
  describe "foldLeft" $ do
    it "is thread safe" $ do
      let input = replicate 1000000 (1 :: Int)
          (as, bs) = splitAt 500000 input

      subject <- Rx.newPublishSubject
      a1 <- async $ do
        threadDelay 100
        mapM_ (Rx.onNext subject) as

      b1 <- async $ do
        threadDelay 100
        mapM_ (Rx.onNext subject) bs

      void $ async $ do
        mapM_ wait [a1, b1]
        Rx.onCompleted subject

      let source =
            Rx.foldLeft (+) 0
              $ Rx.toAsyncObservable subject

      mResult <- Rx.toMaybe source
      case mResult of
        Just result ->
          assertEqual "should be the same as foldl'"
                      (1000000 :: Int)
                      result
        Nothing ->
          assertFailure "Rx failed on test"

    it "behaves like a normal fold" $ do
      let input = replicate 1000000 1 :: [Int]
      mResult <- Rx.toMaybe (Rx.foldLeft (+) 0 $
                              Rx.fromList Rx.newThread input)
      case mResult of
        Just result ->
          assertEqual "should be the same as foldl'"
                      (1000000 :: Int)
                      result
        Nothing ->
          assertFailure "Rx failed on test"
