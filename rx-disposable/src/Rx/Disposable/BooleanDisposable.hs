{-# OPTIONS_GHC -fno-warn-orphans #-}
module Rx.Disposable.BooleanDisposable
       ( module Rx.Disposable.BooleanDisposable
       , toDisposable ) where

import           Control.Applicative
import qualified Control.Concurrent.STM      as STM
import qualified Control.Concurrent.STM.TVar as TVar
import           Rx.Disposable.Disposable    ()
import           Rx.Disposable.Types

instance IDisposable BooleanDisposable where
  isDisposed = isDisposed . toDisposable
  dispose = dispose . toDisposable

empty :: IO BooleanDisposable
empty =
  (BS . DisposableContainer) <$> TVar.newTVarIO Nothing

null :: BooleanDisposable -> IO Bool
null sub =
  get sub >>=  maybe (return False) (const $ return True)

create :: Disposable -> IO BooleanDisposable
create sub =
  (BS . DisposableContainer) <$> TVar.newTVarIO (Just sub)

set :: Disposable -> BooleanDisposable -> IO ()
set sub (BS (DisposableContainer msubVar)) = do
  msub <- STM.atomically $ TVar.readTVar msubVar
  case msub of
    Nothing -> STM.atomically $ TVar.writeTVar msubVar (Just sub)
    Just prevSub -> do
      dispose prevSub
      STM.atomically $ TVar.writeTVar msubVar (Just sub)
set _ _ = error "Invalid BooleanDisposable created!"

get :: BooleanDisposable -> IO (Maybe Disposable)
get (BS (DisposableContainer msubVar)) =
  STM.atomically $ TVar.readTVar msubVar
get _ = error "Invalid BooleanDisposable created!"

clear :: BooleanDisposable -> IO ()
clear sub@(BS (DisposableContainer msubVar)) = do
  dispose sub
  STM.atomically $ TVar.writeTVar msubVar Nothing
clear _ = error "Invalid BooleanDisposable created!"
