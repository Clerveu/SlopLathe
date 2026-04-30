class_name BehaviorComponent
extends Node
## AI action loop: ability → auto-attack → move → idle.
## Owns auto-attack timer. Delegates targeting to combat_manager for spatial queries.

## Emitted when this entity wants to execute an ability on targets.
signal ability_requested(ability: AbilityDefinition, targets: Array)
## Emitted when auto-attack fires on the current attack_target.
signal auto_attack_requested(ability: AbilityDefinition, targets: Array)

const BASE_AA_INTERVAL := 0.5  ## Flat fallback auto-attack interval (seconds). No attribute derivation — attack_speed lives purely in the `attack_speed:bonus` modifier channel, entirely disjoint from the `cast_speed:bonus` channel used for non-AA ability animations.

var auto_attack_timer: float = 0.0
var _auto_attack_interval: float = BASE_AA_INTERVAL  ## Enemies override via aa_interval_override
var _aa_base_interval: float = 0.0  ## Override from AA definition's cooldown_base (0 = use _auto_attack_interval)
var _modifier_comp: ModifierComponent = null  ## Cached for attack_speed bonus queries
var _heal_reactive_target: Node2D = null  ## Most recently healed enemy (for heal-reactive targeting)
var _heal_reactive_connected: bool = false  ## Whether we're listening to on_heal


func setup(modifier_comp: ModifierComponent) -> void:
	_modifier_comp = modifier_comp


func enable_heal_reactive_targeting() -> void:
	## Connect to on_heal for heal-reactive targeting. Called during entity setup
	## when any ability uses the "most_recently_healed_enemy" targeting type.
	if _heal_reactive_connected:
		return
	_heal_reactive_connected = true
	EventBus.on_heal.connect(_on_heal_for_targeting)


func _on_heal_for_targeting(source: Node2D, target: Node2D, _amount: float,
		_attribution_tag: String = "") -> void:
	## Track enemy heals for heal-reactive targeting.
	var entity: Node2D = get_parent()
	if not entity.is_alive:
		return
	if not is_instance_valid(target) or not target.is_alive:
		return
	# Check if healed target is an enemy (from this entity's perspective)
	var enemy_faction: int = 1 if entity.faction == entity.Faction.HERO else 0
	if int(target.faction) == enemy_faction:
		_heal_reactive_target = target


func set_aa_interval(interval: float) -> void:
	## Override base AA interval from ability definition (e.g. Healing Words 1.0s).
	_aa_base_interval = interval
	auto_attack_timer = minf(auto_attack_timer, interval)


func _get_effective_aa_interval() -> float:
	## Returns auto-attack interval adjusted for attack_speed bonus modifiers.
	## Uses AA definition's cooldown_base when set, otherwise the flat base.
	## When using cooldown_base, also applies cooldown_reduce (CDR) modifiers
	## so abilities like Soul CDR affect AA rate.
	var base: float = _aa_base_interval if _aa_base_interval > 0.0 else _auto_attack_interval
	if _modifier_comp:
		var bonus: float = _modifier_comp.sum_modifiers("attack_speed", "bonus")
		if bonus != 0.0:
			var speed_mult: float = maxf(0.01, 1.0 + bonus)  # Floor at 1% to prevent div-by-zero
			base = base / speed_mult
		# Modifier-driven CDR applies to cooldown_base AAs (Healing Words, Wither)
		# alongside attack_speed. No attribute-derived CDR — the Int-derived path
		# was removed; gear/talents/statuses are the only CDR sources.
		if _aa_base_interval > 0.0:
			var cdr: float = clampf(
					_modifier_comp.sum_modifiers("All", "cooldown_reduce"),
					0.0, AttributeDerivation.CDR_CAP)
			if cdr > 0.0:
				base *= (1.0 - cdr)
	return base


