module Rx.Observable.DoTest where

import Data.IORef (newIORef, readIORef, atomicModifyIORef')
import Control.Exception (fromException, ErrorCall(..))
import qualified Rx.Observable as Rx

import Test.HUnit
import Test.Hspec

tests :: Spec
tests =
  describe "Rx.Observable.doAction" $ do
    describe "when action raises an error" $
      it "calls onError statement" $ do
        let source =
              Rx.doAction (\v -> if v < (5 :: Int)
                                   then return ()
                                   else error "value greater than 5")
              $  Rx.fromList Rx.newThread [1..10]

        eResult <- Rx.toList source
        case eResult of
          Right _  -> assertFailure "Expected source to fail but didn't"
          Left (_, err) ->
            maybe (assertFailure "Didn't receive specific failure")
                  (assertEqual "Didn't receive specific failure"
                               (ErrorCall "value greater than 5"))
                  (fromException err)

    describe "when action doesn't raise an error" $ do
      it "performs side effect per element" $ do
        var <- newIORef []
        let source =
              Rx.doAction (\v -> atomicModifyIORef' var (\acc -> (v : acc, ())))
              $ Rx.fromList Rx.newThread ([1..10] :: [Int])

        eResult <- Rx.toList source
        case eResult of
          Left err -> assertFailure $ "Received unexpected error: " ++ show err
          Right _ -> do
            acc <- readIORef var
            assertEqual "side-effects didn't happen"
                        [1..10]
                        (reverse acc)
