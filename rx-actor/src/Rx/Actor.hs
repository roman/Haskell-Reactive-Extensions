{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE ScopedTypeVariables #-}
-- module Rx.Actor where
module Main where

import Control.Exception (ErrorCall(..), AssertionFailed, finally, fromException, assert)

import Data.Typeable (Typeable)

import Control.Monad (void)
import Control.Monad.Trans (liftIO)

import Control.Concurrent.Async (async)

import Rx.Actor.ActorBuilder
import Rx.Actor.Supervisor.SupervisorBuilder
import Rx.Actor.Supervisor
import Rx.Actor.Types

import Rx.Observable (onNext)
import Rx.Subject (newPublishSubject)

import Tiempo (seconds)
import Tiempo.Concurrent (threadDelay)

newtype PrintNumber = PrintNumber () deriving (Typeable, Show)
newtype CallFail = CallFail () deriving (Typeable, Show)
newtype AssertFail = AssertFail () deriving (Typeable, Show)

numberPrinter :: ActorDef ()
numberPrinter = defActor $ do
    actorKey "printer"
    startDelay (seconds 5)

    preStart $ do
      putStrLn "preStart printer"
      return $ InitOk ()

    postStop $ do
      putStrLn "postStop printer"

    preRestart $ \() err _ev -> do
      putStrLn $ "preRestart => " ++ show err

    postRestart $ \() err _ev -> do
      putStrLn $ "postRestart: recovering from failure"
      return $ InitOk ()

    desc "Print integers on terminal"
    receive printNumber
  where
    printNumber :: Int -> ActorM () ()
    printNumber n = liftIO $ putStrLn $ "=> " ++ show n

numberAccumulator :: ActorDef Int
numberAccumulator = defActor $ do
    actorKey "accum"

    onError $ \(err :: ErrorCall) _st -> return Restart
    onError $ \(err :: ErrorCall) _st -> return Restart
    onError $ \(err :: AssertionFailed) _st -> do
      putStrLn "Resuming assertion failed error"
      return $ Resume

    preStart $ do
      putStrLn "preStart accum"
      return $ InitOk 0

    postStop $ do
      putStrLn "postStop accum"

    preRestart $ \_ err _ev -> do
      putStrLn $ "preRestart accum => " ++ show err

    postRestart $ \prevCount err _ev -> do
      putStrLn $ "postRestart accum: recovering from failure"
      putStrLn $ "count was: " ++ show prevCount
      return $ InitOk 0

    desc "sums to a total the given integer"
    receive accumulateNumber

    desc "Prints number on terminal"
    receive printNumber

    desc "Fails the actor via ErrorCall"
    receive callError

    desc "Fails the actor via AssertionFailed"
    receive assertError
  where
    accumulateNumber :: Int -> ActorM Int ()
    accumulateNumber n = modifyState (+n)

    printNumber :: PrintNumber -> ActorM Int ()
    printNumber _ = do
      n <- getState
      emit (CallFail ())
      liftIO $ putStrLn $ "acc => " ++ show n

    callError :: CallFail -> ActorM Int ()
    callError = error "I want to fail"

    assertError :: AssertFail -> ActorM Int ()
    assertError = assert False $ undefined


mySystem :: SupervisorDef
mySystem = defSupervisor $ do
  strategy OneForOne
  backoff $ \attempt -> seconds $ 2 ^ attempt
  addChild numberPrinter
  addChild numberAccumulator

main :: IO ()
main = do
  evBus <- newPublishSubject
  print $ length (_supervisorDefChildren mySystem)
  sup <- startSupervisorWithEventBus evBus mySystem
  void . async $ do
    threadDelay $ seconds 3
    emitEvent sup (1 :: Int)
    emitEvent sup (2 :: Int)
    emitEvent sup (AssertFail ())
    onNext evBus $ toGenericEvent (3 :: Int)
    emitEvent sup (PrintNumber ())
    -- emitEvent sup (PrintNumber ())
    -- emitEvent sup (PrintNumber ())
    -- emitEvent sup (PrintNumber ())
    -- emitEvent sup (PrintNumber ())

  joinSupervisorThread sup `finally` stopSupervisor sup
