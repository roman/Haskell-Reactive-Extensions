{-# OPTIONS_GHC -fno-warn-orphans #-}
module Rx.Disposable.Internal
       ( Disposable
       , empty
       , create
       , toDisposable ) where

import Control.Applicative hiding (empty)
import Control.Monad (unless)

import qualified Control.Concurrent.STM      as STM
import qualified Control.Concurrent.STM.TVar as TVar

import Rx.Disposable.Types

instance IDisposable Disposable where
  isDisposed (Disposable flag _) =
    STM.atomically $ TVar.readTVar flag

  isDisposed (CompositeDisposable flag _) =
    STM.atomically $ TVar.readTVar flag

  isDisposed (DisposableContainer disposableVar) = do
    mdisp <- STM.atomically $ TVar.readTVar disposableVar
    case mdisp of
      Just disposable -> isDisposed disposable
      Nothing -> return False

  dispose disp@(Disposable flag action) = do
    disposed <- isDisposed disp
    unless disposed $ do
      STM.atomically $ TVar.writeTVar flag True
      action

  dispose (DisposableContainer disposableVar) = do
    mdisp <- STM.atomically $ TVar.readTVar disposableVar
    case mdisp of
      Just disposable -> do
        dispose disposable
        STM.atomically $ TVar.writeTVar disposableVar Nothing
      Nothing -> return ()

  dispose disp@(CompositeDisposable flag disposablesVar) = do
    disposed <- isDisposed disp
    unless disposed $ do
      disposables <- STM.atomically $ do
        TVar.writeTVar flag True
        TVar.readTVar disposablesVar
      mapM_ dispose disposables

empty :: IO Disposable
empty =
  Disposable <$> TVar.newTVarIO False <*> pure (return ())

create :: IO () -> IO Disposable
create action =
  Disposable <$> TVar.newTVarIO False <*> pure action
