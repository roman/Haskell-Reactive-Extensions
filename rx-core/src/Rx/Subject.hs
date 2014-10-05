module Rx.Subject
       ( Subject
       , newPublishSubject
       , Single.newSingleSubject
       , Single.newSingleSubjectWithQueue
       , IObserver(..)
       , ToAsyncObservable(..)
       , subscribe )
       where

import Rx.Observable.Types
import qualified Rx.Subject.PublishSubject as Publish
import qualified Rx.Subject.SingleSubject  as Single

newPublishSubject :: IO (Subject v)
newPublishSubject = Publish.create
