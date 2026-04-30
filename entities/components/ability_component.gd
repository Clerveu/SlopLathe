class_name AbilityComponent
extends Node
## Manages the entity's skill bar. Tracks cooldowns, evaluates conditions,
## returns the highest-priority ready ability for BehaviorComponent.

const ProjectileVariantScript = preload("res://data/projectile_variant.gd")

## Per-ability runtime state
class AbilitySlot:
	var definition: AbilityDefinition
	var cooldown_remaining: float = 0.0
	var is_held: bool = false  ## Player toggled to manual hold

	func _init(p_def: AbilityDefinition) -> void:
		definition = p_def

var _slots: Array[AbilitySlot] = []        ## Priority-sorted (highest first) for AI
var _display_slots: Array[AbilitySlot] = [] ## Insertion order (skill slot 1-6) for UI
var _auto_attack: AbilityDefinition = null
var _ability_modifications: Dictionary = {} ## ability_id → Array[Array[Resource]] (talent/item effect overlays)
## Parallel-array provenance for _ability_modifications. Each effect-group at
## _ability_modifications[ability_id][i] has its source name at
## _ability_modification_sources[ability_id][i]. Empty string for talents (the
## existing path) and "item_<item_id>" for items. Read by entity dispatch sites
## that build HitData.contributors lists for item-sourced groups.
var _ability_modification_sources: Dictionary = {} ## ability_id → Array[String] (parallel to _ability_modifications)
var _displacement_arrival_modifications: Dictionary = {} ## ability_id → Array[Array[Resource]] (fire at displacement arrival)
var _cooldown_flat_reductions: Dictionary = {} ## ability_id → float (flat CDR in seconds)
var _projectile_variant_overlays: Dictionary = {} ## ability_id → Array[ProjectileVariant] (accumulated across multiple modifications on the same ability). Consumed by ProjectileManager at spawn time for aimed_single SpawnProjectilesEffects.
var _summon_ability_replacements: Dictionary = {} ## ability_id → AbilityDefinition. Stashed by replace_ability when the target id doesn't match any locally-loaded AA/skill — consumed at summon spawn time (combat_manager._spawn_one_summon) so talents like Wizard Kindle can transform a summon's AA without the talent system caring about spawn lifecycle. Opt-in per talent entry: only populated when a talent explicitly declares an AbilityModification targeting a summon ability_id.
var _targeting_overrides: Dictionary = {}  ## ability_id → TargetingRule. Populated by register_targeting_override (from AbilityModification.targeting_override). Read by get_effective_targeting so BehaviorComponent resolves talent-overridden targeting without mutating the shared AbilityDefinition. Last writer wins if multiple talents target the same ability — talent authoring shouldn't stack overrides on the same id.
var _ability_charges: Dictionary = {}  ## ability_id → int. Stored free-cast counters. While a slot has charges, get_ready_abilities treats it as ready regardless of cooldown/condition gates. Charges consume in commit_cast ONLY when the ability wouldn't have fired normally — natural-ready casts preserve the bank. Incremented by GrantAbilityChargeEffect (capped at per-grant max_charges). First consumer: Ranger Marked For Death (ally kills on marked priority targets bank Crippling Shot charges, max 2).


func setup_abilities(auto_attack: AbilityDefinition, skills: Array[SkillDefinition],
		character_level: int, unlocked_ultimate_ids: Array[String] = []) -> void:
	_auto_attack = auto_attack
	_slots.clear()
	_display_slots.clear()
	for skill in skills:
		if skill.unlock_level <= character_level:
			# Ultimate gating: is_ultimate requires capstone talent pick
			if skill.is_ultimate and not unlocked_ultimate_ids.has(skill.ability.ability_id):
				continue
			var slot := AbilitySlot.new(skill.ability)
			_slots.append(slot)
			_display_slots.append(slot)  # Same objects, insertion order
	# Sort _slots by priority descending so highest is checked first (display_slots stays in skill order)
	_slots.sort_custom(func(a, b): return a.definition.priority > b.definition.priority)


func tick_cooldowns(delta: float) -> void:
	for slot in _slots:
		if slot.cooldown_remaining > 0.0:
			slot.cooldown_remaining = maxf(slot.cooldown_remaining - delta, 0.0)


