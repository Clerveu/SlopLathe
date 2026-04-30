class_name DamageByAmountEffect
extends Resource
## Effect sub-resource: deal raw damage to the target equal to a percentage
## of a contextual "event amount" from the trigger payload (HitData for hit
## events, Dictionary with "amount" key for on_heal events). Dispatched only
## from TriggerComponent, which extracts the event amount and applies it.
##
## Bypasses the damage pipeline — the event amount is already post-pipeline,
## so applying the flat percentage gives exactly <percent>% of what landed.
## Creates a raw HitData and calls target.take_damage directly; source is the
## ORIGINAL event source (the attacker), not the trigger bearer, so thorns
## and last_hit_by attribution remain coherent.
##
## attribution_tag is stamped on the emitted HitData so recursion filters
## (AttributionTag negate=true) can block re-entry.
##
## First consumer: Cleric Martyrdom — 30% of big hits on allies redirected
## as raw damage to the Cleric herself.

@export var percent: float = 0.30
@export var attribution_tag: String = ""
