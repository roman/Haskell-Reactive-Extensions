{-# OPTIONS_GHC -fno-warn-orphans #-}
module Rx.Disposable.Disposable
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
  isDisposed (Disposable flag _) = STM.atomically $ TVar.readTVar flag
  isDisposed (CompositeDisposable flag _) = STM.atomically $ TVar.readTVar flag
  isDisposed (DisposableContainer msubVar) = do
    msub <- STM.atomically $ TVar.readTVar msubVar
    case msub of
      Just sub -> isDisposed sub
      Nothing -> return True

  dispose sub@(Disposable flag action) = do
    disposed <- isDisposed sub
    unless disposed $ do
      STM.atomically $ TVar.writeTVar flag True
      action
  dispose (DisposableContainer msubVar) = do
    msub <- STM.atomically $ TVar.readTVar msubVar
    case msub of
      Just sub -> do
        dispose sub
        STM.atomically $ TVar.writeTVar msubVar Nothing
      Nothing -> return ()
  dispose (CompositeDisposable flag msubsVar) = do
    subs <- STM.atomically $ do
      TVar.writeTVar flag True
      TVar.readTVar msubsVar
    mapM_ dispose subs

empty :: IO Disposable
empty =
  Disposable <$> TVar.newTVarIO False <*> pure (return ())

create :: IO () -> IO Disposable
create action =
  Disposable <$> TVar.newTVarIO False <*> pure action
