{-# LANGUAGE ScopedTypeVariables #-}
module Main where

import Test.Hspec
import Test.HUnit

import Control.Monad (forM_)
import Control.Exception ( ErrorCall, SomeAsyncException, finally )

import Control.Concurrent (yield)
import Control.Concurrent.MVar

import Tiempo

import Rx.Logger (setupTracer, defaultSettings)
import Rx.Actor

main :: IO ()
main = do
  logger <- newLogger
  evBus  <- newEventBus
  disposable <- setupTracer defaultSettings logger
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
    go resultVar actor `finally` dispose actor
  where
    go resultVar _actor = do
      yield
      forM_ spec $ \(input, mexpected) -> do
        onNext evBus input
        case mexpected of
          Nothing -> return ()
          Just (msg, assertion) -> do
            output <- takeMVar resultVar
            assertBool (msg ++ " (received: " ++ show output ++ ")")
                       (assertion output)

anyAsyncException :: Selector SomeAsyncException
anyAsyncException = const True

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
        (\assertOutput -> do
            actorKey "multiple-handler-actor"
            preStart $ return (InitOk ())
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
      assertActorReceives logger evBus
        (\(_ :: () -> IO ()) -> do
          actorKey "failing-actor"
          failingActor)
        [ (GenericEvent (), Nothing) ]
          `shouldThrow` errorCall "fail!"

  describe "dynamic child" $ do
    it "can receive emitted events" $ do
      let input = 777 :: Int

      assertActorReceives logger evBus
          (\assertOutput -> do
              preStart $ return (InitOk ())
              receive $ \() ->
                spawnChild "single-type" $ do
                  preStart $ return (InitOk ())
                  singleTypeActor assertOutput)
          [ (GenericEvent (), Nothing)
          , (GenericEvent input, Just ("should receive event", (== input)))]


  describe "static child" $ do

    it "can receive emitted events" $ do
      let input = 777 :: Int

      assertActorReceives logger evBus
          (\assertOutput -> do
              preStart $ return (InitOk ())
              buildChild $ do
                actorKey "single-type"
                singleTypeActor assertOutput)
          [(GenericEvent input, Just ("should receive event", (== input)))]

    it "can receive events of multiple types on children" $ do
      let leftInput = 777 :: Int
          rightInput = "555" :: String

      assertActorReceives logger evBus
        (\assertOutput -> do
            preStart $ return (InitOk ())

            buildChild $ do
              actorKey "left-type"
              preStart $ return (InitOk ())
              receive (liftIO . assertOutput . Left)

            buildChild $ do
              actorKey "right-type"
              preStart $ return (InitOk ())
              receive (liftIO . assertOutput . Right))

        [ ( GenericEvent leftInput
          , Just ("child should receive event", (== Left leftInput)))

        , ( GenericEvent rightInput
          , Just ("child should receive event", (== Right rightInput)))
        ]

    it "can handle a state" $ do
      assertActorReceives logger evBus
        (\assertOutput -> do
            preStart $ return $ InitOk ()
            buildChild $ do
              actorKey "child-with-state"
              simpleStateActor assertOutput)
        [ (GenericEvent (1 :: Int), Nothing)
        , (GenericEvent (), Just ("state should be consistent", (== (1 :: Int))))
        , (GenericEvent (9 :: Int), Nothing)
        , (GenericEvent (), Just ("state should be consistent", (== (10 :: Int)))) ]

    describe "on error" $ do

      describe "with raise directive" $ do
        it "raises the error" $ do
          let assertion =
                assertActorReceives logger evBus
                  (\assertOutput -> do
                    preStart $ return $ InitOk ()
                    buildChild $ do
                      actorKey "failing-actor"
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
            (\assertOutput -> do
              preStart $ return $ InitOk ()
              buildChild $ do
                actorKey "failing-actor"
                onError $ \(_ :: ErrorCall) -> return Resume
                receive $ \(ev :: String) -> liftIO $ assertOutput ev
                failingActor)
            [ ( GenericEvent (), Nothing )
            , ( GenericEvent "foo", Just ("should receive event", (== "foo")) ) ]

      describe "with stop directive" $ do
        it "stops failing actor" $ do
          let input = 123 :: Int
          assertActorReceives logger evBus
            (\assertOutput -> do
              preStart $ return $ InitOk ()
              buildChild $ do
                actorKey "single-child"
                backoff . const $ seconds 0
                singleTypeActor (assertOutput . Left)
              buildChild $ do
                actorKey "failing-actor"
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
              (\assertOutput -> do
                preStart $ return $ InitOk ()
                backoff (const $ seconds 0)
                buildChild $ do
                  actorKey "failing-actor"
                  preRestart $ \_err _ev ->
                    liftIO $ assertOutput True
                  onError $ \(_ :: ErrorCall) -> return Restart
                  failingActor)
              [ (GenericEvent (), Just ("should call preRestart", id)) ]

          it "calls postRestart once" $ do
            assertActorReceives logger evBus
              (\assertOutput -> do
                preStart $ return $ InitOk ()
                backoff (const $ seconds 0)
                buildChild $ do
                  actorKey "failing-actor"
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
              (\assertOutput -> do
                strategy AllForOne
                preStart . return $ InitOk ()
                backoff (const $ seconds 0)
                buildChild $ do
                  actorKey "one"
                  preStart . return $ InitOk ()
                  preRestart $ \_err _ev ->
                    liftIO $ assertOutput "one"
                buildChild $ do
                  actorKey "two"
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
              (\assertOutput -> do
                strategy AllForOne
                preStart . return $ InitOk ()
                backoff (const $ seconds 0)
                buildChild $ do
                  actorKey "one"
                  preStart . return $ InitOk ()
                  postRestart $ \_err _ev -> do
                    liftIO $ assertOutput "one"
                    return $ InitOk ()
                buildChild $ do
                  actorKey "two"
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
    singleTypeActor assertOutput = do
      preStart $ return (InitOk ())
      stopDelay (seconds 0)
      receive (liftIO . assertOutput)

    simpleStateActor assertOutput = do
      preStart . return $ InitOk 0
      stopDelay (seconds 0)
      receive $ \n  -> modifyState (+n)
      receive $ \() -> getState >>= liftIO . assertOutput

failingActor :: ActorBuilder ()
failingActor = do
  preStart $ return (InitOk ())
  receive (\() -> error "fail!")
