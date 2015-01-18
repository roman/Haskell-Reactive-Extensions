{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
module Rx.Subject.SyncPublishSubject (
    IObservable (..)
  , IObserver (..)
  , Subject
  , create
  ) where

import Control.Applicative
import Control.Monad (unless)

import Control.Concurrent (yield)
import Control.Concurrent.Async (async)
import Control.Concurrent.STM (atomically)
import Control.Concurrent.STM.TChan (newTChanIO, readTChan, writeTChan)
import Control.Concurrent.STM.TVar (newTVarIO, readTVar, writeTVar)

import qualified Data.HashMap.Strict as HashMap
import qualified Data.Unique         as Unique

import Rx.Disposable (newDisposable, emptyDisposable)
import Rx.Observable.Types
import qualified Rx.Notification as Notification

--------------------------------------------------------------------------------

data SubjectEvent v
  = OnSubscribe !Int !(Observer v)
  | OnDispose !Int
  | OnEmit !(Notification v)

create :: IO (Subject v)
create = do
    subChan <- newTChanIO
    completedVar <- newTVarIO Nothing
    main completedVar subChan
  where
    main completedVar subChan = do
        stateMachineAsync <- async $ stateMachine HashMap.empty
        return $ Subject psSubscribe psEmitNotification stateMachineAsync
      where
        stateMachine subMap = do
          ev <- atomically $ readTChan subChan
          case ev of
            OnEmit OnCompleted -> do
              mapM_ (Notification.accept OnCompleted)
                    (HashMap.elems subMap)
              atomically $ writeTVar completedVar (Just $ Right ())

            OnEmit notification@(OnError err) -> do
              mapM (Notification.accept notification)
                   (HashMap.elems subMap) 
              atomically $ writeTVar completedVar (Just $ Left err)

            OnEmit notification -> do
              mapM_ (Notification.accept notification)
                    (HashMap.elems subMap)
              stateMachine subMap

            OnSubscribe subId observer -> do
              let subMap' = HashMap.insert subId observer subMap
              stateMachine subMap'

            OnDispose subId -> do
              let subMap' = HashMap.delete subId subMap
              stateMachine subMap'

        psSubscribe observer = do
          wasCompleted <- atomically $ readTVar completedVar
          case wasCompleted of
             Nothing -> do
                subId <- Unique.hashUnique <$> Unique.newUnique
                atomically $ writeTChan subChan (OnSubscribe subId observer)
                newDisposable "SyncPublishSubject.subscribe"
                  $ atomically
                  $ writeTChan subChan (OnDispose subId)

             Just (Left err) -> do
               onError observer err
               emptyDisposable

             Just (Right {}) -> do
               onCompleted observer
               emptyDisposable

        psEmitNotification notification = do
          yield
          wasCompleted <- atomically $ readTVar completedVar
          case wasCompleted of
            Nothing -> atomically $ writeTChan subChan (OnEmit notification)
            _ -> return ()
            
