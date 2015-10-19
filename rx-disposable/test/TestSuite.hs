{-# LANGUAGE NoImplicitPrelude #-}
module Main where

import Prelude.Compat

import Data.Monoid ((<>))

import Control.Monad (replicateM_, forM)
import Control.Concurrent.STM (atomically, newTVarIO, modifyTVar, readTVar)

import Rx.Disposable
import Test.Hspec
import Test.HUnit (assertEqual)

main :: IO ()
main = hspec $ do
  describe "Disposable" $ do
    describe "mappend" $
      it "combines multiple disposables" $ do
        setup <- forM ([1..10] :: [Int]) $ \index -> do
          var <- newTVarIO (0 :: Int)
          disposable <- newDisposable (show index) (atomically $ modifyTVar var succ)
          return (var, disposable)

        let (vars, disposables) = unzip setup
            disposable = mconcat disposables

        replicateM_ 10 (dispose disposable)
        result <- disposeVerbose disposable

        -- ensure disposables weren't called more than once
        values <- mapM (atomically . readTVar) vars
        mapM_ (assertEqual "disposables were called more than once" 1) values

        -- ensure there are 10 disposables on the result
        assertEqual "didn't account for all disposables"
                    10
                    (disposeCount result)

    describe "wrapDisposable" $
      it "attaches error message to existing disposable" $ do
        disp1 <- newDisposable "inner-1" (return ())
        disp2 <- newDisposable "inner-2" (return ())
        disp3 <- newDisposable "inner-3" (error "failed")


        outerDisp <- wrapDisposable "outer" (return (disp1 <> disp2 <> disp3))
        result <- disposeVerbose outerDisp

        assertEqual "should have 3 entries" (disposeCount result) 3
        assertEqual "should have complete description"
                    [ "outer | inner-1"
                    , "outer | inner-2"
                    , "outer | inner-3" ]
                    (map fst (disposeActionList result))


    describe "dispose" $
      it "calls action only once" $ do
        accVar <- newTVarIO (0 :: Int)
        disposable <- newDisposable "" (atomically $ modifyTVar accVar succ)
        replicateM_ 10 (dispose disposable)
        count <- atomically $ readTVar accVar
        assertEqual "should not be more than 1" 1 count

  describe "BooleanDisposable" $
    describe "setDisposable" $
      it "disposes previous disposable" $ do
        accVar <- newTVarIO ([] :: [Int])
        bd <- newBooleanDisposable

        disposable1 <- newDisposable "" (atomically $ modifyTVar accVar (1:))
        disposable2 <- newDisposable "" (atomically $ modifyTVar accVar (2:))

        setDisposable bd disposable1
        setDisposable bd disposable2

        acc1 <- atomically $ readTVar accVar
        assertEqual "setDisposable should have called dispose in previous disposable" [1] acc1

        dispose bd
        acc2 <- atomically $ readTVar accVar
        assertEqual "dispose should call current disposable" [2, 1] acc2

  describe "SingleAssignmentDisposable" $
    describe "setDisposable" $
      it "throws runtime error if set more than once" $ do
        sad <- newSingleAssignmentDisposable
        let errMsg = "ERROR: called 'setDisposable' more " ++
                     "than once on SingleAssignmentDisposable"

        disposable1 <- newDisposable "" (return ())
        disposable2 <- newDisposable "" (return ())

        setDisposable sad disposable1
        shouldThrow (setDisposable sad disposable2)
                    (errorCall errMsg)

  describe "ToDisposable" $
    it "allows composition of multiple Disposable types" $ do
      sadFlag  <- newTVarIO (0 :: Int)
      bdFlag   <- newTVarIO (0 :: Int)
      dispFlag <- newTVarIO (0 :: Int)

      sad <- newSingleAssignmentDisposable
      bd  <- newBooleanDisposable

      sadInner   <- newDisposable "sad"    $ atomically $ modifyTVar sadFlag succ
      bdInner    <- newDisposable "bd"     $ atomically $ modifyTVar bdFlag succ
      disposable <- newDisposable "normal" $ atomically $ modifyTVar dispFlag succ

      setDisposable sad sadInner
      setDisposable bd  bdInner

      let allDisposables = mconcat [ toDisposable sad
                                   , toDisposable bd
                                   , disposable ]

      replicateM_ 10 (dispose allDisposables)
      dispose allDisposables

      result0 <- disposeVerbose allDisposables
      assertEqual "disposeVerbose is not idempotent" 3 (disposeCount result0)

      result1 <- fmap sum
                     (mapM (atomically . readTVar)
                           [sadFlag, bdFlag, dispFlag])

      assertEqual "not calling all disposables only once" 3 result1
