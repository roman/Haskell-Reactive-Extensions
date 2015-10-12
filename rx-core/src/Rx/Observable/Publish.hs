module Rx.Observable.Publish where


import Rx.Disposable (dispose, newSingleAssignmentDisposable, setDisposable)
import Rx.Subject (newPublishSubject)
import Rx.Scheduler (Sync)
import Rx.Observable.Types

publish :: Observable Sync a -> IO (ConnectableObservable a)
publish source = do
    sourceDisposable <- newSingleAssignmentDisposable
    subject <- newPublishSubject
    let observable = toAsyncObservable subject
    return (ConnectableObservable (subscribeObserver observable)
                                  (connect_ subject sourceDisposable)
                                  (dispose sourceDisposable))
  where
    connect_ subject sourceDisposable = do
      disposable <- subscribeObserver source subject
      setDisposable sourceDisposable disposable

connect :: ConnectableObservable a -> IO ()
connect = _coConnect
