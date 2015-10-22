module Rx.Observable.ErrorTest where

import Control.Concurrent.Async (async, wait)
import Control.Exception (ErrorCall (..), toException)

import qualified Rx.Observable as Rx
import qualified Rx.Subject as Rx


import Test.HUnit
import Test.Hspec

tests :: Spec
tests = do
  describe "Rx.Observable.onErrorResumeNext" $ do
    it "rescues an error with other observable" $ do
      let
        source0 = (fail "this is an error") :: Rx.Observable Rx.Async Int
        source1 = (return 999) :: Rx.Observable Rx.Async Int
        source  = (Rx.onErrorResumeNext source1 source0)

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

  describe "Rx.Observable.retry" $
    it "retries errors n times" $ do
      subject <- Rx.newPublishSubject
      let
        source =
          Rx.foldLeft (+) (0 :: Int)
          $ Rx.retry 3
          $ Rx.toAsyncObservable subject


      resultAsync <- async $ Rx.toEither source

      Rx.onNext subject 10
      Rx.onError subject (toException $ ErrorCall "error 1")
      Rx.onNext subject 20
      Rx.onError subject (toException $ ErrorCall "error 2")
      Rx.onNext subject 30
      Rx.onError subject (toException $ ErrorCall "error 3")
      Rx.onCompleted subject

      result <- wait resultAsync

      case result of
        Right val ->
          assertEqual "didn't receive expected value" (10 + 20 + 30) val
        Left err -> assertFailure $ "expecting to not fail but did: " ++ show err

  describe "Rx.Observable.catch" $
    it "rescues observable from error" $ do
      let
        input = 10 :: Int
        source0 = fail "this is an error" :: Rx.Observable Rx.Async Int
        source =
            Rx.catch (\(ErrorCall _) -> return input) source0

      result <- Rx.toEither source
      case result of
        Right val -> assertEqual "catch didn't work" input val
        Left err -> assertFailure $ "expecting to not fail but did: " ++ show err
