{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Rx.Actor
       ( GenericEvent, EventBus
       , ActorBuilder, ActorM, ActorDef, Actor, RestartDirective(..), InitResult(..)
       , SupervisorBuilder, SupervisorStrategy(..), SupervisorDef, Supervisor
       -- ^ * Actor Builder API
       , defActor, actorKey, preStart, preStart1, postStop, preRestart, postRestart
       , onError, desc, receive, useBoundThread, decorateEventBus
       -- ^ * Actor message handlers API
       , getState, setState, modifyState, getEventBus, emit
       -- ^ * SupervisorBuilder API
       , defSupervisor, strategy, backoff, maxRestarts, addChild, buildChild
       -- ^ * Supervisor API
       , startSupervisor, startSupervisorWithEventBus, stopSupervisor
       , emitEventToSupervisor, joinSupervisorThread
       -- ^ * EventBus API
       , fromGenericEvent, toGenericEvent, emitEvent, typeOfEvent, filterEvent, mapEvent
       ) where

import Control.Exception (ErrorCall(..), AssertionFailed, finally, fromException, assert)

import Data.Typeable (Typeable)

import Control.Monad (void)
import Control.Monad.Trans (liftIO)

import Control.Concurrent.Async (async)

import System.IO (BufferMode(LineBuffering), hSetBuffering, stdout)

import Rx.Observable (onNext)
import Rx.Subject (newPublishSubject)

import Tiempo (seconds)
import Tiempo.Concurrent (threadDelay)

import Rx.Actor.ActorBuilder
import Rx.Actor.Monad
import Rx.Actor.EventBus
import Rx.Actor.Supervisor
import Rx.Actor.Supervisor.SupervisorBuilder

import Rx.Actor.Types


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

    postStop $ \_ -> do
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
    -- This is the identifier that the Supervisor will
    -- use internally to refer to this actor
    actorKey "accum"

    -- Everytime an error of the given type happens, you have
    -- to return a directive of what to do, options are:
    -- * Restart - restarts to the current actor
    -- * Stop    - stops the current actor
    -- * Resume  - ignore the error and resume
    -- * Raise   - raise the error on the supervisor level
    onError $ \(err :: ErrorCall) _st -> return Restart
    onError $ \(err :: AssertionFailed) _st -> do
      putStrLn "Resuming assertion failed error"
      return $ Resume

    -- This function is the "constructor" of the actor
    -- here you can return a value that can be InitOk or
    -- InitFailure
    preStart $ do
      putStrLn "preStart accum"
      return $ InitOk 0

    -- This function is the "finalizer" of the actor
    -- here you should do cleanup of external resources
    postStop $ \_ -> do
      putStrLn "postStop accum"

    -- This gets executed before a restart is about to happen
    -- You will receive:
    -- - current state of the actor
    -- - the exception that happened on the actor
    -- - the event that caused it
    preRestart $ \_ err _ev -> do
      putStrLn $ "preRestart accum => " ++ show err

    -- This gets executed after a restart has happened
    -- You will receive:
    -- - current state of the actor
    -- - the exception that happened on the actor
    -- - the event that caused it
    postRestart $ \prevCount err _ev -> do
      putStrLn $ "postRestart accum: recovering from failure"
      putStrLn $ "count was: " ++ show prevCount
      return $ InitOk 0

    -- General description for the event handler
    desc "sums to a total the given integer"
    -- actual definition of the event handler
    receive accumulateNumber

    desc "Prints number on terminal"
    receive printNumber

    desc "Fails the actor via ErrorCall"
    receive callError

    desc "Fails the actor via AssertionFailed"
    receive assertError
  where
    -- All the receive actions work inside the ActorM monad,
    -- they allow you to get the internal state of the actor
    -- and also to emit events to the main eventBus
    accumulateNumber :: Int -> ActorM Int ()
    accumulateNumber n = modifyState (+n)

    -- this particular action will print the current state
    -- and also it will emit the event "CallFail" which this
    -- actor can handle
    printNumber :: PrintNumber -> ActorM Int ()
    printNumber _ = do
      n <- getState
      emit (CallFail ())
      liftIO $ putStrLn $ "acc => " ++ show n

    -- This raises a CallError exception
    callError :: CallFail -> ActorM Int ()
    callError = error "I want to fail"

    -- This raises a AssertionFailure exception
    assertError :: AssertFail -> ActorM Int ()
    assertError = assert False $ undefined


mySystem :: SupervisorDef
mySystem = defSupervisor $ do
  -- Should I restart only the child that failed or
  -- all of them
  strategy OneForOne
  -- If I restart a child, how much time should I await for each attempt?
  backoff $ \attempt -> seconds $ 2 ^ attempt

  addChild numberPrinter
  addChild numberAccumulator

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  -- All the different events (requests) of the system are going to be "published"
  -- to this event bus, they may be of different types
  eventBus <- newPublishSubject
  print $ length (_supervisorDefChildren mySystem)
  sup <- startSupervisorWithEventBus eventBus mySystem
  void . async $ do
    threadDelay $ seconds 3
    -- When emitting an Event to the supervisor, this will broadcast the
    -- event to all the associated children (defined in lines [166, 167])
    -- If the child actor doesn't know how to react to the type of event, it
    -- will ignore it, if it understands it, it will react to it by doing side-effects
    -- or emitting new events to the main eventBus
    emitEventToSupervisor sup (1 :: Int)
    emitEventToSupervisor sup (2 :: Int)
    emitEventToSupervisor sup (AssertFail ())
    onNext eventBus $ toGenericEvent (3 :: Int)
    emitEventToSupervisor sup (PrintNumber ())
    -- Uncomment this to see the backoff strategy
    -- emitEvent sup (PrintNumber ())
    -- emitEvent sup (PrintNumber ())
    -- emitEvent sup (PrintNumber ())
    -- emitEvent sup (PrintNumber ())

  -- make the supervisor thread the `main` thread, and
  -- cleanup all the actors once is finished
  joinSupervisorThread sup `finally` stopSupervisor sup
