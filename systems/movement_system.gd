class_name MovementSystem
extends Node

const SEPARATION_RADIUS_SQ: float = 256.0
const MAX_SEPARATION_FORCE: float = 20.0
const SEPARATION_DAMPING: float = 0.8
const THREAT_WEIGHT: float = 30.0
const REPOSITION_THRESHOLD: float = 3.0
const SNAP_THRESHOLD: float = 1.0
const DISENGAGE_MULT: float = 1.2
const MOVE_ACCEL: float = 500.0

var spatial_grid: SpatialGrid
var current_scroll_speed: float = 0.0

var rng: RandomNumberGenerator

var _desired_positions: Dictionary = {}
var ground_y_range: Vector2 = Vector2(112, 148)


func _ready() -> void:
	rng = get_parent().rng


func update(delta: float, heroes: Array, enemies: Array) -> void:
	for entity in heroes:
		_move_entity(entity, delta)
	for entity in enemies:
		_move_entity(entity, delta)
	_update_facing(heroes, enemies)


func cleanup_entity(entity: Node2D) -> void:
	_desired_positions.erase(entity)


func _move_entity(entity: Node2D, delta: float) -> void:
	if entity.is_channeling:
		return
	if entity.is_attacking or entity._ability_anim_active:
		_tick_velocity_decay(entity, delta)
		return
	if _apply_movement_override(entity, delta):
		return
	if entity.status_effect_component.is_disabled():
		return
	if entity.status_effect_component.is_movement_disabled():
		return

	if entity.is_untargetable and entity.is_summon:
		var turret_engage: float = entity.get_engage_distance()
		var target := spatial_grid.find_nearest(entity.position, _opposing_faction(entity))
		if target and entity.position.distance_squared_to(target.position) <= turret_engage * turret_engage:
			entity.attack_target = target
			entity.in_combat = true
		else:
			entity.attack_target = null
			entity.in_combat = false
		return

	if entity.aggro_range > 0.0 and not entity.is_aggroed:
		var nearest := spatial_grid.find_nearest(entity.position, _opposing_faction(entity))
		if nearest and entity.position.distance_squared_to(nearest.position) <= entity.aggro_range * entity.aggro_range:
			entity.is_aggroed = true
		else:
			return

	var target_faction: int = _opposing_faction(entity)

	if entity.engagement_target != null:
		if not is_instance_valid(entity.engagement_target) or not entity.engagement_target.is_alive \
				or entity.engagement_target.is_untargetable:
			_clear_engagement(entity)

	if entity.engagement_target != null:
		entity.retarget_timer -= delta
		if entity.retarget_timer <= 0.0:
			entity.retarget_timer = entity.retarget_interval
			var new_target := _find_best_target(entity, target_faction)
			if new_target and new_target != entity.engagement_target:
				_set_engagement(entity, new_target)
				var slot_pos := new_target.position
				_update_desired_position(entity, slot_pos)
		if entity.position.distance_squared_to(entity.desired_position) > SNAP_THRESHOLD * SNAP_THRESHOLD:
			_track_desired_position(entity, delta, _get_effective_speed(entity))
		return

	var target := _find_best_target(entity, target_faction)
	if not target:
		if entity.is_summon and is_instance_valid(entity.summoner) and entity.summoner.is_alive:
			var return_pos: Vector2 = entity.summoner.position + Vector2(15, 0)
			_update_desired_position(entity, return_pos)
		else:
			_update_desired_position(entity, entity.formation_pos)
		entity.set_marching(true)
		if entity.position.distance_squared_to(entity.desired_position) > SNAP_THRESHOLD * SNAP_THRESHOLD:
			_track_desired_position(entity, delta, _get_effective_speed(entity))
		return

	var dist: float = entity.position.distance_to(target.position)
	var effective_engage: float = entity.get_engage_distance()
	if target.combat_role == target.CombatRole.MELEE:
		effective_engage = maxf(effective_engage, target.get_engage_distance())

	if dist <= effective_engage:
		_set_engagement(entity, target)
		entity.retarget_timer = entity.retarget_interval
		_update_desired_position(entity, target.position)
		if entity.position.distance_squared_to(entity.desired_position) > SNAP_THRESHOLD * SNAP_THRESHOLD:
			_track_desired_position(entity, delta, _get_effective_speed(entity))
	else:
		entity.set_marching(true)
		var move_dest: Vector2 = target.position
		var to_dest: Vector2 = move_dest - entity.position
		var effective_speed: float = _get_effective_speed(entity)
		entity.position += to_dest.normalized() * effective_speed * delta
		if entity.combat_role == entity.CombatRole.MELEE:
			var sep := _compute_separation(entity, entity.faction, target) * SEPARATION_DAMPING * delta
			entity.position += sep


func _opposing_faction(entity: Node2D) -> int:
	return SpatialGrid.ENEMY if entity.faction == entity.Faction.HERO else SpatialGrid.HERO


func _set_engagement(entity: Node2D, target: Node2D) -> void:
	if target == entity.engagement_target:
		return
	if entity.engagement_target != null:
		EventBus.on_proximity_exit.emit(entity, entity.engagement_target)
	entity.engagement_target = target
	entity.attack_target = target
	if target != null:
		entity.in_combat = true
		EventBus.on_proximity_enter.emit(entity, target)


func _clear_engagement(entity: Node2D, march: bool = true) -> void:
	if entity._ability_anim_active or entity.is_channeling:
		return
	if entity.engagement_target != null:
		var old_target: Node2D = entity.engagement_target
		entity.engagement_target = null
		EventBus.on_proximity_exit.emit(entity, old_target)
	entity.set_marching(march)


