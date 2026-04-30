class_name ApplyCleanseImmunityEffect
extends Resource
## Effect sub-resource: grant per-status-id immunity to the target for `duration`
## seconds, keyed on the status_id that was just cleansed in the triggering
## on_cleanse event.
##
## Dispatched only from TriggerComponent on_cleanse listeners — the status_id
## comes from the on_cleanse payload Dictionary, not from a static field. Mirrors
## the HealByAmountEffect / DamageByAmountEffect pattern: special-cased in
## `trigger_component._evaluate_and_dispatch` so the effect can read hit_data.
## Not valid on abilities or status hooks.
##
## First consumer: Cleric Retribution (Exorcist T3) — cleansed debuffs cannot be
## reapplied to that ally for 3 seconds.

@export var duration: float = 3.0
