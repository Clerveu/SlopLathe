class_name RefreshStatusInRadiusEffect
extends Resource
## Radius-scanning effect: refreshes a status's duration on every entity of
## `target_faction` (relative to the dispatched target) within `radius` of the
## target position. Same "self-resolving pool" shape as SpreadStatusEffect and
## FactionCleanseEffect — the effect ignores EffectDispatcher's per-target loop
## and runs its own grid scan.
##
## Refresh semantics match RefreshHotsEffect: each affected entity's status
## `time_remaining` is reset to the duration recorded at apply (_applied_duration),
## which already bakes in the applier's duration_bonus. Entities without the
## status are skipped. Untouched: stacks, modifiers, trigger listeners.
##
## First consumer: Wizard Persistent Flames (T3 Pyromancer) — mass-refresh Burn
## on enemies within 30px when the Wizard applies Burn to a max-stacked target.

@export var status_id: String = ""
@export var radius: float = 0.0
@export var target_faction: String = "enemy"  ## "enemy" or "ally" relative to source — matches SpreadStatusEffect's bearer_faction convention
