class_name ExtendActiveCooldownsEffect
extends Resource
## Effect sub-resource: multiply every already-ticking cooldown on the
## dispatch target's AbilityComponent by `multiplier`. Paired with the
## bearer-side cooldown_extend modifier — the modifier affects NEW cooldowns
## started during the carrier status's lifetime; this effect retroactively
## extends ALREADY-ticking cooldowns at dispatch time.
##
## Target-side operation: the passed-in target is the bearer whose cooldowns
## should be extended (typical use: a CC status dispatches this from
## on_apply_effects so applying the status to an enemy drags their rotation).
## No-op on slots currently at 0 (nothing to extend) and when multiplier <= 1.0
## (the natural baseline — "extension" below 1x would be a refund, use
## RefundCooldownEffect for that path).
##
## Does NOT touch the AA cadence — AA timers live on BehaviorComponent, out of
## reach, mirroring RefundCooldownEffect's all-slots convention.
##
## First consumer: Witch Doctor Inescapable's Cooldown Drag status (Silence
## stepdown — +50% to all active and pending enemy cooldowns for 4s).

@export var multiplier: float = 1.5
