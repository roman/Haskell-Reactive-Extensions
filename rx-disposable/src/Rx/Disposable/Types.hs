{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Rx.Disposable.Types where

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
  , _subscriptions :: TVar [Disposable]
  }

instance ToDisposable Disposable where
  toDisposable = id


newtype BooleanDisposable
  = BS Disposable
  deriving (ToDisposable)

newtype SingleAssignmentDisposable
  = SAS Disposable
  deriving (ToDisposable)

newtype CompositeDisposable
  = CS Disposable
  deriving (ToDisposable)
