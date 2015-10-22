{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE NoImplicitPrelude          #-}
module Rx.Disposable
       ( emptyDisposable
       , dispose
       , disposeCount
       , disposeErrorCount
       , newDisposable
       , newBooleanDisposable
       , newSingleAssignmentDisposable
       , toList
       , wrapDisposable
       , wrapDisposableIO
       , BooleanDisposable
       , Disposable
       , SingleAssignmentDisposable
       , SetDisposable (..)
       , ToDisposable (..)
       , IDisposable (..)
       , DisposeResult
       ) where

import           Prelude.Compat

import           Control.Arrow (first)
import           Control.Exception       (SomeException, try)
import           Control.Monad           (liftM, void)
-- import           Data.List               (foldl')
import           Data.Typeable           (Typeable)

import           Control.Concurrent.MVar (MVar, modifyMVar, newMVar, putMVar,
                                          readMVar, swapMVar, takeMVar)

--------------------------------------------------------------------------------

type DisposableDescription = String

data DisposeResult
  = DisposeBranch DisposableDescription DisposeResult
  | DisposeLeaf   DisposableDescription (Maybe SomeException)
  | DisposeResult [DisposeResult]
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
    DisposeResult (as `mappend` bs)
  a@(DisposeResult coll) `mappend` b = DisposeResult (coll ++ [b])
  a `mappend` b@(DisposeResult coll) = DisposeResult (a:coll)
  a `mappend` b = DisposeResult [a, b]

--------------------

instance Monoid Disposable where
  mempty  = Disposable []
  (Disposable as) `mappend` (Disposable bs) =
    Disposable (as `mappend` bs)

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

foldDisposeResult
  :: (DisposableDescription -> Maybe SomeException -> acc -> acc)
    -> (DisposableDescription -> acc -> acc)
    -> ([acc] -> acc)
    -> acc
    -> DisposeResult
    -> acc
foldDisposeResult fLeaf _ _ acc (DisposeLeaf desc mErr) = fLeaf desc mErr acc
foldDisposeResult fLeaf fBranch fList acc (DisposeBranch desc disposeResult) =
  fBranch desc (foldDisposeResult fLeaf fBranch fList acc disposeResult)
foldDisposeResult fLeaf fBranch fList acc (DisposeResult ds) =
  let acc1 = map (foldDisposeResult fLeaf fBranch fList acc) ds
  in fList acc1

disposeCount :: DisposeResult -> Int
disposeCount =
  foldDisposeResult (\_ _ acc -> acc + 1)
                    (const id)
                    sum
                    0
{-# INLINE disposeCount #-}

disposeErrorCount :: DisposeResult -> Int
disposeErrorCount =
  foldDisposeResult (\_ mErr acc -> acc + maybe 0 (const 1) mErr)
                    (const id)
                    sum
                    0
{-# INLINE disposeErrorCount #-}

toList
  :: DisposeResult
     -> [([DisposableDescription], Maybe SomeException)]
toList =
  foldDisposeResult (\desc res acc -> (([desc], res) : acc))
                    (\desc acc -> map (first (desc :)) acc)
                    concat
                    []

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
          let result = DisposeLeaf desc (either Just (const Nothing) disposingResult)
          return (Just result, result)]

wrapDisposableIO
  :: DisposableDescription
     -> IO Disposable
     -> IO Disposable
wrapDisposableIO desc getDisposable = do
  disposeResultVar <- newMVar Nothing
  return $ Disposable
    [modifyMVar disposeResultVar $ \disposeResult ->
      case disposeResult of
        Just result -> return (Just result, result)
        Nothing ->  do
          disposable  <- getDisposable
          innerResult <- disposeVerbose disposable
          let result = DisposeBranch desc innerResult
          return (Just result, result)]
{-# INLINE wrapDisposableIO #-}

wrapDisposable :: DisposableDescription -> Disposable -> IO Disposable
wrapDisposable desc = wrapDisposableIO desc . return
{-# INLINE wrapDisposable #-}

newBooleanDisposable :: IO BooleanDisposable
newBooleanDisposable =
  liftM BooleanDisposable (newMVar mempty)
{-# INLINE newBooleanDisposable #-}

newSingleAssignmentDisposable :: IO SingleAssignmentDisposable
newSingleAssignmentDisposable =
  liftM SingleAssignmentDisposable (newMVar Nothing)
{-# INLINE newSingleAssignmentDisposable #-}
