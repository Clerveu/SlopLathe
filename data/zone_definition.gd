class_name ZoneDefinition
extends Resource

@export var zone_id: String = ""
@export var zone_name: String = ""
@export var tier: int = 1
@export var theme: String = ""
@export var length: float = 0.0
@export var duration: float = 0.0

@export var enemy_roster: Array = []
@export var waves: Array = []
@export var boss_enemy_id: String = ""

@export var spawn_interval_base: float = 6.0
@export var spawn_interval_decay: float = 0.03
@export var spawn_interval_floor: float = 0.5
@export var initial_spawn_delay: float = 2.0

@export var scroll_speed: float = 30.0
@export var combat_speed_ratio: float = 0.25
@export var spawn_side: String = "right"
@export var ground_y_range: Vector2 = Vector2(112.0, 148.0)
@export var hero_max_x_ratio: float = 0.55
@export var background_texture_path: String = ""
@export var formation_override: Array = []

@export var play_area_y: Vector2 = Vector2(40.0, 160.0)
@export var hero_min_x: float = 5.0
@export var melee_target_max_x: float = 290.0

@export var party_class_filter: Array[String] = []
@export var zone_modifiers: Array = []
