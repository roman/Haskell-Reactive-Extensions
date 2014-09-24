module Rx.Subject
       ( Subject
       , newPublishSubject
       , Single.newSingleSubject
       , Single.newSingleSubjectWithQueue
       , IObserver(..)
       , subscribe )
       where

import qualified Rx.Subject.SingleSubject as Single
import qualified Rx.Subject.PublishSubject as Publish
import Rx.Observable.Types

newPublishSubject :: IO (Subject v)
newPublishSubject = Publish.create
