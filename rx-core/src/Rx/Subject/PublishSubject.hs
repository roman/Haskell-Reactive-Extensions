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

import Control.Applicative
import Control.Exception (Exception (..), try)
import Control.Monad (forM_, replicateM_, unless, void)
import Data.Typeable (Typeable)

import Control.Concurrent (yield)
import Control.Concurrent.Async (async, cancelWith)
import Control.Concurrent.STM (atomically)
import Control.Concurrent.STM.TChan (newTChanIO, readTChan, writeTChan)
import Control.Concurrent.STM.TVar (newTVarIO, readTVar)

import qualified Data.HashMap.Strict as HashMap
import qualified Data.Unique         as Unique

import Rx.Disposable (createDisposable, emptyDisposable)
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
    completedVar <- newTVarIO False
    main completedVar subjChan
  where
    main completedVar subjChan = do
        -- TODO: Make stateMachineAsync a weak pointer, in case
        -- subject's are not being used, the async thread _must_ be
        -- disposed.
        --
        -- QUESTION: Is this truly going to stop of threads being
        -- leaked into memory?
        stateMachineAsync <- async $ stateMachine False HashMap.empty
        return $ Subject psSubscribeObserver psEmitNotification stateMachineAsync
      where
        stateMachine wasCompleted subMap = do
          ev <- atomically $ readTChan subjChan
          case ev of
            OnEmit notification@OnCompleted -> unless wasCompleted $ do
              forM_ (HashMap.elems subMap) $ \(subChan, _) ->
                atomically $ writeTChan subChan notification
              stateMachine True subMap

            OnEmit notification -> unless wasCompleted $ do
              forM_ (HashMap.elems subMap) $ \(subChan, _) ->
                atomically $ writeTChan subChan notification
              stateMachine wasCompleted subMap

            OnSubscribe subId observer -> do
              if wasCompleted
                then void
                     $ async
                     $ observerSubscriptionAccept observer OnCompleted (return ())
                else do
                  subChan  <- newTChanIO
                  subAsync <- async $ observerSubscriptionLoop subChan observer
                  let subMap' =
                        HashMap.insert subId (subChan, subAsync) subMap
                  stateMachine wasCompleted subMap'

            OnDispose subId ->
              case HashMap.lookup subId subMap of
                Nothing -> stateMachine wasCompleted subMap
                Just (_, subAsync) -> do
                  cancelWith subAsync SubjectSubscriptionDisposed
                  let subMap' = HashMap.delete subId subMap
                  stateMachine wasCompleted subMap'

        psSubscribeObserver observer = do
          wasCompleted <- atomically $ readTVar completedVar
          if wasCompleted
            then do
              onCompleted observer
              emptyDisposable
            else do
              subId <- Unique.hashUnique <$> Unique.newUnique
              atomically $ writeTChan subjChan (OnSubscribe subId observer)
              createDisposable
                $ atomically
                $ writeTChan subjChan (OnDispose subId)

        observerSubscriptionLoop subChan observer = do
          notification <- atomically $ readTChan subChan
          case notification of
            OnNext {} -> do
              observerSubscriptionAccept
                observer notification (observerSubscriptionLoop subChan observer)
            _ -> do
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
          wasCompleted <- atomically $ readTVar completedVar
          unless wasCompleted
            $ atomically
            $ writeTChan subjChan (OnEmit notification)
