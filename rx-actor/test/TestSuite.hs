{-# LANGUAGE ScopedTypeVariables #-}
module Main where

import Test.Hspec
import Test.HUnit

import Control.Monad (forM_)
import Control.Concurrent (yield)
import Control.Exception ( Exception
                         , ErrorCall (..)
                         , SomeAsyncException
                         , catch
                         , finally )

import Control.Concurrent.MVar

import Tiempo
import Tiempo.Concurrent

import Rx.Logger (setupLogTracer, defaultSettings)
import Rx.Actor

main :: IO ()
main = do
  logger <- newLogger
  evBus  <- newEventBus
  disposable <- setupLogTracer defaultSettings logger
  hspec (tests logger evBus) `finally` dispose disposable

tests :: Logger
      -> EventBus
      -> Spec
tests = actorSpec

assertActorReceives
  :: (Show a, Eq a, Typeable a)
  => Logger -> EventBus
  -> ((a -> IO ()) -> ActorBuilder st)
  -> [(GenericEvent, Maybe (String, (a -> Bool)))]
  -> IO ()
assertActorReceives logger evBus actorBuilder spec = do
    resultVar <- newEmptyMVar
    let actorDef = defActor $ actorBuilder (putMVar resultVar)
    actor <- startRootActor logger evBus actorDef
    go resultVar actor `finally` stopRootActor actor
  where
    go resultVar _actor = do
      yield
      threadDelay (microSeconds 400)
      forM_ spec $ \(input, mexpected) -> do
        onNext evBus input
        case mexpected of
          Nothing -> return ()
          Just (msg, assertion) -> do
            output <- takeMVar resultVar
            assertBool (msg ++ " (received: " ++ show output ++ ")")
                       (assertion output)

assertRootActorFails
  :: (Exception err, Eq err, Show a, Eq a, Typeable a)
  => Logger -> EventBus
  -> ((a -> IO ()) -> ActorBuilder st)
  -> [(GenericEvent, Maybe (String, (a -> Bool)))]
  -> err
  -> IO ()
assertRootActorFails logger evBus actorBuilder spec expectedErr = do
    resultVar <- newEmptyMVar
    let actorDef = defActor $ actorBuilder (putMVar resultVar)
    actor <- startRootActor logger evBus actorDef
    go resultVar actor
      `catch` (assertEqual "shoud match error" expectedErr)
      `finally` stopRootActor actor
  where
    go resultVar _actor = do
      -- yield and delay to allow actor to setup
      yield
      threadDelay (microSeconds 400)

      forM_ spec $ \(input, mexpected) -> do
        onNext evBus input
        case mexpected of
          Nothing -> return ()
          Just (msg, assertion) -> do
            output <- takeMVar resultVar
            assertBool (msg ++ " (received: " ++ show output ++ ")")
                       (assertion output)

      -- delay to allow actor to tearDown
      yield
      threadDelay (microSeconds 400)


actorSpec :: Logger -> EventBus -> Spec
actorSpec logger evBus = do
  describe "root" $ do

    it "can receive emitted events" $ do
      let input = 777 :: Int
      assertActorReceives logger evBus
        (\assertOutput -> do
            actorKey "single-andler-actor"
            singleTypeActor assertOutput)
        [ (GenericEvent input, Just ("should receive event", (== input))) ]

    it "can receive events of multiple types" $ do
      let leftInput  = 777 :: Int
          rightInput = "Hello" :: String
      assertActorReceives logger evBus
        (\ assertOutput -> do
            actorKey "multiple-handler-actor"
            preStart $ do
              return (InitOk ())
            receive (liftIO . assertOutput . Left)
            receive (liftIO . assertOutput . Right))
        [ (GenericEvent leftInput
          , Just ("should receive event", (== Left leftInput)))
        , (GenericEvent rightInput
          , Just ("should receive event", (== Right rightInput))) ]


    it "can handle a state" $ do
      assertActorReceives logger evBus
        simpleStateActor
        [ (GenericEvent (1 :: Int), Nothing)
        , (GenericEvent (), Just ("state should be consistent", (== (1 :: Int))))
        , (GenericEvent (9 :: Int), Nothing)
        , (GenericEvent (), Just ("state should be consistent", (== (10 :: Int)))) ]

    it "throws error on failure" $ do
      assertRootActorFails logger evBus
        (\ (_ :: () -> IO ()) -> do
          actorKey "failing-actor"
          failingActor)
        [ (GenericEvent (), Nothing) ]
        (ErrorCall "fail!")

  describe "dynamic child" $ do
    it "can receive emitted events" $ do
      let input = 777 :: Int

      assertActorReceives logger evBus
          (\ assertOutput -> do
              preStart $ do
                return (InitOk ())
              receive $ \() ->
                spawnChild "single-type" $ do
                  preStart $ return (InitOk ())
                  singleTypeActor  assertOutput)
          [ (GenericEvent (), Nothing)
          , (GenericEvent input, Just ("should receive event", (== input)))]


  describe "static child" $ do

    it "can receive emitted events" $ do
      let input = 777 :: Int

      assertActorReceives logger evBus
          (\ assertOutput -> do
              preStart $ do
                return (InitOk ())
              addChild "single-type" $ do
                singleTypeActor  assertOutput)
          [(GenericEvent input, Just ("should receive event", (== input)))]

    it "can receive events of multiple types on children" $ do
      let leftInput = 777 :: Int
          rightInput = "555" :: String

      assertActorReceives logger evBus
        (\ assertOutput -> do
            preStart $ do
              return (InitOk ())

            addChild "left-type" $ do
              preStart $ return (InitOk ())
              receive (liftIO . assertOutput . Left)

            addChild "right-type" $ do
              preStart $ return (InitOk ())
              receive (liftIO . assertOutput . Right))

        [ ( GenericEvent leftInput
          , Just ("child should receive event", (== Left leftInput)))

        , ( GenericEvent rightInput
          , Just ("child should receive event", (== Right rightInput)))
        ]

    it "can handle a state" $ do
      assertActorReceives logger evBus
        (\ assertOutput -> do
            preStart $ do
              return $ InitOk ()

            addChild "child-with-state" $ do
              simpleStateActor  assertOutput)

        [ (GenericEvent (1 :: Int), Nothing)
        , (GenericEvent (), Just ("state should be consistent", (== (1 :: Int))))
        , (GenericEvent (9 :: Int), Nothing)
        , (GenericEvent (), Just ("state should be consistent", (== (10 :: Int)))) ]

    describe "on error" $ do

      describe "with raise directive" $ do
        it "raises the error" $ do
          let assertion =
                assertActorReceives logger evBus
                  (\ assertOutput -> do
                    preStart $ do
                      return $ InitOk ()
                    addChild "failing-actor" $ do
                      preStart $ return $ InitOk ()
                      onError $ \(_ :: ErrorCall) -> return Raise
                      receive $ \(ev :: String) -> liftIO $ assertOutput ev
                      failingActor)
                  [ (GenericEvent (), Nothing)
                  , ( GenericEvent "foo", Just ("should receive event", (== "foo")) )]

          assertion `shouldThrow` errorCall "fail!"

      describe "with resume directive" $ do
        it "ignores error" $ do
          assertActorReceives logger evBus
            (\ assertOutput -> do
              preStart $ do
                return $ InitOk ()
              addChild "failing-actor" $ do
                onError $ \(_ :: ErrorCall) -> return Resume
                receive $ \(ev :: String) -> liftIO $ assertOutput ev
                failingActor)
            [ ( GenericEvent (), Nothing )
            , ( GenericEvent "foo", Just ("should receive event", (== "foo")) ) ]

      describe "with stop directive" $ do
        it "stops failing actor" $ do
          let input = 123 :: Int
          assertActorReceives logger evBus
            (\ assertOutput -> do
              preStart $ do
                return $ InitOk ()

              addChild "single-child" $ do
                backoff . const $ seconds 0
                singleTypeActor  (assertOutput . Left)

              addChild "failing-actor" $ do
                backoff . const $ seconds 0
                onError $ \(_ :: ErrorCall) -> return Stop
                receive $ \(ev :: String) -> liftIO . assertOutput $ Right ev
                failingActor)
            [ ( GenericEvent (), Nothing)
            , ( GenericEvent "foo", Nothing)
            -- if stopped actor would still be alive, this would
            -- return a Right instead of a Left
            , ( GenericEvent input
              , Just ("should receive event of non stopped actor"
                     , (== Left input))) ]

      describe "with restart directive" $ do

        describe "with OneForOne strategy" $ do
          it "calls preRestart once" $ do
            assertActorReceives logger evBus
              (\ assertOutput -> do
                backoff (const $ seconds 0)

                preStart $ do
                  return $ InitOk ()

                addChild "failing-actor" $ do
                  preRestart $ \_err _ev ->
                    liftIO $ assertOutput True
                  onError $ \(_ :: ErrorCall) -> return Restart
                  failingActor)
              [ (GenericEvent (), Just ("should call preRestart", id)) ]

          it "calls postRestart once" $ do
            assertActorReceives logger evBus
              (\ assertOutput -> do
                backoff (const $ seconds 0)

                preStart $ do
                  return $ InitOk ()

                addChild "failing-actor" $ do
                  postRestart $ \_err _ev -> do
                    liftIO $ assertOutput True
                    return $ InitOk ()
                  onError $ \(_ :: ErrorCall) -> return Restart
                  failingActor)
              [ (GenericEvent (), Just ("should call postRestart", id)) ]

        describe "with AllForOne strategy" $ do
          it "calls preRestart for each actor" $ do
            let validValues = ["one", "two"]
            assertActorReceives logger evBus
              (\ assertOutput -> do
                strategy AllForOne
                backoff (const $ seconds 0)

                preStart $ do
                  return $ InitOk ()

                addChild "one" $ do
                  preStart . return $ InitOk ()
                  preRestart $ \_err _ev ->
                    liftIO $ assertOutput "one"
                addChild "two" $ do
                  preStart . return $ InitOk ()
                  preRestart $ \_err _ev ->
                    liftIO $ assertOutput "two"
                  onError $ \(_ :: ErrorCall) -> return Restart
                  failingActor)
              [ ( GenericEvent ()
                , Just ("should call preRestart", (`elem` validValues)))
              , (GenericEvent "ignored"
                , Just ("should call preRestart", (`elem` validValues))) ]

          it "calls postRestart for each actor" $ do
            let validValues = ["one", "two"]
            assertActorReceives logger evBus
              (\ assertOutput -> do
                strategy AllForOne
                backoff (const $ seconds 0)

                preStart $ do
                  return $ InitOk ()

                addChild "one" $ do
                  preStart . return $ InitOk ()
                  postRestart $ \_err _ev -> do
                    liftIO $ assertOutput "one"
                    return $ InitOk ()

                addChild "two" $ do
                  preStart . return $ InitOk ()
                  postRestart $ \_err _ev -> do
                    liftIO $ assertOutput "two"
                    return $ InitOk ()
                  onError $ \(_ :: ErrorCall) -> return Restart
                  failingActor)
              [ ( GenericEvent ()
                , Just ("should call postRestart", (`elem` validValues)))
              , (GenericEvent ()
                , Just ("should call postRestart", (`elem` validValues))) ]


  where
    singleTypeActor  assertOutput = do
      preStart $ do
        return (InitOk ())
      stopDelay (seconds 0)
      receive (liftIO . assertOutput)

    simpleStateActor  assertOutput = do
      preStart $ do
        return $ InitOk 0
      stopDelay (seconds 0)
      receive $ \n  -> modifyState (+n)
      receive $ \() -> getState >>= liftIO . assertOutput

failingActor :: ActorBuilder ()
failingActor = do
  preStart $ return (InitOk ())
  receive (\() -> error "fail!")
