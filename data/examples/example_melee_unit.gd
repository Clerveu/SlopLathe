class_name ExampleMeleeUnit
extends RefCounted


static func create_unit_definition(sprite_sheet: SpriteFrames) -> UnitDefinition:
	var def := UnitDefinition.new()
	def.unit_id = "warrior"
	def.archetype = "Damage"
	def.tags = ["Humanoid", "Armed"]

	def.sprite_sheet = sprite_sheet
	def.hit_frame = 3

	def.combat_role = "MELEE"
	def.engage_distance = 20.0
	def.move_speed = 25.0

	# Auto-attack: Physical damage scaling from Str
	var aa := AbilityDefinition.new()
	aa.ability_id = "warrior_aa"
	aa.tags = ["Melee", "Physical"]
	aa.targeting = TargetingRule.new()
	aa.targeting.type = "nearest_enemy"
	var aa_dmg := DealDamageEffect.new()
	aa_dmg.damage_type = "Physical"
	aa_dmg.scaling_attribute = "Str"
	aa_dmg.scaling_coefficient = 1.0
	aa.effects = [aa_dmg]
	def.auto_attack = aa

	# Skill 1: War Cry — applies a damage buff to self
	var warcry_ability := AbilityDefinition.new()
	warcry_ability.ability_id = "war_cry"
	warcry_ability.tags = ["Buff"]
	warcry_ability.cooldown_base = 8.0
	warcry_ability.priority = 2
	warcry_ability.targeting = TargetingRule.new()
	warcry_ability.targeting.type = "self"

	var buff_status := StatusEffectDefinition.new()
	buff_status.status_id = "war_cry_buff"
	buff_status.is_positive = true
	buff_status.base_duration = 5.0
	buff_status.max_stacks = 1
	var buff_mod := ModifierDefinition.new()
	buff_mod.target_tag = "All"
	buff_mod.operation = "bonus"
	buff_mod.value = 0.20
	buff_status.modifiers = [buff_mod]

	var apply_buff := ApplyStatusEffectData.new()
	apply_buff.status = buff_status
	apply_buff.stacks = 1
	apply_buff.apply_to_self = true
	warcry_ability.effects = [apply_buff]

	var skill1 := SkillDefinition.new()
	skill1.skill_name = "War Cry"
	skill1.ability = warcry_ability
	skill1.unlock_level = 1

	def.skills = [skill1]

	return def
