module Rx.Subject.PublishSubjectTest (tests) where

import Control.Exception (ErrorCall (..), Exception (..), SomeException (..),
                          toException)

import Control.Concurrent (yield)
import Control.Concurrent.Async (async, wait)
import Control.Concurrent.STM (atomically, modifyTVar, newTVarIO, readTVar,
                               writeTVar)
import Control.Monad (replicateM_, void, when)

import qualified Rx.Observable as Rx
import qualified Rx.Subject    as Rx (Subject, newPublishSubject)

import Test.HUnit
import Test.Hspec

assertError :: Exception e => String -> SomeException -> (e -> IO ()) -> IO ()
assertError errMsg err assertion = do
  case fromException err of
    Just err' -> assertion err'
    Nothing   -> assertFailure errMsg

errorExample = ErrorCall "call 611"

tests :: Spec
tests =
  describe "Rx.Subject.PublishSubject" $ do
    describe "once an OnError notification is received" $ do
      it "doesn't send more OnNext notifications" $ do
        subject <- Rx.newPublishSubject

        resultVar    <- newTVarIO []
        errorVar     <- newTVarIO Nothing
        completedVar <- newTVarIO False

        _disposable <-
          Rx.subscribe (Rx.toAsyncObservable subject)
                       (\msg -> atomically $ modifyTVar resultVar (msg:))
                       (atomically . writeTVar errorVar . Just)
                       (atomically $ writeTVar completedVar True)

        Rx.onNext subject "a"
        Rx.onNext subject "b"
        Rx.onError subject $ toException errorExample
        Rx.onNext subject "c"
        Rx.onNext subject "d"
        Rx.onCompleted subject

        yield
        result <- atomically $ readTVar resultVar
        assertEqual "received events after OnError"
                    ["b", "a"]
                    result

        merrRes <- atomically $ readTVar errorVar
        let errResult =
              maybe Nothing Just $ do
                err <- merrRes
                fromException err

        assertEqual "didn't receive OnError notification"
                    (Just errorExample)
                    errResult

        completed <- atomically $ readTVar completedVar
        assertBool "received OnCompleted when shouldn't have" (not completed)


      it "sends OnError immediately on new subscribers" $ do
        let err = ErrorCall "call 911"
        subject <- Rx.newPublishSubject
        Rx.onError subject $ toException errorExample
        yield
        result <- Rx.toList (Rx.toAsyncObservable subject)
        case result of
         Left ([], err') -> assertEqual "got different exception"
                                        (Just errorExample)
                                        (fromException err')
         _ -> assertFailure "Didn't receive a Left value"


    describe "once an OnCompleted notification is received" $ do

      it "doesn't send more OnNext notifications" $ do
        subject <- Rx.newPublishSubject

        resultVar    <- newTVarIO []
        errorVar     <- newTVarIO Nothing
        completedVar <- newTVarIO False

        _disposable <-
          Rx.subscribe (Rx.toAsyncObservable subject)
                       (\msg -> atomically $ modifyTVar resultVar (msg:))
                       (atomically . writeTVar errorVar . Just)
                       (atomically $ writeTVar completedVar True)

        Rx.onNext subject "a"
        Rx.onNext subject "b"
        Rx.onCompleted subject
        Rx.onNext subject "c"
        Rx.onNext subject "d"
        Rx.onError subject $ toException errorExample

        yield
        result <- atomically $ readTVar resultVar
        assertEqual "received events after OnError"
                    ["b", "a"]
                    result

        merrRes <- atomically $ readTVar errorVar
        let errResult =
              maybe Nothing Just $ do
                err <- merrRes
                fromException err

        assertEqual "received OnError notification"
                    (Nothing :: Maybe ErrorCall)
                    errResult

        completed <- atomically $ readTVar completedVar
        assertBool "didn't receive OnCompleted notification" completed

        
      it "sends OnCompleted immediately on new subscribers" $ do
        subject <- Rx.newPublishSubject :: IO (Rx.Subject Int)
        Rx.onCompleted subject
        yield
        result <- Rx.toList (Rx.toAsyncObservable subject)
        case result of
          Right evs ->
            assertEqual "received notifications when shouldn't" [] evs
          Left _ ->
            assertFailure "Received failure when not expecting it"

        

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
