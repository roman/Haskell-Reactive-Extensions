{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Main where


import Control.Monad (void)
import Control.Monad.Trans (liftIO)

import Control.Concurrent.Async (async)
import Control.Exception (AssertionFailed, ErrorCall, assert, finally)

import System.IO (stdout, hSetBuffering, BufferMode(LineBuffering))

import Tiempo (seconds)
import Tiempo.Concurrent (threadDelay)

import Rx.Observable (onNext, dispose)
import Rx.Subject (newPublishSubject)
import Rx.Logger ( Settings(..)
                 , newLogger
                 , setupTracer, defaultSettings )

import Rx.Actor


--------------------------------------------------------------------------------

newtype PrintNumber = PrintNumber () deriving (Typeable, Show)
newtype CallFail = CallFail () deriving (Typeable, Show)
newtype AssertFail = AssertFail () deriving (Typeable, Show)

--------------------------------------------------------------------------------

numberPrinter :: ActorDef ()
numberPrinter = defActor $ do
    actorKey "printer"
    startDelay (seconds 5)

    preStart $ do
      noisy ("preStart printer" :: String)
      return $ InitOk ()

    postStop $
      noisy ("postStop printer" :: String)

    preRestart $ \err _ev ->
      noisyF "preRestart printer => {}"
             (Only $ show err)

    postRestart $ \_err _ev -> do
      noisy ("postRestart printer : recovering from failure" :: String)
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
    onError $ \(_err :: ErrorCall) -> return Restart
    onError $ \(_err :: AssertionFailed) -> do
      noisy ("Resuming assertion failed error" :: String)
      return Resume

    -- This function is the "constructor" of the actor
    -- here you can return a value that can be InitOk or
    -- InitFailure
    preStart $ do
      noisy ("preStart accum" :: String)
      return $ InitOk 0

    -- This function is the "finalizer" of the actor
    -- here you should do cleanup of external resources
    postStop $
      noisy ("postStop accum" :: String)

    -- This gets executed before a restart is about to happen
    -- You will receive:
    -- - current state of the actor
    -- - the exception that happened on the actor
    -- - the event that caused it
    preRestart $ \err _ev -> do
      noisyF "preRestart accum => {}" (Only $ show err)

    -- This gets executed after a restart has happened
    -- You will receive:
    -- - current state of the actor
    -- - the exception that happened on the actor
    -- - the event that caused it
    postRestart $ \_err _ev -> do
      prevCount <- getState
      noisy ("postRestart accum: recovering from failure" :: String)
      noisyF "count was: {}" (Only prevCount)
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
      noisyF "acc => {}" (Only $ show n)

    -- This raises a CallError exception
    callError :: CallFail -> ActorM Int ()
    callError = error "I want to fail"

    -- This raises a AssertionFailure exception
    assertError :: AssertFail -> ActorM Int ()
    assertError = assert False undefined


mySystem :: SupervisorDef
mySystem = defSupervisor $ do
  -- Should I restart only the child that failed or
  -- all of them
  strategy AllForOne
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
  logger   <- newLogger
  sup <- startSupervisorWithEventBusAndLogger eventBus logger mySystem
  loggerDisposable <-
    setupTracer (defaultSettings { envPrefix = "ACTOR" })
                logger
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
  finally (joinSupervisorThread sup)
          (do stopSupervisor sup
              dispose loggerDisposable)
