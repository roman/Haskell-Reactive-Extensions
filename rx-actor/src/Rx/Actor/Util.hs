{-# LANGUAGE ScopedTypeVariables #-}
module Rx.Actor.Util where

import Data.Typeable ( Typeable
                     , typeOf, typeOf1
                     , typeRepTyCon, splitTyConApp )

import Control.Monad (void)
import Control.Exception (SomeException, catch)

-- TODO: Actually do the Logging

logError :: IO a -> IO (Maybe a)
logError action = (Just `fmap` action) `catch`
                     (\(_ :: SomeException) -> return Nothing)

logError_ :: IO a -> IO ()
logError_ action =
  (void action) `catch` (\(_ :: SomeException) -> return ())

getHandlerParamType1 :: Typeable m => m a -> Maybe String
getHandlerParamType1 a =
    if tyCon == fnTy
       then Just . show $ head tyArgs
       else Nothing
  where
    (tyCon, tyArgs) = splitTyConApp $ typeOf1 a
    fnTy = typeRepTyCon $ typeOf words
