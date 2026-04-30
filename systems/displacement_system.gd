class_name DisplacementSystem
extends Node
## Manages entity displacement: throws, knockbacks, pulls, charges, teleports.
## Child of combat_manager (needs Node for tween creation).
## Same pattern as ProjectileManager — owned by combat_manager, delegates to for specific work.

## Screen bounds for clamping displacement destinations
const BOUNDS_MIN_X := 0.0
const BOUNDS_MAX_X := 310.0  ## Slight margin from 320px viewport edge
const BOUNDS_MIN_Y := 100.0  ## Top of play area
const BOUNDS_MAX_Y := 160.0  ## Bottom of play area

var slot_manager = null
var level_bounds = null
var rng: RandomNumberGenerator  ## Set from combat_manager.rng in _ready()


func _ready() -> void:
	rng = get_parent().rng


func execute(source: Node2D, ability: AbilityDefinition,
		effect: DisplacementEffect, targets: Array) -> void:
	## Begin a displacement. Determines who moves and where, sets up the tween.
	var displaced_entity: Node2D
	var destination_entity: Node2D = null

	if effect.displaced == "self":
		displaced_entity = source
		destination_entity = targets[0] if not targets.is_empty() else null
	else:
		# "target" — targets[0] is displaced, targets[1] is destination
		if targets.is_empty():
			return
		displaced_entity = targets[0]
		destination_entity = targets[1] if targets.size() > 1 else null

	if not is_instance_valid(displaced_entity) or not displaced_entity.is_alive:
		return

	# Anchored check: entity is immune to displacement (Immovable Object, etc.)
	if displaced_entity.modifier_component.has_negation("Displacement"):
		EventBus.on_displacement_resisted.emit(displaced_entity, source)
		return

	# For "to_target" destination, we need a valid destination entity
	if effect.destination == "to_target":
		if not is_instance_valid(destination_entity) or not destination_entity.is_alive:
			return

	# Cancel projectile tracking so in-flight projectiles land at the
	# entity's pre-displacement position instead of following mid-flight
	var cm: Node2D = get_parent()
	if cm and cm.get("projectile_manager"):
		cm.projectile_manager.clear_tracking_target(displaced_entity)

	# Release engagement slots before displacement
	if slot_manager:
		slot_manager.release_slot_from_all(displaced_entity)

	# Compute start and end positions
	var start_pos: Vector2 = displaced_entity.position

	# Teleport to source if configured (Pick & Throw "grab")
	if effect.teleport_to_source and is_instance_valid(source):
		displaced_entity.position = source.position
		start_pos = source.position

	var end_pos: Vector2 = _compute_end_position(
			displaced_entity, source, destination_entity, effect)

	# Instant motion: reposition immediately, no tween, no channeling suppression.
	# Used by Blink and future teleport abilities where the entity is already
	# mid-animation (managed by entity.gd's two-phase animation system).
	if effect.motion == "instant":
		displaced_entity.position = end_pos
		displaced_entity._last_position = end_pos  # Prevent phantom facing from position delta
		_on_arrival(source, displaced_entity, destination_entity, ability, effect)
		return

	# Suppress displaced entity during flight (non-instant only)
	displaced_entity.is_channeling = true
	displaced_entity.is_attacking = false

	# Play custom animation during flight if specified (e.g. jump for Conceal Strike)
	if effect.displacement_animation != "":
		displaced_entity.sprite.play(effect.displacement_animation)

	# Create the motion tween
	var tween := create_tween()

	# Spawn-intro scroll-anchoring: when the displaced entity requested scroll-
	# drift during the choreography, capture distance_traveled at tween start so
	# the arc's start/end anchors can be pushed left each frame in lockstep with
	# the background. Non-spawn-intro displacements leave this at -INF → zero
	# drift applied, existing semantics preserved.
	var scroll_anchor_start_distance: float = -INF
	if displaced_entity.get("_channel_scroll_anchor") == true:
		var cm_ref: Node2D = get_parent()
		if cm_ref and cm_ref.has_method("_advance_simulation"):
			scroll_anchor_start_distance = cm_ref.distance_traveled

	if effect.motion == "arc":
		_tween_arc(tween, displaced_entity, start_pos, end_pos,
				effect.arc_height, effect.duration, scroll_anchor_start_distance)
	else:
		_tween_linear(tween, displaced_entity, start_pos, end_pos, effect.duration,
				scroll_anchor_start_distance)

	if effect.rotate:
		tween.parallel().tween_property(
				displaced_entity.sprite, "rotation", TAU, effect.duration)

	# On arrival
	tween.tween_callback(func() -> void:
		_on_arrival(source, displaced_entity, destination_entity, ability, effect)
	)


