module Rx.Logger.Env (Settings(..), defaultSettings, setupTracer) where

import Control.Monad      (liftM)
import Data.Monoid        (First (..), mconcat)
import System.Environment (lookupEnv)
import System.IO          (stderr, stdout)


import           Rx.Disposable (Disposable, emptyDisposable,
                                newCompositeDisposable)
import qualified Rx.Disposable as Disposable

import Rx.Logger.Core
import Rx.Logger.Format     (ttccFormat)
import Rx.Logger.Serializer (serializeToFile, serializeToHandle)
import Rx.Logger.Types


--------------------------------------------------------------------------------

data Settings
  = Settings {
    envPrefix            :: String
  , envLogEntryFormatter :: LogEntryFormatter
  }

defaultSettings :: Settings
defaultSettings =
  Settings { envPrefix = "LOGGER"
           , envLogEntryFormatter = ttccFormat }

setupTracer :: (ToLogger logger)
             => Settings
             -> logger
             -> IO Disposable
setupTracer settings logger = do
    allSubs <- newCompositeDisposable
    setupHandleTrace >>= flip Disposable.append allSubs
    setupFileTrace   >>= flip Disposable.append allSubs
    return $! Disposable.toDisposable allSubs
  where
    entryF = envLogEntryFormatter settings
    prefix = envPrefix settings
    setupFileTrace =
      lookupEnv (prefix ++ "_TRACE_FILE")
          >>= maybe emptyDisposable
                    (\filepath -> do
                         sub <- serializeToFile filepath entryF logger
                         config logger ("Log tracing on file " ++ filepath)
                         return sub)
    setupHandleTrace = do
      -- NOTE: Can use either STDOUT or STDERR for logging
      results <- sequence [
          liftM (maybe Nothing (const $ Just stdout))
                (lookupEnv (prefix ++ "_TRACE_STDOUT"))
        , liftM (maybe Nothing (const $ Just stderr))
                (lookupEnv (prefix ++ "_TRACE_STDERR"))
        ]
      case getFirst . mconcat . map First $ results of
        Just handle -> do
          sub <- serializeToHandle handle entryF logger
          config logger ("Log tracing on handle " ++ show handle)
          return sub
        Nothing -> emptyDisposable

--------------------------------------------------------------------------------
