module Rx.Observable.MapReduce where

import Control.Concurrent (myThreadId)
import qualified Rx.Observable.List as Observable
import Rx.Scheduler (currentThread)
import Data.Monoid (Sum(..))

import Control.Concurrent.Async (async, cancel, link2)
import Control.Concurrent.STM (atomically)
import Control.Concurrent.STM.TBChan (newTBChanIO, writeTBChan, readTBChan)

import Control.Monad (forever, replicateM, sequence)

import Data.Monoid (Monoid(..))

import Rx.Disposable (toDisposable, createDisposable, newCompositeDisposable, dispose)
import qualified Rx.Disposable as Disposable

import Rx.Scheduler (Async, Sync)
import Rx.Observable.Types
import qualified Rx.Observable.Fold as Observable


type NumberOfThreads = Int

mapConcurrentlyM
  :: IObservable source
  => NumberOfThreads
  -> (a -> IO b)
  -> source s a
  -> Observable s b
mapConcurrentlyM nSize mapFn source = Observable $ \observer -> do
    inputChan <- newTBChanIO nSize
    workers@(w:_) <- replicateM nSize $ async (processEntry observer inputChan)
    linkWorkers workers

    disposable <- newCompositeDisposable
    workersDisposable <- createDisposable $ do
      putStrLn "Disposing worker"
      cancel w

    subDisposable <- subscribe source
                       (atomically . writeTBChan inputChan)
                       (\err -> do
                           print err
                           dispose workersDisposable
                           onError observer err)
                       (do putStrLn "ADONE"
                           dispose workersDisposable
                           onCompleted observer)

    Disposable.append subDisposable disposable
    Disposable.append workersDisposable disposable
    return $ toDisposable disposable
  where
    linkWorkers workers = sequence $ zipWith link2 workers (tail workers)
    processEntry observer inputChan = forever $ do
      a <- atomically $ readTBChan inputChan
      mapFn a >>= onNext observer

mapReduceM
  :: (IObservable source, Monoid b)
  => NumberOfThreads
  -> (a -> IO b)
  -> source s a
  -> Observable s b
mapReduceM nSize mapFn source =
  Observable.foldLeft (\acc a -> return $ acc `mappend` a) mempty $
    mapConcurrentlyM nSize mapFn source


-- example :: IO ()
-- example = do
--     disposable_ <-
--       subscribeOnNext
--         (mapReduceM 2 mapFn $ Observable.fromList currentThread [1..100000])
--         (\result -> putStrLn $ "Result is: " ++ show (result :: Sum Integer))
--     putStrLn "Hello OSEA"
--     return ()
--   where
--     mapFn a = do
--       -- myThreadId >>= print
--       return $ Sum a