func _compute_end_position(displaced: Node2D, source: Node2D,
		destination: Node2D, effect: DisplacementEffect) -> Vector2:
	var dist: float = effect.distance
	if effect.distance_min > 0.0 and effect.distance_min < effect.distance:
		dist = rng.randf_range(effect.distance_min, effect.distance)

	var end_pos: Vector2 = displaced.position
	match effect.destination:
		"to_target":
			end_pos = destination.position
		"away_from_source":
			var dir := Vector2.LEFT
			if is_instance_valid(source):
				dir = (displaced.position - source.position).normalized()
				if dir == Vector2.ZERO:
					dir = Vector2.LEFT
			end_pos = displaced.position + dir * dist
		"toward_source":
			if is_instance_valid(source):
				var dir := (source.position - displaced.position).normalized()
				var clamped_dist := minf(dist, displaced.position.distance_to(source.position))
				end_pos = displaced.position + dir * clamped_dist
		"relative_offset":
			end_pos = displaced.position + effect.relative_offset
		"random_away":
			end_pos = _compute_random_away(displaced, dist, effect.distance_min)

	if level_bounds and not displaced._channel_scroll_anchor:
		end_pos = level_bounds.clamp_displacement_dest(end_pos)
	return end_pos


func _compute_random_away(displaced: Node2D, dist: float, min_dist: float) -> Vector2:
	## Compute a random displacement away from the entity's last melee attacker.
	## Picks a random direction within ±90° of the "away" vector, random distance,
	## clamped to play area bounds. Retries if clamping shrinks distance below minimum.
	var away_dir := Vector2.RIGHT  # Default if no attacker
	if is_instance_valid(displaced.get("last_hit_by")) and displaced.last_hit_by.is_alive:
		away_dir = (displaced.position - displaced.last_hit_by.position).normalized()
		if away_dir == Vector2.ZERO:
			away_dir = Vector2.RIGHT

	var best_pos := displaced.position
	var best_dist_sq := 0.0
	var min_dist_sq: float = min_dist * min_dist

	for _attempt in 8:
		# Random angle within ±90° of away direction
		var spread: float = rng.randf_range(-PI * 0.5, PI * 0.5)
		var dir := away_dir.rotated(spread)
		var candidate := displaced.position + dir * dist
		if level_bounds:
			candidate = level_bounds.clamp_displacement_dest(candidate)
		else:
			candidate.x = clampf(candidate.x, BOUNDS_MIN_X, BOUNDS_MAX_X)
			candidate.y = clampf(candidate.y, BOUNDS_MIN_Y, BOUNDS_MAX_Y)
		var d_sq: float = displaced.position.distance_squared_to(candidate)
		if d_sq >= min_dist_sq:
			return candidate
		# Track best attempt in case all are too short
		if d_sq > best_dist_sq:
			best_dist_sq = d_sq
			best_pos = candidate

	return best_pos


