class_name SnapshotAmplifyStatusesEffect
extends Resource
## Self-resolving pool effect: scans every entity of `target_faction` (relative
## to source) and amplifies their active statuses matching `polarity` in place.
## Per-instance, snapshot-only — debuffs applied AFTER dispatch are untouched
## (they didn't exist when the snapshot ran).
##
## Mutations on each matching ActiveStatus:
##   _runtime_max_stacks → max(1, current_max * stack_multiplier)
##   _tick_power_bonus   += tick_power_bonus      (additive on top of Amplifier)
##   _frozen_until       = max(prev, run_time + freeze_duration)  (when > 0)
##
## During freeze: tick() skips duration decrement on this instance only. Other
## decay-based modifier sync (`_has_decay_modifiers`) still re-syncs because the
## time_remaining ratio doesn't change. Tick effects continue to fire — only the
## expiry timer is paused. Frozen instance auto-thaws when run_time exceeds
## _frozen_until — no cleanup hook required.
##
## Generic shape: future "Frost Snap" / "Surge" / buff-side amplifiers reuse this
## with different polarity / multipliers. First consumer: Witch Doctor Plague
## Tide (Afflictor capstone — debuff caps doubled, durations frozen 10s,
## per-tick potency +100%).

@export var target_faction: String = "enemy"     ## "enemy" or "ally" relative to source
@export var polarity: String = "debuff"          ## "debuff" (non-positive), "buff" (positive), or "any"
@export var stack_multiplier: float = 1.0        ## Multiplied into _runtime_max_stacks (1.0 = no-op)
@export var tick_power_bonus: float = 0.0        ## Added to _tick_power_bonus (0.0 = no-op)
@export var freeze_duration: float = 0.0         ## > 0 = freeze duration timer for this many seconds
