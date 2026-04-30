class_name HealEffect
extends Resource
## Effect sub-resource: heal targets.

@export var scaling_attribute: String = "Cha"
@export var scaling_coefficient: float = 1.0
@export var base_healing: float = 0.0
@export var percent_max_hp: float = 0.0  ## When > 0, heal = target max HP * this value (ignores attribute scaling)
