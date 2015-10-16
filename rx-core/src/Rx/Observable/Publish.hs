module Rx.Observable.Publish where


import Rx.Disposable (Disposable, dispose, newDisposable, newSingleAssignmentDisposable, setDisposable)
import Rx.Subject (newPublishSubject)
import Rx.Observable.Types

publish :: Observable s a -> IO (ConnectableObservable a)
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

connect :: ConnectableObservable a -> IO Disposable
connect obs = do
  _coConnect obs
  newDisposable "ConnectableObservable" (_coDisconnect obs)
