class_name EnemyDefinition
extends Resource

@export var enemy_id: String = ""
@export var enemy_name: String = ""
@export var tags: Array[String] = []
@export var base_stats: Dictionary = {}
@export var auto_attack: AbilityDefinition
@export var skills: Array[SkillDefinition] = []
@export var sprite_sheet: SpriteFrames
@export var shadow_sheet: SpriteFrames = null
@export var hit_frame: int = 3
@export var combat_role: String = "MELEE"
@export var engage_distance: float = 20.0
@export var move_speed: float = 25.0
@export var aggro_range: float = 0.0
@export var retarget_interval: float = 1.5
@export var preferred_range: float = 0.0
@export var aa_interval_override: float = 0.0
@export var xp_value: int = 10
@export var is_elite: bool = false
@export var is_boss: bool = false
@export var priority_role: String = ""
@export var on_death_effects: Array = []
@export var detonate_range: float = 0.0
@export var spawn_intro: ChoreographyDefinition = null
@export var apply_statuses: Array = []