func tick(delta: float, entity: Node2D) -> void:
	if not entity.is_alive or entity.is_channeling or entity.status_effect_component.is_disabled():
		return
	if entity.is_attacking:
		return  # Don't fire abilities during attack animations (prevents wasted cooldowns)

	var ability_comp: AbilityComponent = entity.ability_component
	var modifier_comp: ModifierComponent = entity.modifier_component

	# 1. Can I use an ability?
	# Silence (disables_abilities) gates only this step — AA and movement
	# continue. Iterate all ready abilities by priority — if the highest can't
	# resolve targets (e.g. Pick & Throw with no ranged enemies), try the next one.
	var needs_advance := false
	var ready_abilities: Array[AbilityDefinition] = []
	if not entity.status_effect_component.is_abilities_disabled():
		ready_abilities = ability_comp.get_ready_abilities(entity)
	for ability in ready_abilities:
		var targets := _resolve_targets(ability, entity)
		if targets.is_empty():
			# Advance on empty only for range-dependent targeting without a cluster filter.
			# Cluster filter empty = "target exists but not clustered" — don't advance.
			# Range-dependent empty (e.g. frontal_rectangle) = "nobody in range yet" — advance helps.
			if ability.cast_range > 0.0 and ability.targeting and ability.targeting.min_nearby <= 0:
				var grid: SpatialGrid = entity.spatial_grid
				if grid:
					var enemy_faction := 1 if entity.faction == entity.Faction.HERO else 0
					var nearest := grid.find_nearest(entity.position, enemy_faction)
					if nearest:
						entity.advance_for_cast_range = ability.cast_range
						entity.advance_cast_target = nearest
						needs_advance = true
			continue
		# Cast range check — must be within cast_range of at least one target
		if ability.cast_range > 0.0:
			var in_range := false
			for t in targets:
				if entity.position.distance_to(t.position) <= ability.cast_range:
					in_range = true
					break
			if not in_range:
				# Signal MovementSystem to advance, skip this ability for now
				entity.advance_for_cast_range = ability.cast_range
				entity.advance_cast_target = targets[0]
				needs_advance = true
				continue
		ability_requested.emit(ability, targets)
		ability_comp.commit_cast(ability, entity)
		auto_attack_timer = _get_effective_aa_interval()  # Reset AA timer
		entity.advance_for_cast_range = 0.0
		entity.advance_cast_target = null
		return
	# Clear advance flag if no ability needs it
	if not needs_advance:
		entity.advance_for_cast_range = 0.0
		entity.advance_cast_target = null

	# 2. Auto-attack timer
	if entity.in_combat:
		auto_attack_timer -= delta
		if auto_attack_timer <= 0.0:
			var aa := ability_comp.get_auto_attack()
			if aa:
				var aa_targets := _resolve_aa_targets(aa, entity)
				if not aa_targets.is_empty():
					auto_attack_requested.emit(aa, aa_targets)
					auto_attack_timer = _get_effective_aa_interval()
					return
			# No AA, no valid targets, or conditions failed — stay ready
			auto_attack_timer = 0.0
	else:
		# Not in combat — keep timer ready
		auto_attack_timer = 0.0

	# 3-4. Movement is handled by combat_manager (it owns spatial layout)
	# 5. Nothing to do — fire idle
	if not entity.is_attacking and not entity.in_combat:
		EventBus.on_idle.emit(entity)


func _resolve_aa_targets(aa: AbilityDefinition, entity: Node2D) -> Array:
	## Resolve targets for an auto-attack. Checks conditions, resolves from TargetingRule,
	## falls back to attack_target for simple damage AAs.
	if not aa.conditions.is_empty():
		if not entity.ability_component.check_conditions(aa, entity):
			return []
	if aa.targeting or entity.ability_component.has_targeting_override(aa.ability_id):
		var targets := _resolve_targets(aa, entity)
		if not targets.is_empty():
			return targets
	# Fallback: attack_target (backward compatible for AAs without explicit targeting)
	if is_instance_valid(entity.attack_target) and entity.attack_target.is_alive:
		return [entity.attack_target]
	return []


func resolve_targets_with_rule(rule: TargetingRule, entity: Node2D) -> Array:
	## Resolve targeting from an explicit rule. Used by hit-frame re-resolution
	## when hit_targeting differs from the ability's trigger targeting.
	return _resolve_targets_internal(rule, entity)


func _resolve_targets(ability: AbilityDefinition, entity: Node2D) -> Array:
	## Resolve targeting for an ability. Uses spatial_grid for proximity queries.
	## Consults AbilityComponent.get_effective_targeting so talent-driven
	## targeting_override (e.g. Ranger Hunter's Priority) replaces the ability's
	## base TargetingRule at resolve time without mutating the shared definition.
	var rule: TargetingRule = entity.ability_component.get_effective_targeting(ability)
	if not rule:
		return []
	return _resolve_targets_internal(rule, entity)


