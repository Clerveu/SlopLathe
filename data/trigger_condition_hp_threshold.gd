class_name TriggerConditionHpThreshold
extends Resource
## Trigger condition: an entity involved in the event has HP above/below a threshold.
## Unlike ability ConditionHpThreshold (gates "is this ability ready?"), this checks
## event-entity HP in response to an event (on_hit_received, on_heal, etc.).
##
## entity_role selects which entity's HP to check:
##   "self"   — the trigger bearer (default; e.g. Savage Threshold on own HP)
##   "target" — the event target (e.g. Angelic Intervention on the hit ally)
##   "source" — the event source (rarely used, included for symmetry)
##
## First consumers: Savage Threshold (self, below 40%), Angelic Intervention
## (target, below 20%).

@export var threshold: float = 0.4    ## HP ratio (0.0–1.0)
@export var direction: String = "below"  ## "below" (< threshold) or "above" (> threshold)
@export var entity_role: String = "self"  ## "self", "target", or "source"
