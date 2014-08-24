{-# LANGUAGE ScopedTypeVariables #-}
module Assertion (
  delay, emitToActor, assertReceived, assertReceivedIn, expectError, testActorSystem
  ) where

import Control.Concurrent (yield, takeMVar, putMVar, newEmptyMVar)
import Control.Exception (Exception(..), SomeException(..), catch, finally, throwIO)
import Control.Monad (forM_)
import Data.Maybe (isJust)
import Data.Typeable (typeOf)
import Tiempo
import Tiempo.Concurrent
import Test.HUnit (assertBool, assertEqual, assertFailure)

import Rx.Actor

data ActorAssertion recv
  = ActorAssertion {
    _actorAssertionDelay   :: TimeInterval
  , _actorAssertionEmition :: EventBus -> IO ()
  , _actorAssertionExpect  :: [recv -> IO ()]
  , _actorAssertionErr     :: Maybe SomeException
  }

delay :: TimeInterval -> ActorAssertion recv -> ActorAssertion recv
delay interval actorAssertion = actorAssertion { _actorAssertionDelay = interval }

emitToActor :: (Typeable ev) => ev -> ActorAssertion recv -> ActorAssertion recv
emitToActor ev actorAssertion =
  actorAssertion { _actorAssertionEmition = (`emitEvent` ev) }

assertReceived :: (Show recv, Eq recv)
                  => recv -> ActorAssertion recv -> ActorAssertion recv
assertReceived ev actorAssertion =
  actorAssertion {
    _actorAssertionExpect =
       assertEqual "should match" ev : _actorAssertionExpect actorAssertion
  }

assertReceivedIn :: (Show recv, Eq recv)
                   => (recv -> Bool) -> ActorAssertion recv -> ActorAssertion recv
assertReceivedIn boolFn actorAssertion =
  actorAssertion {
    _actorAssertionExpect =
       (assertBool "should match" . boolFn)  : _actorAssertionExpect actorAssertion
  }


expectError :: Exception err => err -> ActorAssertion recv -> ActorAssertion recv
expectError err actorAssertion =
  actorAssertion {
    _actorAssertionErr = Just $ SomeException err
  }

defaultAssertion :: ActorAssertion recv
defaultAssertion = ActorAssertion {
    _actorAssertionDelay = seconds 0
  , _actorAssertionEmition = const $ return ()
  , _actorAssertionExpect = []
  , _actorAssertionErr = Nothing
  }

evalAssertion :: [ActorAssertion recv -> ActorAssertion recv] -> ActorAssertion recv
evalAssertion xs = foldr (.) id xs $ defaultAssertion

getErrorAssertion :: [ActorAssertion recv] -> Maybe SomeException
getErrorAssertion as =
  let errs = filter (\aa -> isJust (_actorAssertionErr aa)) as
  in case errs of
    [] -> Nothing
    (err:_) -> _actorAssertionErr err

testActorSystem
  :: (Typeable recv, Show recv, Eq recv)
  => Logger
  -> EventBus
  -> ((recv -> IO ()) -> ActorBuilder st)
  -> [[ActorAssertion recv -> ActorAssertion recv]]
  -> IO ()
testActorSystem logger evBus actorBuilder assertions0 = do
    resultVar <- newEmptyMVar
    let actorDef =
          defActor $ actorBuilder (putMVar resultVar . GenericEvent)
    actor <- startRootActor logger evBus actorDef
    main resultVar
      `catch` (\(ex :: SomeException) -> do
                case errorToAssert of
                  Just expectedEx -> do
                    assertEqual "should match error" (show expectedEx) (show ex)
                  Nothing -> do
                    throwIO ex)
      `finally` stopRootActor actor
  where
    assertions = map evalAssertion assertions0
    errorToAssert = getErrorAssertion assertions
    main resultVar = do
      yield
      threadDelay (microSeconds 400)

      forM_ assertions $ \assertion -> do
        _actorAssertionEmition assertion evBus
        threadDelay $ _actorAssertionDelay assertion
        forM_ (_actorAssertionExpect assertion) $ \assertFn -> do
          goutput@(GenericEvent innerOutput) <- takeMVar resultVar
          case fromGenericEvent goutput of
            Just output -> assertFn output
            Nothing ->
              assertFailure
                $ "expecting type doesn't match actual type "
                ++ (show $ typeOf innerOutput)

      yield
      threadDelay (microSeconds 400)