func get_highest_priority_ready(source: Node2D) -> AbilityDefinition:
	## Returns the highest priority ability that is off cooldown and whose
	## conditions are met, or null if nothing is ready. Stored charges bypass
	## both cooldown and condition gating — a charged slot is always considered
	## ready (consumption is decided in commit_cast, not here).
	for slot in _slots:
		if slot.is_held:
			continue
		if has_ability_charge(slot.definition.ability_id):
			return slot.definition
		if slot.cooldown_remaining > 0.0:
			continue
		if _check_conditions(slot.definition, source):
			return slot.definition
	return null


func get_ready_abilities(source: Node2D) -> Array[AbilityDefinition]:
	## Returns all abilities that are off cooldown and whose conditions are met,
	## sorted by priority (highest first — _slots is pre-sorted). Stored charges
	## bypass cooldown and condition gating, so a charged slot is always ready
	## regardless of its natural state. Whether the charge is consumed on this
	## cast is decided later in commit_cast (natural-ready casts preserve the
	## bank).
	var result: Array[AbilityDefinition] = []
	for slot in _slots:
		if slot.is_held:
			continue
		if has_ability_charge(slot.definition.ability_id):
			result.append(slot.definition)
			continue
		if slot.cooldown_remaining > 0.0:
			continue
		if _check_conditions(slot.definition, source):
			result.append(slot.definition)
	return result


func start_cooldown(ability: AbilityDefinition) -> void:
	## Called after an ability fires. Applies modifier-driven CDR
	## (`sum_modifiers("All", "cooldown_reduce")`) — no attribute derivation.
	## cooldown_extend (bearer-side, tag "All") multiplies the final cooldown by
	## (1 + extend) so new cooldowns started while the bearer carries a
	## cooldown-drag-style status take longer to resolve. Stacks multiplicatively
	## AFTER flat + percent CDR, symmetric with how flat stacks before percent.
	## First consumer: Witch Doctor Inescapable's Cooldown Drag (Silence stepdown).
	var entity := get_parent()
	var cdr := 0.0
	var extend: float = 0.0
	if entity.has_node("ModifierComponent"):
		var mods: ModifierComponent = entity.get_node("ModifierComponent")
		cdr = clampf(mods.sum_modifiers("All", "cooldown_reduce"),
				0.0, AttributeDerivation.CDR_CAP)
		extend = maxf(0.0, mods.sum_modifiers("All", "cooldown_extend"))
	for slot in _slots:
		if slot.definition == ability:
			var base_cd: float = ability.cooldown_base
			var flat_reduce: float = _cooldown_flat_reductions.get(ability.ability_id, 0.0)
			slot.cooldown_remaining = maxf(0.0, base_cd - flat_reduce) * (1.0 - cdr) * (1.0 + extend)
			break


func get_auto_attack() -> AbilityDefinition:
	return _auto_attack


func register_ability_modification(target_ability_id: String,
		additional_effects: Array, on_displacement_arrival: bool = false,
		cooldown_flat_reduction: float = 0.0,
		source_name: String = "") -> void:
	## Register additional effects for an ability (from talents/items).
	## Multiple modifications on the same ability are supported.
	## on_displacement_arrival: effects fire at displacement arrival, not hit frame.
	## cooldown_flat_reduction: flat seconds subtracted from base cooldown.
	## source_name: provenance tag — empty for talents (preserves existing path),
	## "item_<item_id>" for items so dispatch sites can build HitData.contributors
	## lists per item-sourced group.
	var target_dict: Dictionary = _displacement_arrival_modifications if on_displacement_arrival else _ability_modifications
	if not additional_effects.is_empty():
		if not target_dict.has(target_ability_id):
			target_dict[target_ability_id] = []
		target_dict[target_ability_id].append(additional_effects)
		if not on_displacement_arrival:
			# Provenance only tracked for hit-frame mods (the dispatch sites we
			# instrument with contributors). Displacement-arrival mods can extend
			# the same pattern when an item-driven displacement consumer arrives.
			if not _ability_modification_sources.has(target_ability_id):
				_ability_modification_sources[target_ability_id] = []
			_ability_modification_sources[target_ability_id].append(source_name)
	if cooldown_flat_reduction > 0.0:
		var current: float = _cooldown_flat_reductions.get(target_ability_id, 0.0)
		_cooldown_flat_reductions[target_ability_id] = current + cooldown_flat_reduction


