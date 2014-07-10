{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Rx.Actor where

import Control.Exception (finally, fromException, ErrorCall(..),)

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
newtype Fail = Fail () deriving (Typeable, Show)

numberPrinter :: ActorDef ()
numberPrinter = defActor $ do
    actorKey "printer"

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

    onError $ \err ->
      case fromException err of
        Just (ErrorCall _) -> Restart
        Nothing -> Resume

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

    desc "Fails the actor"
    receive failActor
  where
    accumulateNumber :: Int -> ActorM Int ()
    accumulateNumber n = modifyState (+n)

    printNumber :: PrintNumber -> ActorM Int ()
    printNumber _ = do
      n <- getState
      liftIO $ putStrLn $ "acc => " ++ show n
      emit (Fail ())

    failActor :: Fail -> ActorM Int ()
    failActor = error "I want to fail"


mySystem :: SupervisorDef
mySystem = defSupervisor $ do
  strategy OneForOne
  backoff $ \attempt -> seconds $ attempt * 2
  addChild numberPrinter
  addChild numberAccumulator

main :: IO ()
main = do
  evBus <- newPublishSubject
  print $ length (_supervisorDefChildren mySystem)
  sup <- startSupervisorWithEventBus evBus mySystem
  void . async $ do
    threadDelay (seconds 3)
    emitEvent sup (1 :: Int)
    emitEvent sup (2 :: Int)
    onNext evBus $ toGenericEvent (3 :: Int)
    emitEvent sup (PrintNumber ())
    emitEvent sup (PrintNumber ())
    emitEvent sup (PrintNumber ())

  joinSupervisorThread sup `finally` stopSupervisor sup
