module Rx.Logger.Env
       ( Settings(..)
       , defaultSettings
       , setupLogTracer
       , setupLogTracerWithPrefix
       ) where

import           Control.Monad      (liftM)
import           Data.Maybe         (fromMaybe)
import           Data.Monoid        (First (..), mconcat)
import qualified Data.Text          as Text
import           System.Environment (lookupEnv)
import           System.IO          (stderr, stdout)


import           Rx.Disposable (Disposable, emptyDisposable,
                                newCompositeDisposable)
import qualified Rx.Disposable as Disposable
import qualified Rx.Observable as Ob

import Rx.Logger.Core
import Rx.Logger.Format         (ttccFormat)
import Rx.Logger.LogLevelParser (parseLogLevel)
import Rx.Logger.Serializer     (serializeToFile, serializeToHandle)
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

setupLogTracerWithPrefix
  :: ToLogger logger => String -> logger -> IO Disposable
setupLogTracerWithPrefix prefix =
  setupLogTracer (defaultSettings { envPrefix = prefix })

setupLogTracer :: (ToLogger logger)
             => Settings
             -> logger
             -> IO Disposable
setupLogTracer settings logger = do
    levelFilter <- getLogLevelFilter
    main $ Ob.filter (levelFilter . _logEntryLevel)
         $ Ob.toAsyncObservable
         $ toLogger logger
  where
    prefix = envPrefix settings
    entryF = envLogEntryFormatter settings
    getLogLevelFilter = do
      mEntry <- lookupEnv (prefix ++ "_LOG_LEVEL")
      let result = do
            logLevelStr <- mEntry
            parseLogLevel $ Text.pack logLevelStr
      return $ fromMaybe (>= TRACE) result

    main loggerOb = do
        allSubs <- newCompositeDisposable
        setupHandleTrace >>= flip Disposable.append allSubs
        setupFileTrace   >>= flip Disposable.append allSubs
        return $! Disposable.toDisposable allSubs
      where
        setupFileTrace =
          lookupEnv (prefix ++ "_TRACE_FILE")
              >>= maybe emptyDisposable
                        (\filepath -> do
                             tracerDisposable <- serializeToFile filepath entryF loggerOb
                             config logger $ "Log tracing on file " ++ filepath
                             return tracerDisposable)
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
              logLevelFilter <- getLogLevelFilter
              tracerDisposable <- serializeToHandle handle entryF loggerOb
              config logger $ "Log tracing on handle " ++ show handle
              return tracerDisposable
            Nothing -> emptyDisposable

--------------------------------------------------------------------------------
