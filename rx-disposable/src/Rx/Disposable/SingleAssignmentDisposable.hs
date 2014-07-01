{-# LANGUAGE RankNTypes #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module Rx.Disposable.SingleAssignmentDisposable
       ( module Rx.Disposable.SingleAssignmentDisposable
       , toDisposable ) where

import Control.Applicative

import qualified Control.Concurrent.STM      as STM
import qualified Control.Concurrent.STM.TVar as TVar

import Rx.Disposable.Disposable ()
import Rx.Disposable.Types

empty :: IO SingleAssignmentDisposable
empty =
  (SAS . DisposableContainer) <$> TVar.newTVarIO Nothing

create :: Disposable -> IO SingleAssignmentDisposable
create sub =
  (SAS . DisposableContainer) <$> TVar.newTVarIO (Just sub)

set :: Disposable -> SingleAssignmentDisposable -> IO ()
set sub (SAS (DisposableContainer msubVar)) = do
  msub <- STM.atomically $ TVar.readTVar msubVar
  case msub of
    Just _ -> error "Disposable already set"
    Nothing -> STM.atomically $ TVar.writeTVar msubVar (Just sub)
set _ _ = error "Invalid SingleAssignmentDisposable was created"

get :: SingleAssignmentDisposable -> IO (Maybe Disposable)
get (SAS (DisposableContainer msubVar)) =
  STM.atomically $ TVar.readTVar msubVar
get _ = error "Invalid SingleAssignmentDisposable was created"


instance IDisposable SingleAssignmentDisposable where
  isDisposed = isDisposed . toDisposable
  dispose = dispose . toDisposable
