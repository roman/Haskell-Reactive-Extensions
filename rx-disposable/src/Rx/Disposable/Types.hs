{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Rx.Disposable.Types where

import Data.Typeable (Typeable)

import Control.Concurrent.STM (TVar)

class IDisposable a where
  dispose :: a -> IO ()
  isDisposed :: a -> IO Bool

class ToDisposable s where
  toDisposable :: s -> Disposable

data Disposable
  = Disposable {
    _isDisposed :: TVar Bool
  , _dispose    :: IO ()
  }
  | DisposableContainer {
    _currentDisposable :: TVar (Maybe Disposable)
  }
  | CompositeDisposable {
    _isDisposed    :: TVar Bool
  , _disposables :: TVar [Disposable]
  }
  deriving (Typeable)

instance ToDisposable Disposable where
  toDisposable = id


newtype BooleanDisposable
  = BD Disposable
  deriving (ToDisposable, Typeable)

newtype SingleAssignmentDisposable
  = SAD Disposable
  deriving (ToDisposable, Typeable)

newtype CompositeDisposable
  = CD Disposable
  deriving (ToDisposable, Typeable)
