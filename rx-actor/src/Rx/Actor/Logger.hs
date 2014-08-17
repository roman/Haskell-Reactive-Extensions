{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE FlexibleInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module Rx.Actor.Logger where

import qualified Rx.Logger as Logger (logMsg)
import Rx.Logger.Monad (MonadLog(logMsg))

import Control.Monad.Trans (MonadIO(..))

import Rx.Actor.Monad
import Rx.Actor.Types


instance (MonadIO m, HasActor m) => MonadLog m where
  logMsg level msg0 = do
    logger <- getLogger
    actorKey <- getActorKey
    let msg = ActorLogMsg actorKey msg0
    liftIO $ Logger.logMsg level logger msg