func replace_ability(target_ability_id: String, replacement: AbilityDefinition) -> void:
	## Wholly swap an ability (AA or skill slot) for `replacement`. Used by talents
	## that fundamentally transform a base ability (Wizard Kindle: Fire Bolt → Burn
	## applicator). Replacement should keep the same ability_id so attribution and
	## ability_modifications keyed by id stay coherent. Re-sorts skill slots by
	## priority and refreshes BehaviorComponent's AA interval when the AA is swapped.
	if replacement == null or target_ability_id == "":
		return
	if _auto_attack and _auto_attack.ability_id == target_ability_id:
		_auto_attack = replacement
		# Refresh AA interval: replacement's cooldown_base overrides Dex-derived
		# (matches entity setup_from_unit_def behavior). cooldown_base = 0 means
		# "use Dex-derived" — clear the override.
		var entity := get_parent()
		if entity and entity.has_node("BehaviorComponent"):
			var beh: BehaviorComponent = entity.get_node("BehaviorComponent")
			beh.set_aa_interval(replacement.cooldown_base)
		return
	for slot in _slots:
		if slot.definition and slot.definition.ability_id == target_ability_id:
			slot.definition = replacement
			# Re-sort by priority — replacement may have a different priority value
			_slots.sort_custom(func(a, b): return a.definition.priority > b.definition.priority)
			return
	# No local match — stash for summon spawns. Consumed by combat_manager at the
	# moment a summon of ours is spawned (Wizard Kindle → Fire Familiar's Fire Bolt).
	_summon_ability_replacements[target_ability_id] = replacement


func get_summon_ability_replacement(ability_id: String) -> AbilityDefinition:
	## Consulted by combat_manager._spawn_one_summon — if the summoner's talent
	## declared a replacement for this summon's ability_id, the summon swaps its
	## own AA/skill via its own replace_ability call.
	return _summon_ability_replacements.get(ability_id, null)


func get_ability_modifications(ability_id: String) -> Array:
	## Returns flat array of all additional effects for the given ability.
	if not _ability_modifications.has(ability_id):
		return []
	var result: Array = []
	for effect_group in _ability_modifications[ability_id]:
		result.append_array(effect_group)
	return result


func get_ability_modification_groups(ability_id: String) -> Array:
	## Returns Array of [source_name: String, effects: Array] per registered group
	## in registration order. Used by entity dispatch sites to fan out per-group
	## (and attach HitData.contributors lists for item-sourced groups). Talent
	## groups carry source_name = ""; item groups carry "item_<item_id>".
	if not _ability_modifications.has(ability_id):
		return []
	var groups: Array = []
	var srcs: Array = _ability_modification_sources.get(ability_id, [])
	var lists: Array = _ability_modifications[ability_id]
	for i in lists.size():
		var src_name: String = srcs[i] if i < srcs.size() else ""
		groups.append([src_name, lists[i]])
	return groups


func register_projectile_variant_overlay(target_ability_id: String,
		variants: Array) -> void:
	## Register per-projectile variants for an aimed_single SpawnProjectilesEffect
	## on the given ability. Multiple overlays on the same ability id accumulate
	## (concatenated). Called from combat_manager._apply_talent_ability_modifications
	## for any AbilityModification with a non-empty projectile_variants_overlay.
	if variants.is_empty():
		return
	if not _projectile_variant_overlays.has(target_ability_id):
		_projectile_variant_overlays[target_ability_id] = []
	for v in variants:
		if v is ProjectileVariantScript:
			_projectile_variant_overlays[target_ability_id].append(v)


func get_projectile_variant_overlay(ability_id: String) -> Array:
	## Returns the accumulated variant overlay array for the ability id, or [] if none.
	## Consumed by ProjectileManager when dispatching an aimed_single SpawnProjectilesEffect.
	if not _projectile_variant_overlays.has(ability_id):
		return []
	return _projectile_variant_overlays[ability_id]


func register_targeting_override(target_ability_id: String, rule: TargetingRule) -> void:
	## Register a talent-driven TargetingRule override for the given ability id.
	## Consumed by BehaviorComponent via get_effective_targeting. The original
	## AbilityDefinition is never mutated — overrides live per-entity on the
	## AbilityComponent so multiple entities of the same class can carry different
	## overrides without cross-contamination.
	if rule == null or target_ability_id == "":
		return
	_targeting_overrides[target_ability_id] = rule


