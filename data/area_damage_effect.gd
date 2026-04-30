class_name AreaDamageEffect
extends Resource
## Effect sub-resource: deal damage to all enemies within a radius of the target's position.
## Full damage pipeline (DamageCalculator) runs per target — not raw/flat damage.
## Source must be alive (attribute scaling). Target can be dead (position reference only).
## First consumer: Thunder Harvest death explosion. Future: Rampage kill explosion, Earthsplitter AOE.

@export var damage_type: String = "Physical"
@export var scaling_attribute: String = "Str"
@export var scaling_coefficient: float = 1.0
@export var base_damage: float = 1.0
@export var aoe_radius: float = 20.0
