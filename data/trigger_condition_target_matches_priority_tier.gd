class_name TriggerConditionTargetMatchesPriorityTier
extends Resource
## Trigger condition: the event's target entity matches any of the listed
## priority tiers. Tier semantics delegate to TargetingRule's static matcher —
## same classification used by "priority_tiered_enemy" targeting, so talent
## bonus effects that gate on "target was a priority target" stay consistent
## with the targeting that picked it.
##
## Supported tiers: "healer", "caster", "ranged", "elite", "boss". Empty list
## means the condition always fails (no tier matches an empty list — use
## absence of this condition when you don't want tier gating).
##
## First consumer: Ranger Hunter's Priority (bonus +1 Mark stack applied to
## priority targets on auto-attack hits; nearest-fallback targets do not get
## the bonus because they match no tier).
##
## `negate` inverts the check: pass when the target matches NONE of the listed
## tiers. Use case: "non-elite, non-boss" filters for trash-only effects,
## where listing ["elite", "boss"] with negate=true passes on every target
## that is neither elite nor boss. First negate consumer: Ranger Fusillade
## (execute filter — non-elite, non-boss trash only).

@export var priority_tiers: Array[String] = []
@export var negate: bool = false