func get_effective_targeting(ability: AbilityDefinition) -> TargetingRule:
	## Returns the talent-overridden targeting rule if one is registered for this
	## ability, otherwise the ability's own TargetingRule. Called by BehaviorComponent
	## during target resolution so talent overrides flow through the same dispatch.
	if ability == null:
		return null
	if _targeting_overrides.has(ability.ability_id):
		return _targeting_overrides[ability.ability_id]
	return ability.targeting


func has_targeting_override(ability_id: String) -> bool:
	## Used by BehaviorComponent._resolve_aa_targets to decide whether to attempt
	## target resolution even when the base ability has no targeting (future case).
	return _targeting_overrides.has(ability_id)


func apply_projectile_patch(ability_id: String, arc_height: float,
		no_flight_collision: bool) -> void:
	## Patch projectile-config fields on the live AbilityDefinition in the slot
	## matching ability_id. `arc_height < 0` = don't touch arc_height.
	## `no_flight_collision = false` is treated as "don't touch" — a talent that
	## wants to force flight collision off doesn't exist in the current design.
	## This keeps the patch additive: no talent's patch reverts a prior talent's.
	##
	## Runs against the slot's current definition (post-replacement) and on a
	## deep duplicate, so shared Resource instances (talent-owned, class-owned)
	## are never mutated. Per-entity ownership of the patched ability lets two
	## entities with different talent compositions carry different projectile
	## configs on the same ability_id without cross-contamination.
	##
	## Walks both `ability.effects` and every phase's `effects` inside the
	## ability's choreography (if any), so abilities like Conceal Strike with
	## SpawnProjectilesEffects buried in a phase can still receive patches.
	if arc_height < 0.0 and not no_flight_collision:
		return
	# Patch auto-attack
	if _auto_attack and _auto_attack.ability_id == ability_id:
		var new_aa: AbilityDefinition = _auto_attack.duplicate(true) as AbilityDefinition
		_patch_projectile_config_in_ability(new_aa, arc_height, no_flight_collision)
		_auto_attack = new_aa
		return
	# Patch skill slot
	for slot in _slots:
		if slot.definition and slot.definition.ability_id == ability_id:
			var new_def: AbilityDefinition = slot.definition.duplicate(true) as AbilityDefinition
			_patch_projectile_config_in_ability(new_def, arc_height, no_flight_collision)
			slot.definition = new_def
			return


func _patch_projectile_config_in_ability(ability: AbilityDefinition,
		arc_height: float, no_flight_collision: bool) -> void:
	## Helper for apply_projectile_patch. Walks the ability's effects array plus
	## any nested choreography phase effects arrays and patches every
	## SpawnProjectilesEffect's ProjectileConfig in place. The ability is
	## assumed to be a deep duplicate — mutation here is safe.
	_patch_projectile_config_in_effects(ability.effects, arc_height, no_flight_collision)
	if ability.choreography != null:
		for phase in ability.choreography.phases:
			_patch_projectile_config_in_effects(phase.effects, arc_height,
					no_flight_collision)


func _patch_projectile_config_in_effects(effects: Array, arc_height: float,
		no_flight_collision: bool) -> void:
	for effect in effects:
		if effect is SpawnProjectilesEffect and effect.projectile != null:
			if arc_height >= 0.0:
				effect.projectile.arc_height = arc_height
			if no_flight_collision:
				effect.projectile.no_flight_collision = true


func get_displacement_arrival_modifications(ability_id: String) -> Array:
	## Returns flat array of effects that fire at displacement arrival (not hit frame).
	if not _displacement_arrival_modifications.has(ability_id):
		return []
	var result: Array = []
	for effect_group in _displacement_arrival_modifications[ability_id]:
		result.append_array(effect_group)
	return result


func check_conditions(ability: AbilityDefinition, source: Node2D) -> bool:
	## Public wrapper for condition evaluation. Used by BehaviorComponent for AA conditions.
	return _check_conditions(ability, source)


func check_resource_cost(ability: AbilityDefinition, source: Node2D) -> bool:
	## Returns true if the entity can afford the ability's resource cost (or has none).
	if ability.resource_cost_status_id == "":
		return true
	var stacks: int = source.status_effect_component.get_stacks(ability.resource_cost_status_id)
	return stacks >= ability.resource_cost_amount


