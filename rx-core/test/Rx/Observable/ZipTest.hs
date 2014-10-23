module Rx.Observable.ZipTest (tests) where

import Control.Concurrent (threadDelay)

import Rx.Disposable (emptyDisposable)
import Rx.Scheduler (newThread, schedule)
import qualified Rx.Observable as Rx

import Test.HUnit (assertEqual, assertFailure)
import Test.Hspec (Spec, describe, it)


tests :: Spec
tests =
  describe "Rx.Observable.zipWith" $ do
    it "is thread safe" $ do
      let size = 1000000 :: Int
          input = replicate size (1 :: Int)
          (as, bs) = splitAt (size `div` 2) input

      let ob1 = Rx.Observable $ \observer -> do
            schedule newThread $ do
              putStrLn "STARTING 1"
              mapM_ (Rx.onNext observer) as
              Rx.onCompleted observer

          ob2 = Rx.Observable $ \observer -> do
            schedule newThread $ do
              putStrLn "STARTING 2"
              mapM_ (Rx.onNext observer) bs
              Rx.onCompleted observer

          source =
            Rx.foldLeft (+) 0
              $ Rx.doOnError (\e -> putStrLn $ "ON ERROR zip: " ++ show e)
              $ Rx.zipWith (+) (Rx.doOnError (const $ putStrLn "ON ERROR ob1")
                                 $ Rx.doOnCompleted (putStrLn "COMPLETED ob1") ob1)
                               (Rx.doOnError (const $ putStrLn "ON ERROR ob2")
                                 $ Rx.doOnCompleted (putStrLn "COMPLETED ob2") ob2)


      mResult <- Rx.toEither source
      case mResult of
        Right result ->
          assertEqual "should work correctly"
                      size
                      result
        Left err ->
          assertFailure $ "Rx failed on test: " ++ show err
