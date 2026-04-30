class_name SummonEffect
extends Resource

@export var summon_id: String = ""
@export var summon_class: UnitDefinition
@export var count: int = 1
@export var spawn_spread: float = 0.0
@export var reset_cooldown_on_death: bool = true
@export var stat_map: Dictionary = {}
@export var duration: float = 0.0
@export var is_untargetable: bool = false
@export var threat_modifier: float = 0.0
