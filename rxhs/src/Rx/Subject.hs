module Rx.Subject
       ( Subject
       , newPublishSubject
       , IObserver(..)
       , subscribe )
       where

import qualified Rx.Subject.PublishSubject as Publish
import Rx.Observable.Types

newPublishSubject :: IO (Subject v)
newPublishSubject = Publish.create
