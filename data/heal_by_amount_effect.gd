class_name HealByAmountEffect
extends Resource
## Effect sub-resource: heal the target for a percentage of a contextual
## "event amount" passed in via trigger dispatch. Dispatched only from
## TriggerComponent, which reads the on_heal event's amount and applies it.
##
## Bypasses the healing pipeline — the event amount is already post-pipeline
## (healing_bonus, healing_received, crit all baked in), so applying the
## flat percentage gives exactly <percent>% of what the target received.
## Curse inversion is still respected.
##
## attribution_tag is stamped on the emitted on_heal signal so trigger
## listeners can filter recursion via AttributionTag(negate=true).
##
## First consumer: Cleric Spirit Link (+25% from Spirit Guardian on each heal).

@export var percent: float = 0.25
@export var attribution_tag: String = ""  ## Stamped on the emitted on_heal (for recursion filter)
