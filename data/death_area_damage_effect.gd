class_name DeathAreaDamageEffect
extends Resource
## AOE damage centered on a dying entity's position. Flat damage, no attribute scaling.
## Source can be dead — position and faction are still readable before queue_free.

@export var damage_type: String = "Fire"
@export var flat_damage: float = 10.0
@export var aoe_radius: float = 25.0
