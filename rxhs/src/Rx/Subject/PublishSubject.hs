{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
module Rx.Subject.PublishSubject (
    IObservable (..)
  , IObserver (..)
  , Subject
  , create
  ) where

import Control.Applicative

import Control.Concurrent.STM (atomically)
import qualified Control.Concurrent.STM.TVar as TVar

import qualified Data.HashMap.Strict as HashMap
import qualified Data.Unique         as Unique

import qualified Rx.Disposable as Disposable
import qualified Rx.Notification          as Notification
import           Rx.Observable.Types

--------------------------------------------------------------------------------

create :: IO (Subject v)
create = do
    subscriptionsVar <- TVar.newTVarIO HashMap.empty
    completedVar <- TVar.newTVarIO False
    main subscriptionsVar completedVar
  where
    main subscriptionsVar completedVar =
        return $ Subject psSubscribe psEmitNotification
      where
        getCompleted = atomically $ TVar.readTVar completedVar
        getDisposables =  atomically $ TVar.readTVar subscriptionsVar
        psSubscribe observer = do
          completed <- getCompleted
          if completed
            then do
              Notification.accept OnCompleted observer
              Disposable.emptyDisposable
            else do
              subscriptionId <- Unique.hashUnique <$> Unique.newUnique
              disposable <- Disposable.createDisposable $
                atomically $ TVar.modifyTVar subscriptionsVar
                                            (HashMap.delete subscriptionId)

              atomically $ TVar.modifyTVar subscriptionsVar
                                           (HashMap.insert subscriptionId observer)

              return disposable


        psEmitNotification notification = do
          subscriptions <- getDisposables
          mapM_ (Notification.accept notification)
                (HashMap.elems subscriptions)
