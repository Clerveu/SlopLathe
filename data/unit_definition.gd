class_name UnitDefinition
extends Resource

@export var unit_id: String = ""
@export var archetype: String = ""
@export var tags: Array[String] = []
@export var equipment_slots: Array[String] = ["Weapon", "Armor", "Amulet", "Trinket"]

@export var auto_attack: AbilityDefinition
@export var skills: Array[SkillDefinition] = []
@export var talent_tree: TalentTreeDefinition

@export var sprite_sheet: SpriteFrames
@export var shadow_sheet: SpriteFrames = null
@export var hit_frame: int = 3

@export var combat_role: String = "MELEE"
@export var engage_distance: float = 20.0
@export var move_speed: float = 25.0
@export var aggro_range: float = 0.0
@export var retarget_interval: float = 1.5
@export var preferred_range: float = 0.0
