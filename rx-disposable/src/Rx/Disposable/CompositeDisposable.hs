{-# OPTIONS_GHC -fno-warn-orphans #-}
module Rx.Disposable.CompositeDisposable
       ( module Rx.Disposable.CompositeDisposable
       , toDisposable ) where

import Control.Applicative

import qualified Control.Concurrent.STM      as STM
import qualified Control.Concurrent.STM.TVar as TVar

import Rx.Disposable.Internal ()
import Rx.Disposable.Types

create :: IO CompositeDisposable
create = do
  cs <- CompositeDisposable <$> TVar.newTVarIO False
                            <*> TVar.newTVarIO []
  return $ CD cs

append :: Disposable -> CompositeDisposable -> IO ()
append s (CD cs) =
  STM.atomically $ TVar.modifyTVar (_disposables cs) (s:)

instance IDisposable CompositeDisposable where
  isDisposed = isDisposed . toDisposable
  dispose = dispose . toDisposable
