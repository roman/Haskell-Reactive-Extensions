module Main where

import Criterion (bench, bgroup, nf, nfIO)
import Criterion.Main (defaultMain)

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (async, wait)
import Control.Monad (replicateM)

import Data.List (foldl')
import qualified Rx.Observable as Rx
import qualified Rx.Subject    as Rx

main :: IO ()
main = defaultMain [
      bench "foldl'" $ nf (foldl' (+) 0) inputList
    , bgroup "Rx.foldLeft" [
        bench "withtout contention" $ nfIO normalFoldLeft
      , bench "with contention (10 threads)"
          $ nfIO (highContentionFoldLeft 10)
      , bench "with contention (100 threads)"
          $ nfIO (highContentionFoldLeft 100)
      , bench "with contention (1000 threads)"
          $ nfIO (highContentionFoldLeft 1000)
      , bench "with contention (100000 threads)"
          $ nfIO (highContentionFoldLeft 1000) ]
    , bgroup "Rx.merge" [
        bench "with contention (10000 threads)"
          $ nfIO (highContentionMerge 10000)]
     ]
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

    highContentionMerge workerCount =
      let sources = replicate workerCount
                      $ Rx.fromList Rx.newThread (replicate 100 (1 :: Int))
          source = Rx.mergeList sources
      in Rx.toMaybe $ Rx.foldLeft (+) 0 source
