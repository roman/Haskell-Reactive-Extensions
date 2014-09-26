module Main where

import Criterion (bgroup, bench, nf, nfIO)
import Criterion.Main (defaultMain)

import Control.Monad (replicateM)
import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (async, wait)

import Data.List (foldl')
import qualified Rx.Observable as Rx
import qualified Rx.Subject as Rx

main :: IO ()
main = defaultMain [
    bgroup "foldLeft" [
        bench "foldl'" $ nf (foldl' (+) 0) inputList
      , bench "Rx.foldLeft" $ nfIO normalFoldLeft
      , bench "Rx.foldLeft with contention (10 threads)"
          $ nfIO (highContentionFoldLeft 10)
      , bench "Rx.foldLeft with contention (100 threads)"
          $ nfIO (highContentionFoldLeft 100)
      , bench "Rx.foldLeft with contention (1000 threads)"
          $ nfIO (highContentionFoldLeft 1000)
      ]]
  where
    inputList :: [Int]
    inputList = replicate 1000000 1

    normalFoldLeft =
      Rx.toMaybe
        (Rx.foldLeft (+) 0
          $ Rx.fromList Rx.newThread inputList)

    highContentionFoldLeft workerCount = do
      subject <- Rx.newPublishSubject
      let worker      = async $ threadDelay 10000 >> mapM_ (Rx.onNext subject) input
          input       = replicate (1000000 `div` workerCount) (1 :: Int)

      _ <- async $ do
        replicateM workerCount worker >>= mapM_ wait
        Rx.onCompleted subject

      Rx.toMaybe
        (Rx.foldLeft (+) 0
          $ Rx.toAsyncObservable subject)