func _resolve_targets_internal(rule: TargetingRule, entity: Node2D) -> Array:
	var grid: SpatialGrid = entity.spatial_grid
	if not grid:
		push_error("BehaviorComponent: entity '%s' has no spatial_grid reference" % entity.name)
		return []
	if not rule:
		return []

	var enemy_faction := 1 if entity.faction == entity.Faction.HERO else 0
	var own_faction := 0 if entity.faction == entity.Faction.HERO else 1

	var results: Array = []
	match rule.type:
		"self":
			results = [entity]
		"nearest_enemy":
			var target := grid.find_nearest(entity.position, enemy_faction)
			results = [target] if target else []
		"nearest_enemies":
			var range_sq := rule.max_range * rule.max_range if rule.max_range > 0.0 else 0.0
			if range_sq > 0.0:
				results = grid.find_nearest_n(entity.position, enemy_faction, rule.max_targets, range_sq)
			else:
				var pool := grid.get_all(enemy_faction)
				pool = pool.duplicate()
				pool.sort_custom(func(a, b):
					return entity.position.distance_squared_to(a.position) < entity.position.distance_squared_to(b.position))
				if rule.max_targets > 0:
					results = pool.slice(0, mini(rule.max_targets, pool.size()))
				else:
					results = pool
		"furthest_enemy":
			var target := grid.find_furthest(entity.position, enemy_faction)
			results = [target] if target else []
		"highest_hp_enemy":
			var pool := grid.get_all(enemy_faction)
			var best: Node2D = null
			var best_hp := -1.0
			for e in pool:
				if e.health.current_hp > best_hp:
					best_hp = e.health.current_hp
					best = e
			results = [best] if best else []
		"self_centered_burst":
			var range_sq := rule.max_range * rule.max_range if rule.max_range > 0.0 else 0.0
			if range_sq > 0.0:
				results = grid.find_nearest_n(entity.position, enemy_faction, rule.max_targets, range_sq)
			else:
				results = grid.get_all(enemy_faction)
		"all_allies":
			results = grid.get_all(own_faction)
		"lowest_hp_ally":
			var allies := grid.get_all(own_faction)
			var lowest: Node2D = null
			var lowest_pct := INF
			for a in allies:
				var pct: float = a.health.current_hp / a.health.max_hp
				if pct < lowest_pct:
					lowest_pct = pct
					lowest = a
			results = [lowest] if lowest else []
		"frontal_rectangle":
			results = _resolve_frontal_rectangle(grid, entity, enemy_faction, rule)
		"grab_nearest_throw_furthest_ranged":
			results = _resolve_grab_throw(grid, entity, enemy_faction, rule.max_range)
		"nearest_enemy_targeting_owner":
			results = _resolve_nearest_enemy_targeting_owner(grid, entity, enemy_faction)
		"lowest_stacks_enemy":
			results = _resolve_lowest_stacks_enemy(grid, entity, enemy_faction, rule)
		"most_recently_healed_enemy":
			if is_instance_valid(_heal_reactive_target) and _heal_reactive_target.is_alive:
				results = [_heal_reactive_target]
				_heal_reactive_target = null  # Consumed — returns empty until next heal event
			else:
				_heal_reactive_target = null
				results = []
		"most_advanced_enemy":
			results = _resolve_most_advanced_enemy(grid, entity, enemy_faction)
		"priority_tiered_enemy":
			results = _resolve_priority_tiered_enemy(grid, entity, enemy_faction, rule)
		_:
			var target := grid.find_nearest(entity.position, enemy_faction)
			results = [target] if target else []

	# Post-resolution x-position filter: only accept targets within max_x_ratio of viewport
	if rule.max_x_ratio > 0.0 and not results.is_empty():
		var max_x: float = 320.0 * rule.max_x_ratio
		results = results.filter(func(e): return e.position.x <= max_x)

	# Post-resolution cluster filter: skip ability if target doesn't have enough nearby enemies
	if rule.min_nearby > 0 and not results.is_empty():
		var pivot: Node2D = results[0]
		var radius_sq: float = rule.nearby_radius * rule.nearby_radius
		var nearby := grid.get_nearby_in_range(pivot.position, enemy_faction, radius_sq)
		var others: int = nearby.size()
		for n in nearby:
			if n == pivot:
				others -= 1
				break
		if others < rule.min_nearby:
			return []

	return results


func _resolve_nearest_enemy_targeting_owner(grid: SpatialGrid, entity: Node2D,
		enemy_faction: int) -> Array:
	## Bodyguard targeting: prefer enemies whose attack_target is the owner.
	## Falls back to nearest enemy if no enemies are targeting the owner.
	if not entity.get("summoner") or not is_instance_valid(entity.summoner):
		var target := grid.find_nearest(entity.position, enemy_faction)
		return [target] if target else []
	var best: Node2D = null
	var best_dist_sq := INF
	var enemies := grid.get_all(enemy_faction)
	for e in enemies:
		if e.attack_target == entity.summoner:
			var d_sq := entity.position.distance_squared_to(e.position)
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				best = e
	if best:
		return [best]
	var target := grid.find_nearest(entity.position, enemy_faction)
	return [target] if target else []


