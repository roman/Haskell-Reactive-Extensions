{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE NoImplicitPrelude          #-}
module Rx.Disposable
       ( emptyDisposable
       , dispose
       , disposeCount
       , disposeErrorCount
       , disposeErrorList
       , disposeActionList
       , wrapDisposable
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

import           Prelude.Compat

import           Control.Exception       (SomeException, try)
import           Control.Monad           (liftM, void)
import           Data.Monoid             ((<>))
import           Data.Typeable           (Typeable)

import           Control.Concurrent.MVar (MVar, modifyMVar, newMVar, putMVar,
                                          readMVar, swapMVar, takeMVar)

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
  disposeVerbose :: d -> IO DisposeResult

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
  disposeVerbose (Disposable actions) =
    mconcat `fmap` sequence actions

instance ToDisposable Disposable where
  toDisposable = id

--------------------

instance IDisposable BooleanDisposable where
  disposeVerbose (BooleanDisposable disposableVar) = do
    disposable <- readMVar disposableVar
    disposeVerbose disposable

instance ToDisposable BooleanDisposable where
  toDisposable booleanDisposable  =
    Disposable [disposeVerbose booleanDisposable]

instance SetDisposable BooleanDisposable where
  setDisposable (BooleanDisposable currentVar) disposable = do
    oldDisposable <- swapMVar currentVar disposable
    void $ disposeVerbose oldDisposable

--------------------

instance IDisposable SingleAssignmentDisposable where
  disposeVerbose (SingleAssignmentDisposable disposableVar) = do
    mdisposable <- readMVar disposableVar
    maybe (return mempty) disposeVerbose mdisposable

instance ToDisposable SingleAssignmentDisposable where
  toDisposable singleAssignmentDisposable =
    Disposable [disposeVerbose singleAssignmentDisposable]

instance SetDisposable SingleAssignmentDisposable where
  setDisposable (SingleAssignmentDisposable disposableVar) disposable = do
    mdisposable <- takeMVar disposableVar
    case mdisposable of
      Nothing -> putMVar disposableVar (Just disposable)
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
dispose = void . disposeVerbose
{-# INLINE dispose #-}

emptyDisposable :: IO Disposable
emptyDisposable = return mempty
{-# INLINE emptyDisposable #-}

newDisposable :: DisposableDescription -> IO () -> IO Disposable
newDisposable desc disposingAction = do
  disposeResultVar <- newMVar Nothing
  return $ Disposable
    [modifyMVar disposeResultVar $ \disposeResult ->
      case disposeResult of
        Just result -> return (Just result, result)
        Nothing ->  do
          disposingResult <- try disposingAction
          let result = DisposeResult [(desc, either Just (const Nothing) disposingResult)]
          return (Just result, result)]

wrapDisposable :: DisposableDescription -> IO Disposable -> IO Disposable
wrapDisposable desc getDisposable = do
  disposeResultVar <- newMVar Nothing
  return $ Disposable
    [modifyMVar disposeResultVar $ \disposeResult ->
      case disposeResult of
        Just result -> return (Just result, result)
        Nothing ->  do
          disposable <- getDisposable
          innerResult <- disposeVerbose disposable
          let result = DisposeResult
                        $ map (\(innerDesc, outcome) -> (desc <> " | " <> innerDesc, outcome))
                              (fromDisposeResult innerResult)
          return (Just result, result)]
{-# INLINE wrapDisposable #-}

newBooleanDisposable :: IO BooleanDisposable
newBooleanDisposable =
  liftM BooleanDisposable (newMVar mempty)
{-# INLINE newBooleanDisposable #-}

newSingleAssignmentDisposable :: IO SingleAssignmentDisposable
newSingleAssignmentDisposable =
  liftM SingleAssignmentDisposable (newMVar Nothing)
{-# INLINE newSingleAssignmentDisposable #-}
