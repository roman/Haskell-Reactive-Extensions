{-# LANGUAGE ExistentialQuantification #-}
module Rx.Actor.Supervisor.SupervisorBuilder where

import Tiempo (TimeInterval, seconds)
import Control.Monad.Free

import Rx.Actor.ActorBuilder
import Rx.Actor.Types

--------------------------------------------------------------------------------

data SupervisorBuilderF x
  = StrategyI   SupervisorStrategy x
  | MaxRestartsI AttemptCount  x
  | BackoffI    (AttemptCount -> TimeInterval) x
  | forall st . AddChildI (ActorDef st) x

instance Functor SupervisorBuilderF where
  fmap f (StrategyI strat x) = StrategyI strat (f x)
  fmap f (MaxRestartsI attemptCount x) = MaxRestartsI attemptCount (f x)
  fmap f (BackoffI fn x) = BackoffI fn (f x)
  fmap f (AddChildI actorDef x) = AddChildI actorDef (f x)

type SupervisorBuilder = Free SupervisorBuilderF

--------------------------------------------------------------------------------

strategy :: SupervisorStrategy -> SupervisorBuilder ()
strategy strat = liftF $ StrategyI strat ()

backoff :: (AttemptCount -> TimeInterval) -> SupervisorBuilder ()
backoff fn  = liftF $ BackoffI fn ()

maxRestarts :: AttemptCount -> SupervisorBuilder ()
maxRestarts attemptCount = liftF $ MaxRestartsI attemptCount ()

addChild :: ActorDef st -> SupervisorBuilder ()
addChild actorDef = liftF $ AddChildI actorDef ()

buildChild :: ActorBuilder st () -> SupervisorBuilder ()
buildChild actorBuilder = do
  liftF $ AddChildI (defActor actorBuilder) ()

emptySupervisorDef :: SupervisorDef
emptySupervisorDef =
  SupervisorDef {
    _supervisorStrategy = OneForOne
  , _supervisorBackoffDelayFn = seconds . (2^)
  , _supervisorMaxRestartAttempts = 5
  , _supervisorDefChildren = []
  }

defSupervisor :: SupervisorBuilder () -> SupervisorDef
defSupervisor instr = eval emptySupervisorDef instr
  where
    eval sup (Pure _) = sup
    eval sup (Free (StrategyI strat next)) =
      eval (sup { _supervisorStrategy = strat }) next
    eval sup (Free (BackoffI backoffFn next)) =
      eval (sup { _supervisorBackoffDelayFn = backoffFn }) next
    eval sup (Free (MaxRestartsI restartAttempts next)) =
      eval (sup { _supervisorMaxRestartAttempts = restartAttempts }) next
    eval sup (Free (AddChildI actorDef next)) =
        let actorDefs = _supervisorDefChildren sup
        in eval (sup { _supervisorDefChildren = gActorDef : actorDefs }) next
      where
        gActorDef = GenericActorDef actorDef
