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

import Control.Concurrent.Async (async)
import Control.Concurrent.STM (atomically)
import Control.Concurrent.STM.TChan (newTChanIO, readTChan, writeTChan)

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
    main subChan
  where
    main subChan = do
        stateMachineAsync <- async $ stateMachine HashMap.empty
        return $ Subject psSubscribe psEmitNotification stateMachineAsync
      where
        stateMachine subMap = do
          ev <- atomically $ readTChan subChan
          case ev of
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
          subId <- Unique.hashUnique <$> Unique.newUnique
          atomically $ writeTChan subChan (OnSubscribe subId observer)
          newDisposable "SyncPublishSubject.subscribe"
            $ atomically $ writeTChan subChan (OnDispose subId)

        psEmitNotification notification =
          atomically $ writeTChan subChan (OnEmit notification)
