class_name ExampleRangedEnemy
extends RefCounted


static func create_enemy_definition(sprite_sheet: SpriteFrames) -> EnemyDefinition:
	var def := EnemyDefinition.new()
	def.enemy_id = "skeleton_archer"
	def.enemy_name = "Skeleton Archer"
	def.tags = ["Undead", "Ranged"]
	def.base_stats = {"Str": 5.0, "Stam": 8.0, "Dex": 3.0}

	def.sprite_sheet = sprite_sheet
	def.hit_frame = 2

	def.combat_role = "RANGED"
	def.engage_distance = 120.0
	def.move_speed = 20.0
	def.aggro_range = 100.0
	def.retarget_interval = 2.0
	def.xp_value = 15

	# Projectile auto-attack
	var aa := AbilityDefinition.new()
	aa.ability_id = "skeleton_archer_aa"
	aa.tags = ["Ranged", "Physical"]
	aa.targeting = TargetingRule.new()
	aa.targeting.type = "nearest_enemy"

	var proj_config := ProjectileConfig.new()
	proj_config.motion_type = "aimed"
	proj_config.speed = 120.0
	proj_config.hit_radius = 6.0
	var proj_dmg := DealDamageEffect.new()
	proj_dmg.damage_type = "Physical"
	proj_dmg.scaling_attribute = "Str"
	proj_dmg.scaling_coefficient = 0.8
	proj_config.on_hit_effects = [proj_dmg]

	var spawn_proj := SpawnProjectilesEffect.new()
	spawn_proj.projectile = proj_config
	spawn_proj.spawn_pattern = "aimed_single"
	aa.effects = [spawn_proj]

	def.auto_attack = aa

	return def
