class_name GroundZone
extends Node2D
## Persistent ground zone. Applies effects to entities within radius each tick.
## Created by EffectDispatcher, parented to combat_manager, ticked by combat_manager.
## Visuals come from effect.vfx_layers (particle presets spawned on birth).

var zone_id: String = ""
var radius: float = 20.0
var target_faction: String = "enemy"
var tick_effects: Array = []
var source: Node2D = null  ## Who created the zone (for effect scaling)
var is_expired: bool = false

var _time_remaining: float = 0.0
var _tick_timer: float = 0.0
var _tick_interval: float = 0.5
var _combat_manager: Node2D = null
var _particle_slots: Array[int] = []  ## Looping particle slots to release on expire
var _debug_color: Color = Color(0, 0, 0, 0)  ## When alpha > 0, zone self-draws a ring (fallback visual when no VFX authored)


func setup(effect: GroundZoneEffect, p_source: Node2D, pos: Vector2,
		combat_manager: Node2D) -> void:
	set_process(false)  # Ticked explicitly by combat_manager
	set_physics_process(false)
	zone_id = effect.zone_id
	radius = effect.radius
	target_faction = effect.target_faction
	tick_effects = effect.tick_effects.duplicate()
	source = p_source
	_time_remaining = effect.duration
	_tick_interval = effect.tick_interval
	_tick_timer = 0.0  ## Tick immediately on first frame
	_combat_manager = combat_manager
	position = pos
	z_index = -10  ## Draw below entities
	_debug_color = effect.debug_color
	_dispatch_vfx_layers(effect.vfx_layers)
	if _debug_color.a > 0.0:
		queue_redraw()


func _draw() -> void:
	## Self-rendered ring for zones that opt in via GroundZoneEffect.debug_color.
	## Drawn in zone-local space (zone sits at world position). Fill is alpha-faded
	## from the configured color; outline uses the full-alpha color.
	if _debug_color.a <= 0.0:
		return
	var fill := Color(_debug_color.r, _debug_color.g, _debug_color.b, _debug_color.a * 0.35)
	draw_circle(Vector2.ZERO, radius, fill)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, _debug_color, 1.0)


func _dispatch_vfx_layers(layers: Array) -> void:
	## Spawn particle VFX on zone birth. One-shot presets auto-release via the
	## finished signal; looping presets are tracked and released on zone expire.
	if layers.is_empty() or not _combat_manager:
		return
	var pm = _combat_manager.particle_manager
	if not pm:
		return
	for layer in layers:
		if layer is ParticleVfxLayerConfig:
			var slot: int = pm.claim(layer.preset, position + layer.offset,
					_combat_manager, false, layer.z_index)
			if slot >= 0 and not layer.preset.one_shot:
				_particle_slots.append(slot)


func release_vfx() -> void:
	## Release all tracked looping particle slots back to the pool.
	## Called by combat_manager before queue_free. Safe to call multiple times.
	if not _combat_manager:
		return
	var pm = _combat_manager.particle_manager
	if not pm:
		return
	for slot in _particle_slots:
		pm.release(slot)
	_particle_slots.clear()


func tick(delta: float) -> void:
	if is_expired:
		return

	_time_remaining -= delta
	if _time_remaining <= 0.0:
		is_expired = true
		return

	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer += _tick_interval
		_apply_tick_effects()


func _apply_tick_effects() -> void:
	if tick_effects.is_empty() or not _combat_manager:
		return
	var grid: SpatialGrid = _combat_manager.spatial_grid
	if not grid:
		return

	# Resolve target faction relative to source
	var faction_id: int
	if not is_instance_valid(source):
		# Source dead — use faction string directly (enemy = 1, ally = 0)
		faction_id = 1 if target_faction == "enemy" else 0
	else:
		match target_faction:
			"enemy":
				faction_id = 1 - int(source.faction)
			"ally":
				faction_id = int(source.faction)
			_:
				return

	var range_sq: float = radius * radius
	var targets: Array = grid.get_nearby_in_range(position, faction_id, range_sq)

	# Use source for scaling; fallback_source = null (zone effects shouldn't need it)
	for target in targets:
		if not target.is_alive:
			continue
		for effect in tick_effects:
			EffectDispatcher.execute_effect(effect, source, target, null,
					_combat_manager, null)
