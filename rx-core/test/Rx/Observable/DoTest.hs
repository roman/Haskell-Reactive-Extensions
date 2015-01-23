module Rx.Observable.DoTest where

import Control.Exception (fromException, ErrorCall(..))
import qualified Rx.Observable as Rx

import Test.HUnit
import Test.Hspec

tests :: Spec
tests =
  describe "Rx.Observable.doAction" $ do
    describe "when action raises an error" $
      it "calls onError statement" $ do
        let source = 
              Rx.doAction (\v -> if v < 5
                                   then return ()
                                   else error "value greater than 5")
              $  Rx.fromList Rx.newThread [1..10]

        eResult <- Rx.toList source
        case eResult of
          Right _  -> assertFailure "Expected source to fail but didn't"
          Left (_, err) ->
            maybe (assertFailure "Didn't receive specific failure")
                  (assertEqual "Didn't receive specific failure"
                               (ErrorCall "value greater than 5"))
                  (fromException err)
      
    describe "when action doesn't raise an error" $ do
      it "performs side effect per element" pending
    
