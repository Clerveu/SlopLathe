class_name ConditionHpThreshold
extends Resource
## Condition: an entity's HP is below/above a threshold (as percentage 0.0–1.0).

@export var target: String = "any_ally"   ## "self", "any_ally", "any_enemy"
@export var threshold: float = 0.5        ## 0.0–1.0
@export var direction: String = "below"   ## "below", "above"
