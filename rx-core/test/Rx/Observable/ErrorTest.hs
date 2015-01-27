module Rx.Observable.ErrorTest where

import Control.Concurrent (newEmptyMVar, putMVar, readMVar)
import Control.Exception (ErrorCall (..), toException)

import qualified Rx.Observable as Rx
import qualified Rx.Subject    as Rx


import Test.HUnit
import Test.Hspec

tests :: Spec
tests = do
  describe "Rx.Observable.onErrorResumeNext" $ do
    it "rescues an error with other observable" $ do
      let
        source0 = (fail "this is an error") :: Rx.Observable Rx.Async Int
        source1 = (return 999) :: Rx.Observable Rx.Async Int
        source = Rx.onErrorResumeNext source1 source0

      result <- Rx.toEither source
      case result of
        Right value ->
           assertEqual "didn't return correct value" 999 (value :: Int)
        Left err ->
          assertFailure $ "receiving error when not expecting it: " ++ show err

  describe "Rx.Observable.onErrorReturn" $
    it "rescues an error with other return value" $ do
      let
        source0 = fail "this is an error"
        source = Rx.onErrorReturn 999 (source0 :: Rx.Observable Rx.Async Int)

      result <- Rx.toEither source
      case result of
        Right value ->
           assertEqual "didn't return correct value" 999 (value :: Int)
        Left err ->
          assertFailure $ "receiving error when not expecting it: " ++ show err

  describe "Rx.Observable.catch" $
    it "rescues observable from error" $ do
      resultVar <- newEmptyMVar
      subject <- Rx.newSyncPublishSubject :: IO (Rx.Subject Int)
      let
        errMsg = "check catch"
        source =
            Rx.catch (\(ErrorCall msg) -> putMVar resultVar msg)
              $ Rx.toAsyncObservable subject

      _disposable <- Rx.subscribe source
                                 (const $ return ())
                                 (const $ return ())
                                 (return ())
      Rx.onNext subject 10
      Rx.onError subject (toException $ ErrorCall errMsg)
      Rx.onCompleted subject

      result <- readMVar resultVar
      assertEqual "catch didn't work" errMsg result
