module Rx.Observable.FirstTest where

import Control.Exception (ErrorCall(..), fromException)
import qualified Rx.Observable as Rx

import Test.HUnit
import Test.Hspec

tests :: Spec
tests = do
  describe "Rx.Observable.once" $ do
    it "succeeds when source emits an element once" $ do
      let source = Rx.once $ return (10 :: Int)
      result <- Rx.toList source
      case result of
        Right v ->
          assertEqual "Expecting single element" [10] v
        Left err ->
          assertFailure $ "unexpected error: " ++ show err

    it "emits OnError when source emits more than one element" $ do
      let source =
            Rx.once
            $ Rx.fromList Rx.newThread ([1..10] :: [Int])

      result <- Rx.toList source
      case result of
        Right v ->
          assertFailure $ "expected failure but didn't happen: " ++ show v
        Left (_, err) ->
          assertEqual "expecting once error but didn't receive it"
                      (Just $ ErrorCall "once: expected to receive one element")
                      (fromException err)
