module Rx.Observable.MapReduce where

import Control.Concurrent (myThreadId)
import qualified Rx.Observable.List as Observable
import Rx.Scheduler (newThread)
import Data.Monoid (Sum(..))

import Control.Concurrent.Async (async, cancel, link2)
import Control.Concurrent.STM (atomically)
import Control.Concurrent.STM.TBChan (newTBChanIO, writeTBChan, readTBChan)

import Control.Monad (forever, replicateM, sequence)

import Data.Monoid (Monoid(..))

import Rx.Disposable (toDisposable, createDisposable, newCompositeDisposable
                     , newSingleAssignmentDisposable, dispose)
import qualified Rx.Disposable as Disposable

import Rx.Scheduler (Async)
import Rx.Observable.Types
import qualified Rx.Observable.Fold as Observable

type NumberOfThreads = Int

mapConcurrentlyM
  :: IObservable source
  => NumberOfThreads
  -> (a -> IO b)
  -> source Async a
  -> Observable Async b
mapConcurrentlyM nSize mapFn source = Observable $ \observer -> do
    disposable <- newCompositeDisposable
    subDisposable <- newSingleAssignmentDisposable
    inputChan <- newTBChanIO nSize

    workers@(w:_) <-
      replicateM nSize
        $ async (processEntryFromWorker observer inputChan)
    linkWorkers workers



    workersDisposable <- createDisposable $ cancel w
    innerSubDisposable <-
      subscribe source (atomically . writeTBChan inputChan)
                       (\err -> do
                           dispose subDisposable
                           dispose workersDisposable
                           onError observer err)
                       (do dispose workersDisposable
                           onCompleted observer)

    Disposable.set innerSubDisposable subDisposable
    Disposable.append subDisposable disposable
    Disposable.append workersDisposable disposable
    return $ toDisposable disposable
  where
    linkWorkers workers = sequence $ zipWith link2 workers (tail workers)
    processEntryFromWorker observer inputChan = forever $ do
      entry <- atomically $ readTBChan inputChan
      mapFn entry >>= onNext observer

mapReduceM
  :: (IObservable source, Monoid b)
  => NumberOfThreads
  -> (a -> IO b)
  -> source Async a
  -> Observable Async b
mapReduceM nSize mapFn source =
  Observable.foldMap id
    $ mapConcurrentlyM nSize mapFn source

mapReduce
  :: (IObservable source, Monoid b)
  => NumberOfThreads
  -> (a -> b)
  -> source Async a
  -> Observable Async b
mapReduce nSize mapFn =
  mapReduceM nSize (return . mapFn)


-- example :: IO ()
-- example = do
--     disposable_ <-
--       subscribeOnNext
--         (mapReduceM 2 mapFn $ Observable.fromList newThread [1..100000])
--         (\result -> putStrLn $ "Result is: " ++ show (result :: Sum Integer))
--     return ()
--   where
--     mapFn a = do
--       -- myThreadId >>= print
--       return $ Sum a
