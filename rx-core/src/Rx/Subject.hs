module Rx.Subject
       ( Subject
       , newPublishSubject
       , newSyncPublishSubject
       , Single.newSingleSubject
       , Single.newSingleSubjectWithQueue
       , IObserver(..)
       , ToAsyncObservable(..)
       , subscribe )
       where

import Rx.Observable.Types
import qualified Rx.Subject.PublishSubject as Publish
import qualified Rx.Subject.SyncPublishSubject as SyncPublish
import qualified Rx.Subject.SingleSubject  as Single

newPublishSubject :: IO (Subject v)
newPublishSubject = Publish.create

newSyncPublishSubject :: IO (Subject v)
newSyncPublishSubject = SyncPublish.create
