{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ExistentialQuantification #-}
module Rx.Actor.ActorBuilder where

import Data.Typeable (Typeable)
import Control.Concurrent (ThreadId, forkIO, forkOS)
import Control.Exception (Exception, SomeException)
import Control.Monad.Free

import Tiempo (TimeInterval, seconds)

import qualified Data.HashMap.Strict as HashMap

import Rx.Actor.Util (getHandlerParamType1)
import Rx.Actor.Types

--------------------------------------------------------------------------------

data ActorBuilderF st x
  = SetActorKeyI String x
  | SetStartDelayI TimeInterval x
  | PreStartI (PreActorM (InitResult st)) x
  | PostStopI (RO_ActorM st ()) x
  | PreRestartI  (SomeException -> GenericEvent -> RO_ActorM st ()) x
  | PostRestartI (SomeException -> GenericEvent -> RO_ActorM st (InitResult st)) x
  | forall e. (Typeable e, Exception e)
      => OnErrorI (e -> RO_ActorM st RestartDirective)  x
  | HandlerDescI String x
  | SetForkerI (IO () -> IO ThreadId) x
  | AppendEventBusDecoratorI EventBusDecorator x
  | forall t . Typeable t => HandlerI (t -> ActorM st ()) x

instance Functor (ActorBuilderF st) where
  fmap f (SetActorKeyI key x) = SetActorKeyI key (f x)
  fmap f (SetStartDelayI delay x) = SetStartDelayI delay (f x)
  fmap f (PreStartI action x) = PreStartI action (f x)
  fmap f (PostStopI action x) = PostStopI action (f x)
  fmap f (PreRestartI action x) = PreRestartI action (f x)
  fmap f (PostRestartI action x) = PostRestartI action (f x)
  fmap f (OnErrorI action x) = OnErrorI action (f x)
  fmap f (SetForkerI forker x) = SetForkerI forker (f x)
  fmap f (AppendEventBusDecoratorI decorator x) =
    AppendEventBusDecoratorI decorator (f x)
  fmap f (HandlerDescI str x) = HandlerDescI str (f x)
  fmap f (HandlerI action x) = HandlerI action (f x)

type ActorBuilder st = Free (ActorBuilderF st)

-- $setup
-- >>> import Control.Concurrent.MVar
-- >>> import Control.Exception (ErrorCall(..), toException)
-- >>> let err = toException $ ErrorCall "test"

--------------------------------------------------------------------------------

actorKey :: String -> ActorBuilder st ()
actorKey key = liftF $ SetActorKeyI key ()

startDelay :: TimeInterval -> ActorBuilder st ()
startDelay delay = liftF $ SetStartDelayI delay ()

-- |
-- Example:
--
-- >>> let actorDef = defActor $ preStart (return $ InitOk 0)
-- >>> _actorPreStart actorDef
-- InitOk 0
preStart :: PreActorM (InitResult st) -> ActorBuilder st ()
preStart action = liftF $ PreStartI action ()

-- |
-- Example:
--
-- >>> result <- newEmptyMVar :: IO (MVar String)
-- >>> let actorDef = defActor $ postStop (putMVar result "STOPPED")
-- >>> _actorPostStop actorDef
-- >>> takeMVar result
-- "STOPPED"
postStop :: (RO_ActorM st ()) -> ActorBuilder st ()
postStop action = liftF $ PostStopI action ()

-- |
-- Example:
--
-- >>> result <- newEmptyMVar :: IO (MVar Int)
-- >>> let actorDef = defActor $ preRestart (\st _ -> putMVar result st)
-- >>> _actorPreRestart actorDef 777 err
-- >>> takeMVar result
-- 777
preRestart
  :: (SomeException -> GenericEvent -> RO_ActorM st ())
  -> ActorBuilder st ()
preRestart action = liftF $ PreRestartI action ()

-- |
-- Example:
--
-- >>> result <- newEmptyMVar :: IO (MVar Int)
-- >>> let actorDef = defActor $ postRestart (\st _ -> putMVar result st)
-- >>> _actorPostRestart actorDef 777 err
-- >>> takeMVar result
-- 777
postRestart
  :: (SomeException -> GenericEvent -> RO_ActorM st (InitResult st))
  -> ActorBuilder st ()
postRestart action = liftF $ PostRestartI action ()

onError
  :: (Typeable e, Exception e)
  => (e -> RO_ActorM st RestartDirective)
  -> ActorBuilder st ()
onError action = liftF $ OnErrorI action ()

useBoundThread :: Bool -> ActorBuilder st ()
useBoundThread False = liftF $ SetForkerI forkIO ()
useBoundThread True  = liftF $ SetForkerI forkOS ()

desc :: String -> ActorBuilder st ()
desc str = liftF $ HandlerDescI str ()

decorateEventBus :: EventBusDecorator -> ActorBuilder st ()
decorateEventBus decorator = liftF $ AppendEventBusDecoratorI decorator ()

receive :: Typeable t => (t -> ActorM st ()) -> ActorBuilder st ()
receive handler = liftF $ HandlerI handler ()

--------------------------------------------------------------------------------

defActor :: ActorBuilder st () -> ActorDef st
defActor buildInstructions =
    let result = eval emptyActorDef buildInstructions
    in case _actorChildKey result of
      Nothing -> error "FATAL: Actor must have an actor key"
      Just _  -> result
  where
    emptyActorDef =
      ActorDef {
          _actorChildKey = Nothing
        , _actorForker = forkIO
        , _actorPreStart = error "preStart needs to be defined"
        , _actorPostStop = return ()
        , _actorPreRestart = \_ _ -> return ()
        , _actorPostRestart = \_ _ -> getState >>= return . InitOk
        , _actorRestartDirective =
         HashMap.singleton "SomeException"
                            (ErrorHandler $ \(_ :: SomeException) -> return Restart)
        , _actorReceive = HashMap.empty
        , _actorRestartAttempt = 0
        , _actorDelayAfterStart = seconds 0
        , _actorEventBusDecorator = id
        }
    eval actorDef (Pure _) = actorDef

    eval actorDef (Free (SetActorKeyI key next)) =
      eval (actorDef { _actorChildKey = Just key }) next

    eval actorDef (Free (SetStartDelayI delay next)) =
      eval (actorDef { _actorDelayAfterStart = delay }) next

    eval actorDef (Free (PreStartI preStart_ next)) =
      eval (actorDef {_actorPreStart = preStart_}) next

    eval actorDef (Free (PostStopI postStop_ next)) =
      eval (actorDef {_actorPostStop = postStop_}) next

    eval actorDef (Free (PreRestartI preRestart_ next)) =
      eval (actorDef { _actorPreRestart = preRestart_}) next

    eval actorDef (Free (PostRestartI postRestart_ next)) =
      eval (actorDef { _actorPostRestart = postRestart_}) next

    eval actorDef (Free (SetForkerI forker next)) =
      eval (actorDef { _actorForker = forker }) next

    eval actorDef (Free (AppendEventBusDecoratorI decorator next)) =
      let currentDecorator = _actorEventBusDecorator actorDef
      in eval (actorDef { _actorEventBusDecorator = decorator . currentDecorator }) next

    eval actorDef (Free (OnErrorI onError_ next)) =
      eval (addErrorHandler actorDef (ErrorHandler onError_)) next

    eval actorDef (Free (HandlerDescI str (Free (HandlerI handler next)))) =
      eval (addReceiveHandler actorDef (EventHandler str handler)) next

    eval _actorDef (Free (HandlerDescI str _)) =
      error $ "FATAL: ActorBuilder#desc can only be used " ++
              "before a receive handler\n(context: " ++
              str ++ ")"

    eval actorDef (Free (HandlerI handler next)) =
      eval (addReceiveHandler actorDef (EventHandler "" handler)) next


--------------------------------------------------------------------------------

-- NOTE: Both addReceiveHandler and addErrorHandler have the same exact code
-- by using Lenses we can make a polymorphic function that can receive the
-- the setting attribute as a parameter

addReceiveHandler :: ActorDef st -> EventHandler st -> ActorDef st
addReceiveHandler actorDef handler@(EventHandler _ fn) = do
  case getHandlerParamType1 fn of
    Just paramType ->
      let actorRecieve' = HashMap.insertWith (\_ _ -> handler)
                                             paramType
                                             handler
                                             (_actorReceive actorDef)
      in actorDef { _actorReceive = actorRecieve' }
    Nothing ->
      error "Weird: didn't receive a valid handler that can be inspected"

addErrorHandler :: ActorDef st -> ErrorHandler st -> ActorDef st
addErrorHandler actorDef errorHandler@(ErrorHandler fn) = do
  case getHandlerParamType1 fn of
    Just paramType ->
      let actorRestartDirective' =
            HashMap.insertWith (\_ _ -> errorHandler)
                               paramType
                               errorHandler
                               (_actorRestartDirective actorDef)
      in actorDef { _actorRestartDirective = actorRestartDirective' }
    Nothing ->
      error "Weird: didn't receive a valid handler that can be inspected"