func _tween_arc(tween: Tween, entity: Node2D, start: Vector2, end: Vector2,
		height: float, dur: float, scroll_anchor_start_distance: float = -INF) -> void:
	# Entity position stays on the ground path (linear start→end); only the Sprite
	# child is lifted by the arc offset. Keeps ShadowSprite — sibling at local (0,0) —
	# tracking the ground trajectory instead of arcing through the air with the thrown
	# entity. arc_offset returns to 0 at t=1, so sprite.position.y self-resets on land.
	# scroll_anchor_start_distance != -INF: subtract accumulated scroll from start/end
	# each frame so a water-spawn arc lands on the same texture pixel, not on-screen pixel.
	var sprite: Node2D = entity.get_node_or_null("Sprite")
	var cm_ref: Node2D = get_parent()
	tween.tween_method(func(t: float) -> void:
		if not is_instance_valid(entity):
			return
		var drift: float = 0.0
		if scroll_anchor_start_distance != -INF and cm_ref:
			drift = cm_ref.distance_traveled - scroll_anchor_start_distance
		var drift_off := Vector2(drift, 0.0)
		entity.position = (start - drift_off).lerp(end - drift_off, t)
		if sprite:
			sprite.position.y = -4.0 * height * t * (1.0 - t)
	, 0.0, 1.0, dur)


func _tween_linear(tween: Tween, entity: Node2D, start: Vector2, end: Vector2,
		dur: float, scroll_anchor_start_distance: float = -INF) -> void:
	var cm_ref: Node2D = get_parent()
	tween.tween_method(func(t: float) -> void:
		if not is_instance_valid(entity):
			return
		var drift: float = 0.0
		if scroll_anchor_start_distance != -INF and cm_ref:
			drift = cm_ref.distance_traveled - scroll_anchor_start_distance
		var drift_off := Vector2(drift, 0.0)
		entity.position = (start - drift_off).lerp(end - drift_off, t)
	, 0.0, 1.0, dur)


func _on_arrival(source: Node2D, displaced: Node2D, destination: Node2D,
		ability: AbilityDefinition, effect: DisplacementEffect) -> void:
	## Displacement complete. Reset state, apply arrival effects, bounce.

	# Reset displaced entity state
	if is_instance_valid(displaced):
		displaced.sprite.rotation = 0.0
		displaced.is_channeling = false

	var source_alive: bool = is_instance_valid(source) and source.is_alive

	# Effects on displaced entity
	if is_instance_valid(displaced) and displaced.is_alive:
		for e in effect.on_arrival_displaced_effects:
			EffectDispatcher.execute_effect(e, source, displaced, ability, get_parent())
		for e in effect.on_arrival_both_effects:
			EffectDispatcher.execute_effect(e, source, displaced, ability, get_parent())

	# Effects on destination entity
	if is_instance_valid(destination) and destination.is_alive:
		for e in effect.on_arrival_destination_effects:
			EffectDispatcher.execute_effect(e, source, destination, ability, get_parent())
		for e in effect.on_arrival_both_effects:
			EffectDispatcher.execute_effect(e, source, destination, ability, get_parent())

	# Dispatch talent/item displacement arrival modifications (e.g. Seismic Throw ground zone)
	if ability and is_instance_valid(source) and source.is_alive:
		var arrival_mods: Array = source.ability_component.get_displacement_arrival_modifications(ability.ability_id)
		if not arrival_mods.is_empty():
			var arrival_targets: Array = []
			if is_instance_valid(displaced):
				arrival_targets.append(displaced)
			if is_instance_valid(destination) and destination != displaced:
				arrival_targets.append(destination)
			EffectDispatcher.execute_effects(arrival_mods, source, arrival_targets,
					ability, get_parent())

	# Bounce toward the source (thrower). At arrival the displaced entity is on top of
	# the destination, so displaced-vs-destination gives a near-zero junk vector.
	if effect.bounce_distance > 0.0 and is_instance_valid(displaced) and displaced.is_alive:
		var bounce_dir: Vector2
		if is_instance_valid(source):
			bounce_dir = (source.position - displaced.position).normalized()
		else:
			bounce_dir = Vector2.LEFT
		if bounce_dir == Vector2.ZERO:
			bounce_dir = Vector2.LEFT
		var bounce_tween := create_tween()
		bounce_tween.tween_property(displaced, "position",
				displaced.position + bounce_dir * effect.bounce_distance,
				0.2).set_ease(Tween.EASE_OUT)
