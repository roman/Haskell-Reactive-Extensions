module Rx.Subject.PublishSubjectTest (tests) where

import Control.Exception (ErrorCall (..), Exception (..), SomeException (..))

import Control.Concurrent.Async (async, wait)
import Control.Monad (replicateM_, void, when)

import qualified Rx.Observable as Rx
import qualified Rx.Subject    as Rx (newPublishSubject)

import Test.HUnit
import Test.Hspec

assertError :: Exception e => String -> SomeException -> (e -> IO ()) -> IO ()
assertError errMsg err assertion = do
  case fromException err of
    Just err' -> assertion err'
    Nothing   -> assertFailure errMsg

tests :: Spec
tests =
  describe "Rx.Subject.PublishSubject" $
    describe "on subscription failure" $
      it "doesn't kill other subscriptions" $ do
        subject <- Rx.newPublishSubject
        let count = 10
            errMsg =  "I want to see the world burn"
            source0 =
              Rx.foldLeft (+) 0
               $ Rx.toAsyncObservable subject

            source1 =
              Rx.doAction
               (const $ error errMsg)
               $ source0

        resultAsync <- async $ do
          result0 <- Rx.toEither source0
          result1 <- Rx.toEither source1
          return (result0, result1)

        replicateM_ count $ Rx.onNext subject (1 :: Int)
        Rx.onCompleted subject

        result <- wait resultAsync

        case result of
          (Right n, Left err) -> do
            assertEqual "other subscriber is affected by error" count n
            assertError "expecting error call" err $ \(ErrorCall errMsg) ->
              assertEqual "" errMsg errMsg

          failure ->
            assertFailure $ "Expected Right and Left, got: " ++ show failure
