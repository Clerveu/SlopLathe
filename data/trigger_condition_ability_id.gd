class_name TriggerConditionAbilityId
extends Resource
## Trigger condition: the ability that caused the event matches the expected ability_id.
## Requires event data to be HitData with a non-null ability field (on_hit_dealt, on_hit_received, on_crit).
## First consumer: Thunder Harvest (on_hit_dealt where ability is "barbarian_thunder_blade").

@export var ability_id: String = ""  ## Required ability_id to match
