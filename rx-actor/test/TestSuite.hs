{-# LANGUAGE ScopedTypeVariables #-}
module Main where

import Control.Exception (ErrorCall (..), finally)
import Tiempo

import Rx.Actor
import Rx.Logger (defaultSettings, setupLogTracer)

import Assertion
import Test.Hspec

--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------


actorSpec :: Logger -> EventBus -> Spec
actorSpec logger evBus = do
  describe "root" $ do

    it "can receive emitted events" $ do
      let input = 777 :: Int
      testActorSystem logger evBus
        (\sendToAssertReceived -> do
            preStart $ return (InitOk ())
            receive (\(ev :: Int) -> liftIO $ sendToAssertReceived ev))
        [ [emitToActor input, assertReceived input] ]

    it "can receive events of multiple types" $ do
      let leftInput  = 777 :: Int
          rightInput = "Hello" :: String

      testActorSystem logger evBus
        (\sendToAssertReceived -> do
            preStart $ return $ InitOk ()
            receive (\(ev :: Int) ->
                      liftIO . sendToAssertReceived $ Left ev)
            receive (\(ev :: String) ->
                      liftIO . sendToAssertReceived $ Right ev))

        [ [ emitToActor leftInput, assertReceived (Left leftInput) ]
        , [ emitToActor rightInput, assertReceived (Right rightInput) ]
        ]


    it "can handle a state" $ do
      testActorSystem logger evBus
        simpleStateActor
        [ [emitToActor (1 :: Int)]
        , [emitToActor (), assertReceived 1]
        , [emitToActor (9 :: Int)]
        , [emitToActor (), assertReceived 10]]

    it "throws error on failure" $ do
      testActorSystem logger evBus
        (\(_ :: () -> IO ()) -> failingActor)
        [ [emitToActor (), expectError (ErrorCall "fail!")] ]

  describe "dynamic child" $ do

    it "can receive emitted events" $ do
      let input = 777 :: Int

      testActorSystem logger evBus
          (\(sendToAssertReceived :: Int -> IO ()) -> do
              preStart $ return $ InitOk ()
              receive $ \() ->
                spawnChild "single-type" $ do
                  preStart $ return (InitOk ())
                  singleTypeActor sendToAssertReceived)
          [ [emitToActor ()]
          , [emitToActor input, assertReceived input] ]

    it "can be stopped" $ do
      let input = "Child is Alive" :: String

      testActorSystem logger evBus
          (\sendToAssertReceived -> do
              preStart $ return $ InitOk ()
              receive $ \(req :: Either () ()) ->
                case req of
                 Left () -> stopChild "single-type"
                 Right () ->
                   spawnChild "single-type" $ do
                     preStart $ return (InitOk ())
                     postStop $ liftIO $ sendToAssertReceived "Child was Stopped"
                     singleTypeActor sendToAssertReceived)
          [ [emitToActor (Right () :: Either () ())]
          , [emitToActor input, assertReceived input]
          , [emitToActor (Left () :: Either () ()), assertReceived "Child was Stopped"] ]


  describe "static child" $ do

    it "can receive emitted events" $ do
      let input = 777 :: Int

      testActorSystem logger evBus
          (\ sendToAssertReceived -> do
              preStart $ return $ InitOk ()
              addChild "single-type" $
                singleTypeActor sendToAssertReceived)
          [ [emitToActor input, assertReceived input] ]

    it "can receive events of multiple types on children" $ do
      let leftInput = 777 :: Int
          rightInput = "555" :: String

      testActorSystem logger evBus
        (\sendToAssertReceived -> do
            preStart $ return $ InitOk ()

            addChild "left-type" $ do
              preStart $ return $ InitOk ()
              receive (liftIO . sendToAssertReceived . Left)

            addChild "right-type" $ do
              preStart $ return $ InitOk ()
              receive (liftIO . sendToAssertReceived . Right))

        [ [ emitToActor leftInput, assertReceived (Left leftInput) ]
        , [ emitToActor rightInput, assertReceived (Right rightInput) ]
        ]

    it "can be stopped" $ do
      let input = "Child is Alive" :: String

      testActorSystem logger evBus
          (\sendToAssertReceived -> do
              preStart $ return $ InitOk ()
              receive $ \(req :: Either () ()) ->
                case req of
                 Left () -> stopChild "single-type"
                 Right () ->
                   spawnChild "single-type" $ do
                     preStart $ return (InitOk ())
                     postStop $ liftIO $ sendToAssertReceived "Child was Stopped"
                     singleTypeActor sendToAssertReceived)
          [ [emitToActor (Right () :: Either () ())]
          , [emitToActor input, assertReceived input]
          , [emitToActor (Left () :: Either () ()), assertReceived "Child was Stopped"] ]


    it "can handle a state" $ do
      testActorSystem logger evBus
        (\sendToAssertReceived -> do
            preStart $ return $ InitOk ()
            addChild "child-with-state" $ do
              simpleStateActor sendToAssertReceived)
        [ [ emitToActor (1 :: Int) ]
        , [ emitToActor (), assertReceived (1 :: Int) ]
        , [ emitToActor (9 :: Int) ]
        , [ emitToActor (), assertReceived (10 :: Int) ]]


    describe "on error" $ do
      describe "with raise directive" $ do
        it "raises the error" $ do
          testActorSystem logger evBus
             (\sendToAssertReceived -> do
                 onError $ \(_ :: ErrorCall) -> return Raise
                 preStart $ return $ InitOk ()
                 addChild "failing-actor" $ do
                   onError $ \(_ :: ErrorCall) -> return Raise
                   preStart $ return $ InitOk ()
                   receive $ \(ev :: String) -> liftIO $ sendToAssertReceived ev
                   failingActor)
             [ [emitToActor "foo", assertReceived "foo"]
             , [emitToActor ()]
             , [delay (seconds 1), expectError (ErrorCall "fail!")] ]

      describe "with resume directive" $ do
        it "ignores error" $ do
          testActorSystem logger evBus
            (\ sendToAssertReceived -> do
              preStart $ return $ InitOk ()
              addChild "failing-actor" $ do
                onError $ \(_ :: ErrorCall) -> return Resume
                receive $ \(ev :: String) -> liftIO $ sendToAssertReceived ev
                failingActor)
            [ [ emitToActor () ]
            , [ emitToActor "foo", assertReceived "foo"] ]

      describe "with stop directive" $ do
        it "stops failing actor" $ do
          let input = 123 :: Int
          testActorSystem logger evBus
            (\ sendToAssertReceived -> do
              preStart $ do
                return $ InitOk ()

              addChild "single-child" $ do
                backoff . const $ seconds 0
                singleTypeActor  (sendToAssertReceived . Left)

              addChild "failing-actor" $ do
                backoff . const $ seconds 0
                onError $ \(_ :: ErrorCall) -> return Stop
                receive $ \(ev :: String) -> liftIO . sendToAssertReceived $ Right ev
                failingActor)
            [ [ emitToActor () ]
            , [ emitToActor "foo" ]
            -- if stopped actor would still be alive, this would
            -- return a Right instead of a Left
            , [ emitToActor input, assertReceived (Left input) ] ]

      describe "with restart directive" $ do

        describe "with OneForOne strategy" $ do
          it "calls preRestart once" $ do
            testActorSystem logger evBus
              (\ sendToAssertReceived -> do
                backoff (const $ seconds 0)

                preStart $ do
                  return $ InitOk ()

                addChild "failing-actor" $ do
                  preRestart $ \_err _ev ->
                    liftIO $ sendToAssertReceived True

                  onError $ \(_ :: ErrorCall) -> return Restart
                  failingActor)
              [ [ emitToActor (), assertReceived True ] ]

          it "calls postRestart once" $ do
            testActorSystem logger evBus
              (\ sendToAssertReceived -> do
                backoff (const $ seconds 0)

                preStart $ do
                  return $ InitOk ()

                addChild "failing-actor" $ do
                  postRestart $ \_err _ev -> do
                    liftIO $ sendToAssertReceived True
                    return $ InitOk ()
                  onError $ \(_ :: ErrorCall) -> return Restart
                  failingActor)
              [ [ emitToActor (), assertReceived True ] ]

        describe "with AllForOne strategy" $ do
          it "calls preRestart for each actor" $ do
            let validValues = ["one", "two"]
            testActorSystem logger evBus
              (\ sendToAssertReceived -> do
                strategy AllForOne
                backoff (const $ seconds 0)

                preStart $ do
                  return $ InitOk ()

                addChild "one" $ do
                  preStart . return $ InitOk ()
                  preRestart $ \_err _ev ->
                    liftIO $ sendToAssertReceived "one"

                addChild "two" $ do
                  preStart . return $ InitOk ()
                  preRestart $ \_err _ev ->
                    liftIO $ sendToAssertReceived "two"
                  onError $ \(_ :: ErrorCall) -> return Restart
                  failingActor)

              [ [ emitToActor ()
                , assertReceivedIn (`elem` validValues)
                , assertReceivedIn (`elem` validValues ) ] ]

          it "calls postRestart for each actor" $ do
            let validValues = ["one", "two"]
            testActorSystem logger evBus
              (\ sendToAssertReceived -> do
                strategy AllForOne
                backoff (const $ seconds 0)

                preStart $ return $ InitOk ()

                addChild "one" $ do
                  preStart . return $ InitOk ()
                  postRestart $ \_err _ev -> do
                    liftIO $ sendToAssertReceived "one"
                    return $ InitOk ()

                addChild "two" $ do
                  onError $ \(_ :: ErrorCall) -> return Restart
                  preStart . return $ InitOk ()
                  postRestart $ \_err _ev -> do
                    liftIO $ sendToAssertReceived "two"
                    return $ InitOk ()
                  failingActor)

              [ [ emitToActor ()
                , assertReceivedIn (`elem` validValues)
                , assertReceivedIn (`elem` validValues) ] ]

  describe "grandchildren failure" $ do
    describe "with restart directive on grandparent & raise directive on parent" $ do
      it "restarts child & grandchild when grandchild's handler fails" $ do
        testActorSystem logger evBus
          (\(sendToAssertReceived :: String -> IO ()) -> do
            strategy AllForOne
            backoff . const $ seconds 0
            preStart $ return $ InitOk ()

            addChild "child" $ do
              backoff . const $ seconds 0
              preStart $ return $ InitOk ()
              preRestart $ \_err _ev -> do
                liftIO $ sendToAssertReceived "on child prerestart"
              postRestart $ \_err _ev -> do
                return $ InitOk ()

              addChild "grandchild" $ do
                onError $ \(_ :: ErrorCall) -> return Raise
                preStart $ return $ InitOk ()
                receive (\() -> error "fail!")
                receive $ \(msg :: String) -> liftIO $ sendToAssertReceived msg)

          [ [emitToActor "Hello", assertReceived "Hello"]
          , [emitToActor (), assertReceived "on child prerestart"]
          , [emitToActor "World", assertReceived "World"] ]
  where
    singleTypeActor sendToAssertReceived = do
      preStart $ return $ InitOk ()
      stopDelay (seconds 0)
      receive (liftIO . sendToAssertReceived)

    simpleStateActor sendToAssertReceived = do
      preStart $ return $ InitOk (0 :: Int)
      stopDelay (seconds 0)
      receive $ \n  -> modifyState (+n)
      receive $ \() -> getState >>= liftIO . sendToAssertReceived

failingActor :: ActorBuilder ()
failingActor = do
  preStart $ return (InitOk ())
  receive (\() -> error "fail!")
