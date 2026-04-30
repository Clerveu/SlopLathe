class_name TriggerConditionAbilityHasTag
extends Resource
## Trigger condition: the ability that caused the event carries a specific tag.
## Requires event data to be HitData with a non-null ability field
## (on_hit_dealt, on_hit_received, on_crit). Negate inverts: pass when the
## ability LACKS the tag. Item-driven triggers gated on ability category
## ("Fire" hits, "Melee" hits, "Spell" hits) consume this without enumerating
## ability_ids — parallels the way TargetingRule's tag matchers work.

@export var tag: String = ""
@export var negate: bool = false
