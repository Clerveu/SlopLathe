class_name HitData
extends RefCounted
## Runtime damage result from DamageCalculator. Not serialized.

var amount: float = 0.0
var damage_type: String = "Physical"
var original_damage_type: String = "Physical"
var is_crit: bool = false
var is_blocked: bool = false
var is_dodged: bool = false
var block_mitigated: float = 0.0
var dr_mitigated: float = 0.0  ## Amount mitigated by damage_taken modifiers (Step 6.5)
var source: Node2D = null
var target: Node2D = null
var ability: AbilityDefinition = null
var is_reflected: bool = false  ## True for thorns/reflect damage — prevents recursive reflection
var is_echo: bool = false  ## True for echo-replayed hits (Cleric Salvation, Ranger Echo Shot). Suppresses self-stacking on_hit_received reactions ("no free proc velocity" principle). Trigger listeners can gate via TriggerConditionHitIsEcho.
var attribution_tag: String = ""  ## Source attribution: status_id, talent source_id, "thorns", "leech", "overflow", etc.
## Multi-entity contribution chain — defaults to empty array. Each entry is
## {entity: Node2D, source_name: String, role: String}. Reporting-only;
## the mechanical `source` stays the acting entity (thorns, leech, kill credit
## all resolve against `source`). `contributors` lets cross-entity item flows
## (an item on entity A injecting a trigger onto B that hits C) attribute the
## delta back to A's item without breaking source identity. Roles used initially:
## "item_trigger", "item_ability_modification", "item_cross_injection".
var contributors: Array[Dictionary] = []


static func create(p_amount: float, p_damage_type: String, p_source: Node2D,
		p_target: Node2D, p_ability: AbilityDefinition = null) -> HitData:
	var h := HitData.new()
	h.amount = p_amount
	h.damage_type = p_damage_type
	h.original_damage_type = p_damage_type
	h.source = p_source
	h.target = p_target
	h.ability = p_ability
	return h
