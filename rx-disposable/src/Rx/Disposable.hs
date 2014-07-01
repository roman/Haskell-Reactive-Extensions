-- Module: Rx.Disposable
-- Copyright: (c) 2014 Roman Gonzalez
-- (c) 2014 Birdseye Software, Inc.
-- License: MIT
{-|

Disposables are an approach to manage a one time cleanup of resources
by composing them together with various primitives. This library
provides 4 different kind of Disposables:

* @Disposable@
* @BooleanDisposable@
* @SingleAssignmentDisposable@
* @CompositeDisposable@

All of them implement a common classtype @IDisposable@ which responsability
is to provide a @dispose@ function. This function will perform a cleanup
@IO@ action when called. Let's get started with the _raison-d'etre_ of each
@Disposable@ type:


* @Disposable@

This is the most common (and general) type of @IDisposable@, it
contains an @IO@ action that is executed when @dispose@ is called on
it. There are three different ways to create values of this type:

  - @createDisposable@ - receives an IO action and returns a @Disposable@
  - @emptyDisposable@ - returns a @Disposable@ that does nothing
  - @toDisposable@ - transforms any other @IDisposable@ into a @Disposable@


* @BooleanDisposable@

Serves as a wrapper of a common @Disposable@, it can hold one
@Disposable@ at a time, which can be replaced many times, however,
each time a new inner @Disposable@ is set, the old one is disposed
immediately. This serves useful when an action is done by many
entities that produce a Disposable, but there is only one working at a
time. There are 3 functions related to this type:

  - @newBooleanDisposable@ - creates an empty @BooleanDisposable@
  - @set@ - Sets a new @Disposable@ as the wrapped disposable
  - @get@ - Returns the original wrapped @Disposable@

* @SingleAssignmentDisposable@

A wrapper @IDisposable@ as the @BooleanDisposable@, it's main
difference is that it allows the @set@ function to be called only
once. This type is very useful when the disposable reference is needed
from an async Observable, so that the Observable can dispose itself on
certain conditions. There are 3 functions related to this type:

  - @newSingleAssignmentDisposable@ - creates an empty @SingleAssignmentDisposable@
  - @set@ - Sets a new @Disposable@ as the wrapped disposable. This can be
            called only once.
  - @get@ - Returns the original wrapped @Disposable@

* @CompositeDisposable@

As it's name suggest, this @IDisposable@ holds a collection of
@Disposable@ records internally. When @dispose@ is called on it all
its @Disposable@ children are cleaned up. The order in which they are
disposed is in the same order they were appended to the
@CompositeDisposable@. There are 2 functions related to this type:

  - @newCompositeDisposable@ - creates an empty @CompositeDisposable@
  - @append@ - Appends a new @Disposable@ to the disposable children list


-}
module Rx.Disposable
       ( IDisposable(..)
       , ToDisposable(..)
       , Disposable
       , SingleAssignmentDisposable
       , CompositeDisposable
       , BooleanDisposable
       , append
       , createDisposable
       , emptyDisposable
       , get
       , newSingleAssignmentDisposable
       , newCompositeDisposable
       , newBooleanDisposable
       , set
       , toDisposable
       ) where

import qualified Rx.Disposable.BooleanDisposable          as BD
import qualified Rx.Disposable.CompositeDisposable        as CD
import qualified Rx.Disposable.Disposable                 as D
import qualified Rx.Disposable.SingleAssignmentDisposable as SAD

import Rx.Disposable.Types

--------------------------------------------------------------------------------

class IDisposableWrapper d where
  -- | Sets inner @Disposable@ on the type implemeting @IDisposableWrapper@
  set :: ToDisposable d0 => d0 -> d -> IO ()
  -- | Gets inner @Disposable@ on the type implemeting @IDisposableWrapper@
  get :: d -> IO (Maybe Disposable)

class IDisposableContainer d where
  -- | Append a @Disposable@ to the @Disposable@ children list
  append :: ToDisposable d0 => d0 -> d -> IO ()

--------------------------------------------------------------------------------

-- | Creates a disposable that doesn't have any side effect whatsoever
-- when disposed.
emptyDisposable :: IO Disposable
emptyDisposable = D.empty

-- | Creates a @Disposable@ from an @IO@ action, this @IO@ action will
-- be called when @dispose@ is called.
createDisposable :: IO () -> IO Disposable
createDisposable = D.create

-- | Creates an empty @BooleanDisposable@.
--
newBooleanDisposable :: IO BooleanDisposable
newBooleanDisposable = BD.empty

-- | Creates an empty @SingleAssignmentDisposable@.
--
newSingleAssignmentDisposable :: IO SingleAssignmentDisposable
newSingleAssignmentDisposable = SAD.empty

-- | Creates an empty @CompositeDisposable@.
--
newCompositeDisposable :: IO CompositeDisposable
newCompositeDisposable = CD.create

--------------------------------------------------------------------------------

instance IDisposableWrapper BooleanDisposable where
  set d0 = BD.set (toDisposable d0)
  get = BD.get

instance IDisposableWrapper SingleAssignmentDisposable where
  set d0 = SAD.set (toDisposable d0)
  get = SAD.get

instance IDisposableContainer CompositeDisposable where
  append d0 = CD.append (toDisposable d0)