func consume_resource_cost(ability: AbilityDefinition, source: Node2D) -> void:
	## Consume the ability's resource cost. Called at commit time (after ability_requested).
	if ability.resource_cost_status_id == "":
		return
	source.status_effect_component.consume_stacks(
			ability.resource_cost_status_id, ability.resource_cost_amount)


func _check_conditions(ability: AbilityDefinition, source: Node2D) -> bool:
	## Evaluate ability conditions. All conditions must pass.
	if not check_resource_cost(ability, source):
		return false
	if ability.conditions.is_empty():
		return true
	for condition in ability.conditions:
		if condition is ConditionTakingDamage:
			var check_time: float
			if condition.required_tag != "":
				# Tag-filtered: check per-tag hit time dictionary
				var tag_times: Dictionary = source.get("_last_hit_time_by_tag")
				if tag_times == null or not tag_times.has(condition.required_tag):
					return false
				check_time = float(tag_times[condition.required_tag])
			else:
				var hit_time = source.get("last_hit_time")
				if hit_time == null:
					return false
				check_time = float(hit_time)
			# Use combat-local time (run_time in seconds) instead of wall clock
			var cm: Node2D = source.get("combat_manager")
			var now: float = cm.run_time if cm else 0.0
			var elapsed: float = now - check_time
			if elapsed >= condition.window:
				return false
		elif condition is ConditionHpThreshold:
			if not _check_hp_threshold(condition, source):
				return false
		elif condition is ConditionSummonCount:
			if not _check_summon_count(condition, source):
				return false
		elif condition is ConditionEntityCount:
			if not _check_entity_count(condition, source):
				return false
		elif condition is ConditionStackCount:
			if not _check_stack_count(condition, source):
				return false
		elif condition is ConditionCorpseExists:
			if not _check_corpse_exists(condition, source):
				return false
		elif condition is ConditionTargetingCount:
			if not _check_targeting_count(condition, source):
				return false
	return true


func extend_all_cooldowns(multiplier: float) -> void:
	## Multiply cooldown_remaining on every skill slot by `multiplier`. No-op on
	## slots currently at 0 (nothing to extend) and when multiplier <= 1.0 (the
	## natural baseline — no-op preserves the semantic "drag the cooldowns").
	## Paired with the cooldown_extend modifier: multiplier applies once at
	## dispatch time to ALREADY-ticking cooldowns; cooldown_extend keeps NEW
	## cooldowns (started while the bearer carries the extending status)
	## extended through start_cooldown / force_cooldown_by_id.
	## Does NOT touch the AA cadence — AA timers live on BehaviorComponent,
	## out of reach, mirroring refund_cooldown's all-slots mode convention.
	## First consumer: Cooldown Drag status's on_apply_effects via
	## ExtendActiveCooldownsEffect (Witch Doctor Inescapable — Silence stepdown).
	if multiplier <= 1.0:
		return
	for slot in _slots:
		if slot.cooldown_remaining > 0.0:
			slot.cooldown_remaining *= multiplier


func refund_cooldown(ability_id: String, seconds: float) -> void:
	## Subtract `seconds` from cooldown_remaining. Two modes:
	##   - Named ability (ability_id non-empty): refunds the single matching
	##     slot, no-op when not present. First consumer: Ranger Waste Not
	##     (6s on ranger_crippling_shot on priority kill).
	##   - All slots (ability_id == ""): refunds every slot owned by this
	##     entity. AA timer lives on BehaviorComponent and is out of reach
	##     (intentional — "all abilities" means all skill slots). First
	##     consumer: Ranger Fusillade (1s on all slots per crit during the
	##     8s window).
	## Clamped at 0 (cannot drive cooldown_remaining negative).
	if seconds <= 0.0:
		return
	if ability_id == "":
		for slot in _slots:
			slot.cooldown_remaining = maxf(0.0, slot.cooldown_remaining - seconds)
		return
	for slot in _slots:
		if slot.definition.ability_id == ability_id:
			slot.cooldown_remaining = maxf(0.0, slot.cooldown_remaining - seconds)
			return


func grant_ability_charge(ability_id: String, max_charges: int) -> void:
	## Bank one charge of the named ability, capped at `max_charges`. A charge
	## lets the owner fire the ability while its normal gates (cooldown,
	## ConditionStackCount, resource cost, all ability conditions) would block
	## it. No-op when already at cap or the ability isn't owned by this entity.
	## Silent — spillover grants aren't rejected loudly.
	## Dispatched by GrantAbilityChargeEffect; first consumer: Marked For Death.
	if ability_id == "" or max_charges <= 0:
		return
	var owns: bool = false
	for slot in _slots:
		if slot.definition.ability_id == ability_id:
			owns = true
			break
	if not owns:
		return
	var current: int = _ability_charges.get(ability_id, 0)
	if current >= max_charges:
		return
	_ability_charges[ability_id] = current + 1


