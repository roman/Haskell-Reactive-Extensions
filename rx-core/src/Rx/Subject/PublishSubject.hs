{-# LANGUAGE DeriveDataTypeable    #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
module Rx.Subject.PublishSubject (
    IObservable (..)
  , IObserver (..)
  , Subject
  , create
  ) where

import Control.Exception (Exception (..), try)
import Control.Monad (forM_, replicateM_)
import Data.Typeable (Typeable)

import Control.Concurrent (yield)
import Control.Concurrent.Async (async, cancelWith)
import Control.Concurrent.STM (atomically)
import Control.Concurrent.STM.TChan (newTChanIO, readTChan, writeTChan)

import qualified Data.HashMap.Strict as HashMap
import qualified Data.Unique         as Unique

import Rx.Disposable (newDisposable)
import Rx.Observable.Types
import qualified Rx.Notification as Notification

--------------------------------------------------------------------------------

data SubjectEvent v
  = OnSubscribe !Int !(Observer v)
  | OnDispose !Int
  | OnEmit !(Notification v)

data SubjectSubscriptionDisposed
  = SubjectSubscriptionDisposed
  deriving (Show, Typeable)

instance Exception SubjectSubscriptionDisposed

--------------------------------------------------------------------------------

create :: IO (Subject v)
create = do
    subjChan <- newTChanIO
    main subjChan
  where
    main subjChan = do
        -- TODO: Make stateMachineAsync a weak pointer, in case
        -- subject's are not being used, the async thread _must_ be
        -- disposed.
        --
        -- QUESTION: Is this truly going to stop of threads being
        -- leaked into memory?
        stateMachineAsync <- async $ stateMachine HashMap.empty
        return $ Subject psSubscribeObserver psEmitNotification stateMachineAsync
      where
        stateMachine subMap = do
          ev <- atomically $ readTChan subjChan
          case ev of
            OnEmit notification -> do
              forM_ (HashMap.elems subMap) $ \(subChan, _) ->
                atomically $ writeTChan subChan notification
              stateMachine subMap

            OnSubscribe subId observer -> do
              subChan  <- newTChanIO
              subAsync <- async $ observerSubscriptionLoop subChan observer
              let subMap' = HashMap.insert subId (subChan, subAsync) subMap
              stateMachine subMap'

            OnDispose subId ->
              case HashMap.lookup subId subMap of
                Nothing -> stateMachine subMap
                Just (_, subAsync) -> do
                  cancelWith subAsync SubjectSubscriptionDisposed
                  let subMap' = HashMap.delete subId subMap
                  stateMachine subMap'

        psSubscribeObserver observer = do
          subId <- Unique.hashUnique <$> Unique.newUnique
          atomically $ writeTChan subjChan (OnSubscribe subId observer)
          newDisposable "PublishSubject.subscribe"
            $ atomically $ writeTChan subjChan (OnDispose subId)

        observerSubscriptionLoop subChan observer = do
          notification <- atomically $ readTChan subChan
          case notification of
            OnNext {} ->
              observerSubscriptionAccept
                observer notification (observerSubscriptionLoop subChan observer)
            _ ->
              observerSubscriptionAccept
                observer notification (return ())

        observerSubscriptionAccept observer notification nextStep = do
          result <- try $ Notification.accept notification observer
          case result of
            Left err -> onError observer err
            Right _  -> nextStep

        psEmitNotification notification = do
          -- NOTE: this yield helps prevent race conditions
          -- when using a Subject of subjects
          replicateM_ 2 yield
          atomically $ writeTChan subjChan (OnEmit notification)
