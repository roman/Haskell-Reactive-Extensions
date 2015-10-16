{-# LANGUAGE NoImplicitPrelude #-}
module Rx.Observable.Publish where

import           Prelude.Compat

import           Rx.Disposable       (Disposable, dispose,
                                      newSingleAssignmentDisposable,
                                      setDisposable, toDisposable,
                                      wrapDisposable)
import           Rx.Observable.Types
import           Rx.Subject          (newPublishSubject)

publish :: Observable s a -> IO (ConnectableObservable a)
publish source = do
    sourceDisposable <- newSingleAssignmentDisposable
    subject <- newPublishSubject
    let observable = toAsyncObservable subject
    return (ConnectableObservable (subscribeObserver observable)
                                  (connect_ subject sourceDisposable)
                                  (toDisposable sourceDisposable))
  where
    connect_ subject sourceDisposable = do
      disposable <- subscribeObserver source (toObserver subject)
      setDisposable sourceDisposable disposable

connect :: ConnectableObservable a -> IO Disposable
connect obs = do
  _coConnect obs
  wrapDisposable "ConnectableObservable" (_coDisconnect obs)