func has_ability_charge(ability_id: String) -> bool:
	return _ability_charges.get(ability_id, 0) > 0


func get_ability_charges(ability_id: String) -> int:
	return _ability_charges.get(ability_id, 0)


func consume_ability_charge(ability_id: String) -> bool:
	## Decrement one charge. Returns true if a charge was consumed, false if
	## the counter was already 0.
	var cur: int = _ability_charges.get(ability_id, 0)
	if cur <= 0:
		return false
	_ability_charges[ability_id] = cur - 1
	return true


func is_normal_ready(ability: AbilityDefinition, source: Node2D) -> bool:
	## True when the ability would fire WITHOUT needing a stored charge — off
	## cooldown AND all conditions + resource cost pass. Called by commit_cast
	## to decide whether a charge is consumed or the normal cost+cooldown path
	## runs.
	for slot in _slots:
		if slot.definition == ability:
			if slot.cooldown_remaining > 0.0:
				return false
			break
	return _check_conditions(ability, source)


func commit_cast(ability: AbilityDefinition, source: Node2D) -> void:
	## Post-emit commit point for the BehaviorComponent. Atomically routes a
	## cast through EITHER the normal resource-cost + cooldown path OR the
	## stored-charge consumption path — never both. Natural-ready casts consume
	## resources and set cooldown; casts that made it into the ready list ONLY
	## because a charge bypassed the gates consume the charge instead. This
	## preserves the "stored charge lasts until it's actually needed" semantic
	## (Marked For Death's charge doesn't get burned on a Crippling Shot that
	## would have fired naturally on Focus + cooldown).
	if is_normal_ready(ability, source):
		consume_resource_cost(ability, source)
		start_cooldown(ability)
	else:
		consume_ability_charge(ability.ability_id)


func force_cooldown_by_id(ability_id: String) -> void:
	## Force an ability onto its base cooldown (with CDR). Used by summon death → resummon.
	var entity := get_parent()
	var cdr := 0.0
	var extend: float = 0.0
	if entity.has_node("ModifierComponent"):
		var mods: ModifierComponent = entity.get_node("ModifierComponent")
		cdr = clampf(mods.sum_modifiers("All", "cooldown_reduce"),
				0.0, AttributeDerivation.CDR_CAP)
		extend = maxf(0.0, mods.sum_modifiers("All", "cooldown_extend"))
	for slot in _slots:
		if slot.definition.ability_id == ability_id:
			var base_cd: float = slot.definition.cooldown_base
			var flat_reduce: float = _cooldown_flat_reductions.get(ability_id, 0.0)
			slot.cooldown_remaining = maxf(0.0, base_cd - flat_reduce) * (1.0 - cdr) * (1.0 + extend)
			break


func get_display_slots() -> Array[AbilitySlot]:
	return _display_slots


func _check_entity_count(condition: ConditionEntityCount, source: Node2D) -> bool:
	## Evaluate an entity count condition against the appropriate faction.
	var grid: SpatialGrid = source.spatial_grid
	if not grid:
		push_error("AbilityComponent: entity '%s' has no spatial_grid reference" % source.name)
		return false
	var check_faction: int
	match condition.faction:
		"enemy":
			check_faction = 1 if source.faction == source.Faction.HERO else 0
		"ally":
			check_faction = 0 if source.faction == source.Faction.HERO else 1
		_:
			return false

	if condition.range > 0.0:
		var range_sq: float = condition.range * condition.range
		var in_range := grid.get_nearby_in_range(source.position, check_faction, range_sq)
		# Exclude range: fail if any entity is closer than exclude_range
		if condition.exclude_range > 0.0:
			var exclude_sq: float = condition.exclude_range * condition.exclude_range
			for e in in_range:
				if source.position.distance_squared_to(e.position) < exclude_sq:
					return false
		if condition.requires_negative_status:
			var count: int = 0
			for e in in_range:
				if is_instance_valid(e) and e.is_alive \
						and e.status_effect_component.has_any_negative_status():
					count += 1
					if count >= condition.min_count:
						return true
			return false
		return in_range.size() >= condition.min_count
	else:
		var all := grid.get_all(check_faction)
		if condition.requires_negative_status:
			var count: int = 0
			for e in all:
				if is_instance_valid(e) and e.is_alive \
						and e.status_effect_component.has_any_negative_status():
					count += 1
					if count >= condition.min_count:
						return true
			return false
		return all.size() >= condition.min_count


