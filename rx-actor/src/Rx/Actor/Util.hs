{-# LANGUAGE ScopedTypeVariables #-}
module Rx.Actor.Util where

import Control.Monad (void)
import Control.Exception (SomeException, catch)

-- TODO: Actually do the Logging

logError :: IO a -> IO (Maybe a)
logError action = (Just `fmap` action) `catch`
                     (\(_ :: SomeException) -> return Nothing)

logError_ :: IO a -> IO ()
logError_ action =
  (void action) `catch` (\(_ :: SomeException) -> return ())

loopUntil_ :: Monad m => [a] -> (a -> m (Maybe (m ()))) -> m ()
loopUntil_ [] _  = return ()
loopUntil_ (a:as) fn = do
  result <- fn a
  case result of
    Just action -> action
    Nothing -> loopUntil_ as fn
