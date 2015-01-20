{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
module Rx.Disposable
       ( emptyDisposable
       , dispose
       , disposeCount
       , disposeErrorCount
       , disposeErrorList
       , disposeActionList
       , newDisposable
       , newBooleanDisposable
       , newSingleAssignmentDisposable
       , BooleanDisposable
       , Disposable
       , SingleAssignmentDisposable
       , SetDisposable(..)
       , ToDisposable(..)
       , IDisposable(..)
       , DisposeResult
       ) where

import Control.Exception (SomeException, try)
import Control.Monad (void)
import Data.Monoid (Monoid (..))
import Data.Typeable (Typeable)

import Control.Concurrent.MVar (MVar, modifyMVar, newMVar, putMVar, readMVar,
                                swapMVar, takeMVar)

--------------------------------------------------------------------------------

type DisposableDescription = String

newtype DisposeResult
  = DisposeResult { fromDisposeResult :: [(DisposableDescription, Maybe SomeException)] }
  deriving (Show, Typeable)

newtype Disposable
  = Disposable [IO DisposeResult]
  deriving (Typeable)

newtype BooleanDisposable
  = BooleanDisposable (MVar Disposable)
  deriving (Typeable)

newtype SingleAssignmentDisposable
  = SingleAssignmentDisposable (MVar (Maybe Disposable))
  deriving (Typeable)

--------------------------------------------------------------------------------

class IDisposable d where
  disposeWithResult :: d -> IO DisposeResult

class ToDisposable d where
  toDisposable :: d -> Disposable

class SetDisposable d where
  setDisposable ::  d -> Disposable -> IO ()

--------------------------------------------------------------------------------

instance Monoid DisposeResult where
  mempty = DisposeResult []
  (DisposeResult as) `mappend` (DisposeResult bs) =
    DisposeResult $ as ++ bs

--------------------

instance Monoid Disposable where
  mempty  = Disposable []
  (Disposable as) `mappend` (Disposable bs) =
    Disposable (as ++ bs)

instance IDisposable Disposable where
  disposeWithResult (Disposable actions) =
    mconcat `fmap` sequence actions

instance ToDisposable Disposable where
  toDisposable = id

--------------------

instance IDisposable BooleanDisposable where
  disposeWithResult (BooleanDisposable disposableVar) = do
    disposable <- readMVar disposableVar
    disposeWithResult disposable

instance ToDisposable BooleanDisposable where
  toDisposable booleanDisposable  =
    Disposable [disposeWithResult booleanDisposable]

instance SetDisposable BooleanDisposable where
  setDisposable (BooleanDisposable currentVar) disposable = do
    oldDisposable <- swapMVar currentVar disposable
    void $ disposeWithResult oldDisposable

-- --------------------

instance IDisposable SingleAssignmentDisposable where
  disposeWithResult (SingleAssignmentDisposable disposableVar) = do
    mdisposable <- readMVar disposableVar
    maybe (return mempty) disposeWithResult mdisposable

instance ToDisposable SingleAssignmentDisposable where
  toDisposable singleAssignmentDisposable =
    Disposable [disposeWithResult singleAssignmentDisposable]

instance SetDisposable SingleAssignmentDisposable where
  setDisposable (SingleAssignmentDisposable disposableVar) disposable = do
    mdisposable <- takeMVar disposableVar
    case mdisposable of
      Nothing -> putMVar disposableVar $ Just disposable
      Just _  -> error $ "ERROR: called 'setDisposable' more " ++
                         "than once on SingleAssignmentDisposable"

--------------------------------------------------------------------------------

disposeErrorList :: DisposeResult -> [(DisposableDescription, SomeException)]
disposeErrorList = foldr accJust [] . fromDisposeResult
  where
    accJust (_, Nothing) acc = acc
    accJust (desc, Just err) acc = (desc, err) : acc
{-# INLINE disposeErrorList #-}

disposeActionList :: DisposeResult -> [(DisposableDescription, Maybe SomeException)]    
disposeActionList = fromDisposeResult
{-# INLINE disposeActionList #-}

disposeCount :: DisposeResult -> Int
disposeCount = length . fromDisposeResult
{-# INLINE disposeCount #-}

disposeErrorCount :: DisposeResult -> Int
disposeErrorCount = length . disposeErrorList
{-# INLINE disposeErrorCount #-}

--------------------
  
dispose :: IDisposable disposable => disposable -> IO ()
dispose = void . disposeWithResult
{-# INLINE dispose #-}

emptyDisposable :: IO Disposable
emptyDisposable = return mempty
{-# INLINE emptyDisposable #-}

newDisposable :: DisposableDescription -> IO () -> IO Disposable
newDisposable desc disposingAction = do
  disposeResultVar <- newMVar Nothing
  return $ Disposable $
    [modifyMVar disposeResultVar $ \disposeResult ->
      case disposeResult of
        Just result -> return (Just result, result)
        Nothing ->  do
          disposingResult <- try disposingAction
          let result = DisposeResult [(desc, either Just (const Nothing) disposingResult)]
          return (Just result, result)]
{-# INLINE newDisposable #-}

newBooleanDisposable :: IO BooleanDisposable
newBooleanDisposable = do
  newMVar mempty >>= return . BooleanDisposable
{-# INLINE newBooleanDisposable #-}

newSingleAssignmentDisposable :: IO SingleAssignmentDisposable
newSingleAssignmentDisposable = do
  newMVar Nothing >>= return . SingleAssignmentDisposable
{-# INLINE newSingleAssignmentDisposable #-}
