module Rx.Observable.ConcatTest where

import           Test.Hspec
import           Test.HUnit

import           Control.Concurrent.Async (async, wait)
import           Control.Exception        (ErrorCall (..), SomeException (..),
                                           fromException)
import           Data.Maybe               (fromJust)

import qualified Rx.Observable            as Rx
import qualified Rx.Subject               as Rx (newPublishSubject)

tests :: Spec
tests =
  describe "Rx.Observable.Concat" $ do
    describe "concatList" $ do
      it "concatenates elements from different observables in order" $ do
        let obs = Rx.concatList [ Rx.fromList Rx.newThread [1..10]
                                , Rx.fromList Rx.newThread [11..20]
                                , Rx.fromList Rx.newThread [21..30] ]
        result <- Rx.toList (obs :: Rx.Observable Rx.Async Int)
        case result of
          Left err -> assertFailure (show err)
          Right out -> assertEqual "elements are not in order" (reverse [1..30]) out

    describe "concat" $ do
      it "concatanates async observables in order of subscription" $ do
        outerSource  <- Rx.newPublishSubject
        innerSource1 <- Rx.newPublishSubject
        innerSource2 <- Rx.newPublishSubject

        let sources   = Rx.toAsyncObservable outerSource
            obs1      = Rx.toAsyncObservable innerSource1
            obs2      = Rx.toAsyncObservable innerSource2
            resultObs = Rx.concat sources

        resultA <- async (Rx.toList resultObs)

        Rx.onNext outerSource (obs2 :: Rx.Observable Rx.Async Int)
        Rx.onNext outerSource (obs1 :: Rx.Observable Rx.Async Int)

        -- ignores this because it is not subscribed to obs1 yet
        -- (obs2 needs to be completed first)
        Rx.onNext innerSource1 (-1)
        Rx.onNext innerSource1 (-2)

        -- outer is completed, but won't be done until inner sources
        -- are completed
        Rx.onCompleted outerSource

        -- first elements emitted
        Rx.onNext innerSource2 1
        Rx.onNext innerSource2 2
        Rx.onNext innerSource2 3

        Rx.onCompleted innerSource2

        -- this elements are emitted because innerSource2 completed
        Rx.onNext innerSource1 11
        Rx.onNext innerSource1 12

        -- after this, the whole thing is completed
        Rx.onCompleted innerSource1

        result <- wait resultA
        case result of
          Left err -> assertFailure (show err)
          Right xs -> assertEqual "should be on the right order" (reverse [1,2,3,11,12]) xs

      it "handles error when outer source fails " $ do
        outerSource  <- Rx.newPublishSubject
        innerSource1 <- Rx.newPublishSubject
        innerSource2 <- Rx.newPublishSubject

        let sources   = Rx.toAsyncObservable outerSource
            obs1      = Rx.toAsyncObservable innerSource1
            obs2      = Rx.toAsyncObservable innerSource2
            resultObs = Rx.concat sources

        resultA <- async (Rx.toList resultObs)

        Rx.onNext outerSource (obs2 :: Rx.Observable Rx.Async Int)
        Rx.onNext outerSource (obs1 :: Rx.Observable Rx.Async Int)

        Rx.onNext innerSource2 123
        Rx.onError outerSource (SomeException (ErrorCall "foobar"))

        Rx.onNext innerSource2 456

        result <- wait resultA

        case result of
          Right _  -> assertFailure "expected failure, got valid response"
          Left (xs, err) -> do
            assertEqual "received elements before error" [123] xs
            assertEqual "received error" (ErrorCall "foobar") (fromJust $ fromException err)

      it "handles error on inner source" $ do
        outerSource  <- Rx.newPublishSubject
        innerSource1 <- Rx.newPublishSubject
        innerSource2 <- Rx.newPublishSubject

        let sources   = Rx.toAsyncObservable outerSource
            obs1      = Rx.toAsyncObservable innerSource1
            obs2      = Rx.toAsyncObservable innerSource2
            resultObs = Rx.concat sources

        resultA <- async (Rx.toList resultObs)

        Rx.onNext outerSource (obs2 :: Rx.Observable Rx.Async Int)
        Rx.onNext outerSource (obs1 :: Rx.Observable Rx.Async Int)

        Rx.onNext innerSource2 123
        Rx.onError innerSource2 (SomeException (ErrorCall "foobar"))

        Rx.onCompleted outerSource

        result <- wait resultA

        case result of
          Right _  -> assertFailure "expected failure, got valid response"
          Left (xs, err) -> do
            assertEqual "received elements before error" [123] xs
            assertEqual "received error" (ErrorCall "foobar") (fromJust $ fromException err)