func _update_desired_position(entity: Node2D, new_pos: Vector2) -> void:
	if _desired_positions.has(entity):
		var old_pos: Vector2 = _desired_positions[entity]
		if old_pos.distance_squared_to(new_pos) < REPOSITION_THRESHOLD * REPOSITION_THRESHOLD:
			return
	_desired_positions[entity] = new_pos
	entity.desired_position = new_pos


func _track_desired_position(entity: Node2D, delta: float, speed: float) -> void:
	var to_target: Vector2 = entity.desired_position - entity.position
	var dist: float = to_target.length()
	var target_vel: Vector2
	if dist <= SNAP_THRESHOLD:
		target_vel = Vector2.ZERO
		if entity._velocity.length_squared() < 1.0:
			entity.position = entity.desired_position
			entity._velocity = Vector2.ZERO
			return
	else:
		target_vel = (to_target / dist) * speed
	entity._velocity = entity._velocity.move_toward(target_vel, MOVE_ACCEL * delta)
	entity.position += entity._velocity * delta


func _tick_velocity_decay(entity: Node2D, delta: float) -> void:
	if entity._velocity.is_zero_approx():
		entity._velocity = Vector2.ZERO
		return
	entity._velocity = entity._velocity.move_toward(Vector2.ZERO, MOVE_ACCEL * delta)
	entity.position += entity._velocity * delta


func _get_effective_speed(entity: Node2D) -> float:
	var base: float = entity.move_speed
	var bonus: float = entity.modifier_component.sum_modifiers("move_speed", "bonus")
	return base * maxf(0.0, 1.0 + bonus)


func _apply_movement_override(entity: Node2D, delta: float) -> bool:
	var override: String = entity.status_effect_component.get_movement_override()
	if override == "":
		return false

	var speed: float = _get_effective_speed(entity)
	match override:
		"flee_right":
			var flee_x: float = entity.position.x + speed * delta
			var drift_y: float = entity.position.y + rng.randf_range(-0.5, 0.5) * speed * delta
			drift_y = clampf(drift_y, ground_y_range.x, ground_y_range.y)
			entity.position = Vector2(flee_x, drift_y)
			if entity.engagement_target != null:
				_clear_engagement(entity)
			entity.set_marching(true)
			return true
		_:
			return false


func _find_taunt_override(entity: Node2D, target_faction: int) -> Node2D:
	var candidates := spatial_grid.get_all(target_faction)
	var best: Node2D = null
	var best_dist := INF
	for c in candidates:
		if not c.status_effect_component.has_taunt():
			continue
		var taunt_radius: float = c.status_effect_component.get_taunt_radius()
		var dist: float = entity.position.distance_to(c.position)
		if dist <= taunt_radius and dist < best_dist:
			best_dist = dist
			best = c
	return best


func _find_best_target(entity: Node2D, target_faction: int) -> Node2D:
	var taunt_override := _find_taunt_override(entity, target_faction)
	if taunt_override:
		return taunt_override
	var candidates := spatial_grid.get_all(target_faction)
	if candidates.is_empty():
		return null
	var best: Node2D = null
	var best_score: float = -INF
	for c in candidates:
		var dist: float = entity.position.distance_to(c.position)
		var threat: float = c.modifier_component.sum_modifiers("Threat", "add")
		var score: float = -dist + threat * THREAT_WEIGHT
		if score > best_score:
			best_score = score
			best = c
	return best


func _resolve_ranged_target(entity: Node2D, target_faction: int) -> Node2D:
	var taunt_override := _find_taunt_override(entity, target_faction)
	if taunt_override:
		return taunt_override
	var aa: AbilityDefinition = entity.ability_component.get_auto_attack()
	if aa and aa.targeting:
		match aa.targeting.type:
			"furthest_enemy":
				return spatial_grid.find_furthest(entity.position, target_faction)
	return _find_best_target(entity, target_faction)


func _update_facing(heroes: Array, enemies: Array) -> void:
	for e in heroes:
		e.update_facing()
	for e in enemies:
		e.update_facing()


func _compute_separation(entity: Node2D, faction: int, approach_target: Node2D = null) -> Vector2:
	var nearby := spatial_grid.get_nearby(entity.position, faction)
	var separation := Vector2.ZERO
	var has_approach := is_instance_valid(approach_target)
	var approach_dir := Vector2.ZERO
	if has_approach:
		approach_dir = (approach_target.position - entity.position).normalized()

	for neighbor in nearby:
		if neighbor == entity:
			continue
		var dist_sq := entity.position.distance_squared_to(neighbor.position)
		if dist_sq >= SEPARATION_RADIUS_SQ:
			continue
		var dist: float = sqrt(dist_sq)
		var radius: float = sqrt(SEPARATION_RADIUS_SQ)
		var strength: float = 1.0 - dist / radius
		if has_approach and approach_dir.length_squared() > 0.01:
			var to_n: Vector2 = neighbor.position - entity.position
			var to_neighbor: Vector2 = to_n.normalized() if to_n.length_squared() > 0.01 else Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			var cross: float = approach_dir.x * to_neighbor.y - approach_dir.y * to_neighbor.x
			var lateral_dir := Vector2(-approach_dir.y, approach_dir.x) * signf(cross)
			if absf(cross) < 0.001:
				lateral_dir = Vector2(-approach_dir.y, approach_dir.x)
			separation += lateral_dir * strength
		else:
			var away: Vector2 = entity.position - neighbor.position
			var push_dir: Vector2 = away.normalized() if away.length_squared() > 0.01 else Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			separation += push_dir * strength
	return separation.limit_length(MAX_SEPARATION_FORCE)