func _check_hp_threshold(condition: ConditionHpThreshold, source: Node2D) -> bool:
	## Evaluate an HP threshold condition against the appropriate entity set.
	var grid: SpatialGrid = source.spatial_grid
	if not grid:
		push_error("AbilityComponent: entity '%s' has no spatial_grid reference" % source.name)
		return false
	var own_faction: int = 0 if source.faction == source.Faction.HERO else 1

	var entities_to_check: Array = []
	match condition.target:
		"self":
			entities_to_check = [source]
		"any_ally":
			entities_to_check = grid.get_all(own_faction)
		"any_enemy":
			var enemy_faction: int = 1 if source.faction == source.Faction.HERO else 0
			entities_to_check = grid.get_all(enemy_faction)
		_:
			return false

	for entity in entities_to_check:
		var hp_pct: float = entity.health.current_hp / entity.health.max_hp
		match condition.direction:
			"below":
				if hp_pct < condition.threshold:
					return true
			"above":
				if hp_pct > condition.threshold:
					return true
	return false


func _check_corpse_exists(condition: ConditionCorpseExists, source: Node2D) -> bool:
	## Evaluate whether any corpse of the specified faction exists.
	var cm: Node2D = source.get_parent()
	if not cm or not cm.get("corpses"):
		return false
	var check_faction: int
	match condition.faction:
		"ally":
			check_faction = int(source.faction)
		"enemy":
			check_faction = 1 if source.faction == source.Faction.HERO else 0
		_:
			return false
	for corpse in cm.corpses:
		if is_instance_valid(corpse) and int(corpse.faction) == check_faction:
			return true
	return false


func _check_stack_count(condition: ConditionStackCount, source: Node2D) -> bool:
	## Evaluate a stack count condition. Checks if target has stacks in [min_stacks, max_stacks].
	## max_stacks < 0 = no upper bound (backward compatible).
	match condition.target:
		"self":
			var stacks: int = source.status_effect_component.get_stacks(condition.status_id)
			if stacks < condition.min_stacks:
				return false
			if condition.max_stacks >= 0 and stacks > condition.max_stacks:
				return false
			return true
		"any_enemy":
			var grid: SpatialGrid = source.spatial_grid
			if not grid:
				return false
			var enemy_faction: int = 1 if source.faction == source.Faction.HERO else 0
			var enemies: Array = grid.get_all(enemy_faction)
			for e in enemies:
				var stacks: int = e.status_effect_component.get_stacks(condition.status_id)
				if stacks < condition.min_stacks:
					continue
				if condition.max_stacks >= 0 and stacks > condition.max_stacks:
					continue
				return true
			return false
		_:
			return false


func _check_summon_count(condition: ConditionSummonCount, source: Node2D) -> bool:
	## Evaluate a summon count condition. Counts living summons of summon_id on
	## the source and checks count in [min_count, max_count]. max_count < 0 = no upper bound.
	## Mirrors _check_stack_count's shape.
	var count: int = 0
	if source.get("_active_summons") != null and source._active_summons.has(condition.summon_id):
		var summon_list: Array = source._active_summons[condition.summon_id]
		for summon in summon_list:
			if is_instance_valid(summon) and summon.is_alive:
				count += 1
	if count < condition.min_count:
		return false
	if condition.max_count >= 0 and count > condition.max_count:
		return false
	return true


func _check_targeting_count(condition: ConditionTargetingCount, source: Node2D) -> bool:
	## Count enemies whose attack_target is this entity.
	var grid: SpatialGrid = source.spatial_grid
	if not grid:
		return false
	var enemy_faction: int = 1 if source.faction == source.Faction.HERO else 0
	var enemies: Array = grid.get_all(enemy_faction)
	var count: int = 0
	for e in enemies:
		if is_instance_valid(e) and e.is_alive and e.attack_target == source:
			count += 1
			if count >= condition.min_count:
				return true
	return false
