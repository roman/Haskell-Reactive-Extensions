module Rx.Subject.SingleSubject (
    IObservable (..)
  , IObserver (..)
  , Subject
  , newSingleSubject
  , newSingleSubjectWithQueue
  ) where

import Control.Monad (when)

import Control.Concurrent.Async (async)
import Control.Concurrent.STM (atomically)
import qualified Control.Concurrent.STM.TQueue as TQueue
import qualified Control.Concurrent.STM.TVar   as TVar

import Rx.Disposable (newDisposable, emptyDisposable)
import Rx.Observable.Types
import qualified Rx.Notification as Notification

--------------------------------------------------------------------------------

_newSingleSubject :: Bool -> IO (Subject v)
_newSingleSubject queueOnEmpty = do
    observerVar <- TVar.newTVarIO Nothing
    completedVar <- TVar.newTVarIO False
    notificationQueue <- TQueue.newTQueueIO
    main observerVar completedVar notificationQueue
  where
    main observerVar completedVar notificationQueue = do
        stateMachineAsync <- async $ return ()
        return $ Subject singleSubscribe singleEmitNotification stateMachineAsync
      where
        emitQueuedNotifications observer = when queueOnEmpty $ do
          result <-
            atomically $ TQueue.tryReadTQueue notificationQueue
          case result of
            Just notification -> do
              Notification.accept notification observer
              emitQueuedNotifications observer
            Nothing -> return ()

        acceptNotification notification = do
          result <- atomically $ TVar.readTVar observerVar
          case result of
            Nothing
              | queueOnEmpty ->
                  atomically $
                    TQueue.writeTQueue notificationQueue notification
              | otherwise -> return ()
            Just observer ->
              Notification.accept notification observer

        singleSubscribe observer = do
           completed <- atomically $ TVar.readTVar completedVar
           if completed
             then do
               Notification.accept OnCompleted observer
               emptyDisposable
             else do
               prevObserver <- atomically $ TVar.readTVar observerVar
               maybe (emitQueuedNotifications observer) onCompleted prevObserver
               atomically
                 $ TVar.modifyTVar observerVar (const $ Just observer)
               newDisposable "SingleSubject.subscribe"
                 $ atomically
                 $ TVar.writeTVar observerVar Nothing

        singleEmitNotification (OnError err) = do
          atomically $ TVar.writeTVar completedVar True
          acceptNotification $ OnError err

        singleEmitNotification OnCompleted = do
          atomically $ TVar.writeTVar completedVar True
          acceptNotification OnCompleted

        singleEmitNotification notification =
          acceptNotification notification

--------------------------------------------------------------------------------

newSingleSubject :: IO (Subject v)
newSingleSubject = _newSingleSubject False

newSingleSubjectWithQueue :: IO (Subject v)
newSingleSubjectWithQueue = _newSingleSubject True