func _resolve_lowest_stacks_enemy(grid: SpatialGrid, entity: Node2D,
		enemy_faction: int, rule: TargetingRule) -> Array:
	## Select the nearest enemy with the fewest stacks of target_status_id.
	## When all enemies have equal stacks, degenerates to nearest.
	var pool := grid.get_all(enemy_faction)
	if pool.is_empty():
		return []
	var status_id: String = rule.target_status_id
	var min_stacks: int = 0x7FFFFFFF
	var best: Node2D = null
	var best_dist_sq := INF
	for e in pool:
		var stacks: int = e.status_effect_component.get_stacks(status_id)
		if stacks < min_stacks:
			min_stacks = stacks
			best = e
			best_dist_sq = entity.position.distance_squared_to(e.position)
		elif stacks == min_stacks:
			var d_sq: float = entity.position.distance_squared_to(e.position)
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				best = e
	return [best] if best else []


func _resolve_frontal_rectangle(grid: SpatialGrid, entity: Node2D, enemy_faction: int,
		rule: TargetingRule) -> Array:
	## Frontal rectangle: enemies within max_range forward and ±(height/2) vertically.
	## Forward = right for heroes (flip_h false), left for enemies (flip_h true).
	var range_sq: float = rule.max_range * rule.max_range
	var half_height: float = rule.height / 2.0
	var candidates := grid.get_nearby_in_range(entity.position, enemy_faction, range_sq)
	var results: Array = []
	var facing_right: bool = not entity.sprite.flip_h
	for e in candidates:
		var dx: float = e.position.x - entity.position.x
		var dy: float = e.position.y - entity.position.y
		# Must be in the forward direction
		if facing_right and dx < 0.0:
			continue
		if not facing_right and dx > 0.0:
			continue
		# Must be within height band
		if absf(dy) > half_height:
			continue
		results.append(e)
	return results


func _resolve_grab_throw(grid: SpatialGrid, entity: Node2D, enemy_faction: int,
		max_range: float) -> Array:
	## Pick & Throw: returns [nearest_enemy, furthest_ranged_enemy].
	## Returns empty if no ranged enemies exist or nearest enemy is out of grab range.
	var pool := grid.get_all(enemy_faction)
	if pool.is_empty():
		return []

	# Must have at least one ranged enemy
	var furthest_ranged: Node2D = null
	var furthest_dist_sq := -1.0
	for e in pool:
		if e.combat_role == e.CombatRole.RANGED:
			var d_sq := entity.position.distance_squared_to(e.position)
			if d_sq > furthest_dist_sq:
				furthest_dist_sq = d_sq
				furthest_ranged = e
	if not furthest_ranged:
		return []

	# Nearest enemy (any type) — must be within grab range
	var grab_range: float = max_range if max_range > 0.0 else entity.get_engage_distance()
	var grab_range_sq := grab_range * grab_range
	var nearest := grid.find_nearest(entity.position, enemy_faction)
	if not nearest:
		return []
	if entity.position.distance_squared_to(nearest.position) > grab_range_sq:
		return []

	return [nearest, furthest_ranged]


func _resolve_most_advanced_enemy(grid: SpatialGrid, entity: Node2D,
		enemy_faction: int) -> Array:
	## Select the enemy deepest into hero territory (lowest X position).
	## Ties broken by nearest to caster.
	var pool := grid.get_all(enemy_faction)
	if pool.is_empty():
		return []
	var best: Node2D = null
	var best_x := INF
	var best_dist_sq := INF
	for e in pool:
		if e.position.x < best_x:
			best_x = e.position.x
			best = e
			best_dist_sq = entity.position.distance_squared_to(e.position)
		elif e.position.x == best_x:
			var d_sq: float = entity.position.distance_squared_to(e.position)
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				best = e
	return [best] if best else []


func _resolve_priority_tiered_enemy(grid: SpatialGrid, entity: Node2D,
		enemy_faction: int, rule: TargetingRule) -> Array:
	## Walk the rule's priority_tiers in order. For each tier, collect all enemies
	## matching that tier classification and pick the nearest. First tier with any
	## candidates wins — lower tiers are not consulted. When no tier matches,
	## falls back to nearest_enemy. Tier semantics live in TargetingRule's static
	## matcher so every consumer (targeting, trigger conditions) classifies the
	## same way. First consumer: Ranger Hunter's Priority.
	##
	## Scale: O(pool_size × tiers). Pool is already pre-filtered to alive enemies
	## by the spatial grid. At 300x density with <=5 tiers, this is a single
	## low-hundreds-iteration pass — no sqrt, no per-frame allocations beyond the
	## result array.
	var pool: Array = grid.get_all(enemy_faction)
	if pool.is_empty():
		return []
	for tier in rule.priority_tiers:
		var best: Node2D = null
		var best_dist_sq: float = INF
		for e in pool:
			if not TargetingRule.entity_matches_priority_tier(e, tier):
				continue
			var d_sq: float = entity.position.distance_squared_to(e.position)
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				best = e
		if best:
			return [best]
	# Fallback: nearest enemy (no priority tier matched)
	var nearest: Node2D = grid.find_nearest(entity.position, enemy_faction)
	return [nearest] if nearest else []
