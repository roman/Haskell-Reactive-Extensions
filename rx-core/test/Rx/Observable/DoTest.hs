module Rx.Observable.DoTest where

import Data.IORef (atomicModifyIORef', newIORef, readIORef)
import qualified Rx.Observable as Rx

import Test.HUnit
import Test.Hspec

tests :: Spec
tests = do
  describe "Rx.Observable.doOnCompleted" $
    it "does a side effect when observable is completed" $ do
      var <- newIORef (0 :: Int)
      let source =
            Rx.doOnCompleted (atomicModifyIORef' var (\v -> (v + 1, ())))
            $ Rx.fromList Rx.currentThread ([1..10] :: [Int])

      eResult <- Rx.toList source
      case eResult of
        Left err ->
          assertFailure $ "received unexpected error: " ++ show err
        Right _ -> do
          result <- readIORef var
          assertEqual "doOnCompleted wasn't called exactly once"
                      (1 :: Int)
                      result


  describe "Rx.Observable.doOnError" $
    it "does a side effect when an error happens" $ do
      var <- newIORef (0 :: Int)
      let source =
            Rx.doOnError (const $ atomicModifyIORef' var (\v -> (v + 1, ())))
              $ do v <- Rx.fromList Rx.newThread ([1..10] :: [Int])
                   if (v > 5) then fail "value greater than 5" else return v

      eResult <- Rx.toList source
      case eResult of
        Right _   -> assertFailure "Didn't receive expected error"
        Left _ -> do
          result <- readIORef var
          assertEqual "doOnError wasn't called exactly once"
                      1
                      result

  describe "Rx.Observable.doAction" $
    it "performs side effect per element" $ do
      var <- newIORef []
      let source =
            Rx.doAction (\v -> atomicModifyIORef' var (\acc -> (v : acc, ())))
            $ Rx.fromList Rx.newThread ([1..10] :: [Int])

      eResult <- Rx.toList source
      case eResult of
        Left err ->
         assertFailure $
          "Received unexpected error: " ++ show err
        Right _ -> do
          acc <- readIORef var
          assertEqual "side-effects didn't happen"
                      [1..10]
                      (reverse acc)
