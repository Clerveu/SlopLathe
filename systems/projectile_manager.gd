class_name ProjectileManager
extends Node2D
## Centralized projectile manager. Replaces individual Projectile nodes with
## parallel-array state and pooled rendering via _draw().
##
## Eliminates per-projectile Node2D overhead: no _process() per node, no
## AnimatedSprite2D children, no queue_free()/new() churn. All projectile
## movement, hit detection, and rendering in one place.
##
## Owned by combat_manager. Consumes SpatialGrid for hit detection.

const POOL_SIZE := 512

const ProjectileVariantScript = preload("res://data/projectile_variant.gd")

## 8-direction names indexed by angle sector (same as Projectile.DIR_NAMES).
const DIR_NAMES: Array[String] = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]

## Screen bounds for expiry (matches old projectile.gd margins).
const BOUNDS_MIN_X := -20.0
const BOUNDS_MAX_X := 340.0
const BOUNDS_MIN_Y := -20.0
const BOUNDS_MAX_Y := 200.0

var spatial_grid: SpatialGrid  ## Set by combat_manager after creation
var combat_manager: Node2D          ## Back-reference for impact VFX spawning

# --- Pool state ---
var _count: int = 0            ## High-water mark (iterate 0.._count-1)
var _free_list: Array[int] = []  ## Stack of dead slot indices

# --- Parallel arrays: core state ---
var _positions: PackedVector2Array
var _velocities: PackedVector2Array     # direction * speed (precomputed)
var _factions: PackedInt32Array
var _target_factions: PackedInt32Array
var _distances: PackedFloat32Array      # distance traveled (for max_range)
var _hit_radius_sqs: PackedFloat32Array
var _alive: PackedByteArray
var _speeds: PackedFloat32Array         # raw speed (for distance tracking)
var _max_ranges: PackedFloat32Array
var _motion_types: PackedInt32Array     # 0=directional, 1=aimed, 2=homing

# --- References (can't go in packed arrays) ---
var _configs: Array = []                # ProjectileConfig per slot
var _sources: Array = []                # Node2D (who fired)
var _abilities: Array = []              # AbilityDefinition per slot
var _targets: Array = []                # Node2D (homing/arc tracking target)

# --- Arc state ---
var _arc_starts: PackedVector2Array
var _arc_ends: PackedVector2Array
var _arc_times: PackedFloat32Array
var _arc_durations: PackedFloat32Array
var _arc_heights: PackedFloat32Array

# --- Pierce tracking ---
var _hit_lists: Array = []              # Array[Array] per slot
var _pierce_counts: PackedInt32Array

# --- Rendering state ---
var _textures: Array = []               # Texture2D per slot (resolved at spawn)
var _visual_scales: PackedVector2Array
var _rotations: PackedFloat32Array

# --- Impact VFX config ---
var _impact_sprite_frames: Array = []   # SpriteFrames or null
var _impact_animations: Array = []      # String
var _impact_visual_scales: PackedVector2Array

# --- Per-slot variant overrides ---
# Default to config values on every spawn path (initialized in _init_pool + re-set on
# every spawn call). Variant spawns override these per-slot so per-projectile damage
# and splash radius scale independently of the shared ProjectileConfig.
var _impact_aoe_radii: PackedFloat32Array    # Per-projectile splash radius (copies config.impact_aoe_radius by default)
var _damage_multipliers: PackedFloat32Array  # Per-projectile power_multiplier threaded through EffectDispatcher
var _echo_sources: Array = []                # Per-projectile EchoSourceConfig (null = not an echo). Carried to on-hit dispatch so DealDamage suppresses crit + stamps HitData.is_echo per config.

# Motion type constants
const MOTION_DIRECTIONAL := 0
const MOTION_AIMED := 1
const MOTION_HOMING := 2


func _ready() -> void:
	_init_pool()


func _init_pool() -> void:
	_positions.resize(POOL_SIZE)
	_velocities.resize(POOL_SIZE)
	_factions.resize(POOL_SIZE)
	_target_factions.resize(POOL_SIZE)
	_distances.resize(POOL_SIZE)
	_hit_radius_sqs.resize(POOL_SIZE)
	_alive.resize(POOL_SIZE)
	_speeds.resize(POOL_SIZE)
	_max_ranges.resize(POOL_SIZE)
	_motion_types.resize(POOL_SIZE)

	_arc_starts.resize(POOL_SIZE)
	_arc_ends.resize(POOL_SIZE)
	_arc_times.resize(POOL_SIZE)
	_arc_durations.resize(POOL_SIZE)
	_arc_heights.resize(POOL_SIZE)

	_pierce_counts.resize(POOL_SIZE)
	_visual_scales.resize(POOL_SIZE)
	_rotations.resize(POOL_SIZE)

	_configs.resize(POOL_SIZE)
	_sources.resize(POOL_SIZE)
	_abilities.resize(POOL_SIZE)
	_targets.resize(POOL_SIZE)
	_hit_lists.resize(POOL_SIZE)
	_textures.resize(POOL_SIZE)
	_impact_sprite_frames.resize(POOL_SIZE)
	_impact_animations.resize(POOL_SIZE)
	_impact_visual_scales.resize(POOL_SIZE)
	_impact_aoe_radii.resize(POOL_SIZE)
	_damage_multipliers.resize(POOL_SIZE)
	_echo_sources.resize(POOL_SIZE)

	# Zero out packed arrays and fill reference arrays with null
	for i in POOL_SIZE:
		_alive[i] = 0
		_configs[i] = null
		_sources[i] = null
		_abilities[i] = null
		_targets[i] = null
		_hit_lists[i] = []
		_textures[i] = null
		_impact_sprite_frames[i] = null
		_impact_animations[i] = ""
		_impact_visual_scales[i] = Vector2.ONE
		_impact_aoe_radii[i] = 0.0
		_damage_multipliers[i] = 1.0
		_echo_sources[i] = null


func _claim_slot() -> int:
	if not _free_list.is_empty():
		return _free_list.pop_back()
	if _count < POOL_SIZE:
		var slot := _count
		_count += 1
		return slot
	push_warning("ProjectileManager: pool exhausted (%d slots)" % POOL_SIZE)
	return -1


func _release_slot(i: int) -> void:
	_alive[i] = 0
	# Clear references to avoid holding stale Node2D refs
	_sources[i] = null
	_abilities[i] = null
	_targets[i] = null
	_configs[i] = null
	_textures[i] = null
	_hit_lists[i].clear()
	_impact_sprite_frames[i] = null
	_echo_sources[i] = null
	_free_list.append(i)


# --- Spawning ---

func spawn(source: Node2D, ability: AbilityDefinition,
		config: ProjectileConfig, direction: Vector2,
		tracking_target: Node2D, offset: Vector2,
		echo_source: EchoSourceConfig = null) -> int:
	## Returns the claimed slot index (for callers that need to apply per-slot
	## overrides after spawn), or -1 if the pool is exhausted. echo_source (non-null)
	## marks this projectile as an echo replay — on-hit DealDamage will pass it
	## through so DamageCalculator can suppress crit and HitData.is_echo gets set.
	var i := _claim_slot()
	if i < 0:
		return -1

	_alive[i] = 1
	_positions[i] = source.position + offset
	_speeds[i] = config.speed
	_max_ranges[i] = config.max_range
	_distances[i] = 0.0
	_hit_radius_sqs[i] = config.hit_radius * config.hit_radius
	_factions[i] = source.faction
	_target_factions[i] = 1 if source.faction == 0 else 0
	_velocities[i] = direction * config.speed
	# Rotate non-directional sprites to match trajectory (E-facing base = angle 0)
	# Directional-anim sprites (8-dir) handle facing via sprite selection, not rotation
	if not config.use_directional_anims:
		_rotations[i] = direction.angle()
	else:
		_rotations[i] = 0.0

	_configs[i] = config
	_sources[i] = source
	_abilities[i] = ability
	_targets[i] = tracking_target
	_hit_lists[i] = []
	_pierce_counts[i] = config.pierce_count

	# Motion type
	match config.motion_type:
		"directional":
			_motion_types[i] = MOTION_DIRECTIONAL
		"aimed":
			_motion_types[i] = MOTION_AIMED
		"homing":
			_motion_types[i] = MOTION_HOMING
		_:
			_motion_types[i] = MOTION_DIRECTIONAL

	# Arc state
	_arc_heights[i] = config.arc_height
	if config.arc_height > 0.0:
		_arc_starts[i] = _positions[i]
		if is_instance_valid(tracking_target):
			_arc_ends[i] = tracking_target.position
		else:
			var range_dist := config.max_range if config.max_range > 0.0 else 200.0
			_arc_ends[i] = _positions[i] + direction * range_dist
		var initial_dist := _positions[i].distance_to(_arc_ends[i])
		_arc_durations[i] = initial_dist / maxf(config.speed, 1.0)
		_arc_times[i] = 0.0

	# Rendering — resolve texture at spawn time
	_visual_scales[i] = config.visual_scale
	_textures[i] = _resolve_texture(config, direction)

	# Impact VFX
	_impact_sprite_frames[i] = config.impact_sprite_frames
	_impact_animations[i] = config.impact_animation if config.impact_animation != "" else ""
	_impact_visual_scales[i] = config.impact_visual_scale

	# Per-slot variant overrides: default to config values (non-variant paths unchanged)
	_impact_aoe_radii[i] = config.impact_aoe_radius
	_damage_multipliers[i] = 1.0
	_echo_sources[i] = echo_source

	queue_redraw()
	return i


func _resolve_texture(config: ProjectileConfig, direction: Vector2) -> Texture2D:
	## Get the correct frame texture for this projectile at spawn time.
	if not config.sprite_frames:
		return null
	var anim_name: String
	if config.use_directional_anims:
		anim_name = _direction_to_anim(direction)
	elif config.animation != "":
		anim_name = config.animation
	else:
		return null
	if not config.sprite_frames.has_animation(anim_name):
		return null
	if config.sprite_frames.get_frame_count(anim_name) == 0:
		return null
	return config.sprite_frames.get_frame_texture(anim_name, 0)


# --- Processing ---

func _process(delta: float) -> void:
	var any_active := false
	for i in _count:
		if not _alive[i]:
			continue
		any_active = true
		if _arc_heights[i] > 0.0:
			_process_arc(i, delta)
		else:
			_process_linear(i, delta)

	if any_active:
		queue_redraw()


func _process_linear(i: int, delta: float) -> void:
	# Homing: recalculate direction toward target each frame
	if _motion_types[i] == MOTION_HOMING:
		var tgt = _targets[i]
		if is_instance_valid(tgt) and tgt.is_alive:
			var dir: Vector2 = (tgt.position - _positions[i]).normalized()
			_velocities[i] = dir * _speeds[i]
			# Update texture for new direction
			var config: ProjectileConfig = _configs[i]
			if config.use_directional_anims:
				_textures[i] = _resolve_texture(config, dir)

	# Move
	var move_vec := _velocities[i] * delta
	_positions[i] += move_vec
	_distances[i] += _speeds[i] * delta

	# Max range expiry
	if _max_ranges[i] > 0.0 and _distances[i] >= _max_ranges[i]:
		_release_slot(i)
		return

	# Screen bounds expiry
	var pos := _positions[i]
	if pos.x < BOUNDS_MIN_X or pos.x > BOUNDS_MAX_X or pos.y < BOUNDS_MIN_Y or pos.y > BOUNDS_MAX_Y:
		_release_slot(i)
		return

	# Hit detection via spatial grid
	_check_hits(i)


func _process_arc(i: int, delta: float) -> void:
	_arc_times[i] += delta

	if _arc_durations[i] <= 0.0:
		_release_slot(i)
		return

	# Track target's live position
	var tgt = _targets[i]
	if is_instance_valid(tgt) and tgt.is_alive:
		_arc_ends[i] = tgt.position

	var t := clampf(_arc_times[i] / _arc_durations[i], 0.0, 1.0)
	var start := _arc_starts[i]
	var end := _arc_ends[i]
	var arc_h := _arc_heights[i]

	# Lerp from start to (live) end, with parabolic Y offset
	var base_pos := start.lerp(end, t)
	var arc_offset := 4.0 * arc_h * t * (1.0 - t)
	_positions[i] = Vector2(base_pos.x, base_pos.y - arc_offset)

	# Rotate sprite to match arc tangent
	var dx := end.x - start.x
	var dy := (end.y - start.y) - 4.0 * arc_h * (1.0 - 2.0 * t)
	_rotations[i] = atan2(dy, dx)

	# Arrived — hit check and expire
	if t >= 1.0:
		var had_hit_before: int = _hit_lists[i].size()
		_check_hits(i)
		# Ground AOE: if no primary target hit, fire impact_aoe_effects at landing position
		# (fountain fireballs that hit empty ground still damage nearby enemies)
		if _alive[i] and _hit_lists[i].size() == had_hit_before:
			_execute_ground_aoe(i)
		_spawn_impact_vfx(i)
		if _alive[i]:
			_release_slot(i)
		return

	# Screen bounds safety
	var pos := _positions[i]
	if pos.x < BOUNDS_MIN_X or pos.x > BOUNDS_MAX_X or pos.y < BOUNDS_MIN_Y or pos.y > BOUNDS_MAX_Y:
		_release_slot(i)
		return

	# Mid-flight hit detection (skip for no_flight_collision projectiles — damage on landing only)
	var config_nfc: ProjectileConfig = _configs[i]
	if not config_nfc or not config_nfc.no_flight_collision:
		_check_hits(i)


func _check_hits(i: int) -> void:
	if not spatial_grid:
		return
	var nearby: Array = spatial_grid.get_nearby(_positions[i], _target_factions[i])
	var hit_radius_sq: float = _hit_radius_sqs[i]
	var pos: Vector2 = _positions[i]
	var hits: Array = _hit_lists[i]

	for tgt in nearby:
		if tgt in hits:
			continue
		if pos.distance_squared_to(tgt.position) <= hit_radius_sq:
			_on_hit(i, tgt)
			if not _alive[i]:
				return  # Was released by pierce check


func _on_hit(i: int, target_entity: Node2D) -> void:
	_hit_lists[i].append(target_entity)
	_execute_effects(i, target_entity)
	_execute_impact_aoe(i, target_entity)
	_spawn_impact_vfx(i)

	# Pierce check
	var pierce: int = _pierce_counts[i]
	if pierce >= 0 and _hit_lists[i].size() > pierce:
		_release_slot(i)


func _execute_effects(i: int, target_entity: Node2D) -> void:
	var config: ProjectileConfig = _configs[i]
	if not config:
		return
	if not is_instance_valid(_sources[i]):
		return
	var source: Node2D = _sources[i]
	var ability: AbilityDefinition = _abilities[i]
	var dmg_mult: float = _damage_multipliers[i]
	var echo_src: EchoSourceConfig = _echo_sources[i]
	for effect in config.on_hit_effects:
		EffectDispatcher.execute_effect(effect, source, target_entity, ability, combat_manager, null, "", dmg_mult, echo_src)


func _execute_impact_aoe(i: int, primary_target: Node2D) -> void:
	## Execute splash/AOE effects on all enemies within the per-slot radius,
	## excluding the primary hit target. Generalizes to any AOE projectile.
	var config: ProjectileConfig = _configs[i]
	var radius: float = _impact_aoe_radii[i]
	if not config or radius <= 0.0 or config.impact_aoe_effects.is_empty():
		return
	if not spatial_grid:
		return
	if not is_instance_valid(_sources[i]):
		return
	var source: Node2D = _sources[i]
	var ability: AbilityDefinition = _abilities[i]
	var pos: Vector2 = _positions[i]
	var radius_sq: float = radius * radius
	var splash_targets: Array = spatial_grid.get_nearby_in_range(pos, _target_factions[i], radius_sq)
	var dmg_mult: float = _damage_multipliers[i]
	var echo_src: EchoSourceConfig = _echo_sources[i]

	# Debug overlay for AOE impact
	if combat_manager and combat_manager.get("debug_draw"):
		var _aoe_ability_id: String = ability.ability_id if ability else ""
		combat_manager.debug_draw.draw_impact_aoe(pos, radius, _aoe_ability_id)

	for target in splash_targets:
		if target == primary_target:
			continue  # Exclude primary — already hit by on_hit_effects
		for effect in config.impact_aoe_effects:
			EffectDispatcher.execute_effect(effect, source, target, ability, combat_manager, null, "", dmg_mult, echo_src)


func _execute_ground_aoe(i: int) -> void:
	## Positional AOE at landing position — no primary target required.
	## Used by fountain projectiles that land on empty ground: fire
	## impact_aoe_effects to all enemies within the per-slot radius of the
	## landing position. Same effect loop as _execute_impact_aoe but without
	## a primary target to exclude. First consumer: Wizard Firestorm.
	var config: ProjectileConfig = _configs[i]
	var radius: float = _impact_aoe_radii[i]
	if not config or radius <= 0.0 or config.impact_aoe_effects.is_empty():
		return
	if not spatial_grid:
		return
	if not is_instance_valid(_sources[i]):
		return
	var source: Node2D = _sources[i]
	var ability: AbilityDefinition = _abilities[i]
	var pos: Vector2 = _positions[i]
	var radius_sq: float = radius * radius
	var splash_targets: Array = spatial_grid.get_nearby_in_range(pos, _target_factions[i], radius_sq)
	var dmg_mult: float = _damage_multipliers[i]
	var echo_src: EchoSourceConfig = _echo_sources[i]

	if combat_manager and combat_manager.get("debug_draw"):
		var _aoe_ability_id: String = ability.ability_id if ability else "ground_aoe"
		combat_manager.debug_draw.draw_impact_aoe(pos, radius, _aoe_ability_id)

	for target in splash_targets:
		if not target.is_alive:
			continue
		for effect in config.impact_aoe_effects:
			EffectDispatcher.execute_effect(effect, source, target, ability, combat_manager, null, "", dmg_mult, echo_src)


func _spawn_impact_vfx(i: int) -> void:
	var impact_sf: SpriteFrames = _impact_sprite_frames[i]
	if not impact_sf:
		return
	if not is_instance_valid(combat_manager):
		return
	var fx := VfxEffect.create(impact_sf, _impact_animations[i], false,
			0, Vector2.ZERO, _impact_visual_scales[i])
	fx.position = _positions[i]
	combat_manager.add_child(fx)


# --- Rendering ---

func _draw() -> void:
	for i in _count:
		if not _alive[i]:
			continue
		var tex: Texture2D = _textures[i]
		if not tex:
			continue
		var pos := _positions[i]
		var rot := _rotations[i]
		var scl := _visual_scales[i]
		var size := tex.get_size()
		var half := size * 0.5

		# For non-rotated, non-scaled projectiles, just draw at position
		if rot == 0.0 and scl == Vector2.ONE:
			draw_texture(tex, pos - half)
		else:
			draw_set_transform(pos, rot, scl)
			draw_texture(tex, -half)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# --- Utility ---

static func _direction_to_anim(dir: Vector2) -> String:
	var angle := dir.angle()
	if angle < 0.0:
		angle += TAU
	var index := int(round(angle / (TAU / 8.0))) % 8
	return DIR_NAMES[index]


func spawn_projectiles(source: Node2D, ability: AbilityDefinition,
		effect: Resource, targets: Array,
		echo_source: EchoSourceConfig = null) -> void:
	## Resolve spawn pattern and create projectiles.
	## Called by EffectDispatcher when it encounters a SpawnProjectilesEffect.
	## echo_source (non-null) = this spawn is an echo replay; propagates to each
	## projectile slot so on-hit dispatch honors the echo's suppressions.
	match effect.spawn_pattern:
		"radial":
			_spawn_radial(source, ability, effect, echo_source)
		"aimed_single":
			# aimed_single + variants (either static on the effect OR overlaid by
			# a talent AbilityModification) → per-variant fan. Empty variants →
			# unchanged single-projectile path.
			var variants: Array = _collect_variants(source, ability, effect)
			if variants.is_empty():
				_spawn_aimed_single(source, ability, effect, targets, echo_source)
			else:
				_spawn_aimed_variants(source, ability, effect, variants, targets, echo_source)
		"at_targets":
			_spawn_at_targets(source, ability, effect, targets, echo_source)
		"fountain":
			_spawn_fountain(source, ability, effect, echo_source)


func _collect_variants(source: Node2D, ability: AbilityDefinition,
		effect: Resource) -> Array:
	## Concatenate static effect variants with any talent-registered overlay for
	## this ability id on the source. Overlay is read live at cast time so prior
	## replacement_ability modifications to the ability do not interfere.
	var out: Array = []
	if not effect.projectile_variants.is_empty():
		for v in effect.projectile_variants:
			if v is ProjectileVariantScript:
				out.append(v)
	if is_instance_valid(source) and source.get("ability_component") != null and ability:
		var overlay: Array = source.ability_component.get_projectile_variant_overlay(ability.ability_id)
		for v in overlay:
			if v is ProjectileVariantScript:
				out.append(v)
	return out


func _spawn_radial(source: Node2D, ability: AbilityDefinition,
		effect: Resource, echo_source: EchoSourceConfig = null) -> void:
	## Spawn N projectiles in evenly-spaced directions from the source.
	for i in effect.count:
		var angle := float(i) * TAU / float(effect.count)
		var dir := Vector2.from_angle(angle)
		spawn(source, ability, effect.projectile, dir, null, effect.spawn_offset, echo_source)


func _spawn_aimed_single(source: Node2D, ability: AbilityDefinition,
		effect: Resource, targets: Array = [],
		echo_source: EchoSourceConfig = null) -> void:
	## Spawn one projectile aimed at the resolved target. Prefers targets[0] when
	## provided by the caller (the ability's resolved pending targets) and only
	## falls back to source.attack_target when the call site passed no targets —
	## load-bearing for talent-driven targeting overrides (Ranger Hunter's Priority)
	## where the ability's resolved target can differ from the movement-system's
	## attack_target (nearest).
	var aim_target: Node2D = null
	if not targets.is_empty() and is_instance_valid(targets[0]) and targets[0].is_alive:
		aim_target = targets[0]
	elif is_instance_valid(source.attack_target) and source.attack_target.is_alive:
		aim_target = source.attack_target
	if not is_instance_valid(aim_target) or not aim_target.is_alive:
		return
	var dir = (aim_target.position - (source.position + effect.spawn_offset)).normalized()
	var needs_target: bool = effect.projectile.motion_type == "homing" or effect.projectile.arc_height > 0.0
	var proj_target: Node2D = aim_target if needs_target else null
	spawn(source, ability, effect.projectile, dir, proj_target, effect.spawn_offset, echo_source)


func _spawn_aimed_variants(source: Node2D, ability: AbilityDefinition,
		effect: Resource, variants: Array, targets: Array = [],
		echo_source: EchoSourceConfig = null) -> void:
	## Spawn one projectile per variant. All variants share the base aim
	## direction resolved from the BASE spawn_offset; each variant can rotate
	## its direction by `angle_offset_degrees` and/or translate its spawn point
	## by `offset_delta`. Per-variant overrides mutate per-slot arrays after
	## spawn so the shared ProjectileConfig is never mutated. Targets[0] overrides
	## source.attack_target when provided (same rule as _spawn_aimed_single).
	var aim_target: Node2D = null
	if not targets.is_empty() and is_instance_valid(targets[0]) and targets[0].is_alive:
		aim_target = targets[0]
	elif is_instance_valid(source.attack_target) and source.attack_target.is_alive:
		aim_target = source.attack_target
	if not is_instance_valid(aim_target) or not aim_target.is_alive:
		return
	var base_origin: Vector2 = source.position + effect.spawn_offset
	var base_dir: Vector2 = (aim_target.position - base_origin).normalized()
	var config: ProjectileConfig = effect.projectile
	var needs_target: bool = config.motion_type == "homing" or config.arc_height > 0.0
	var proj_target: Node2D = aim_target if needs_target else null
	for v in variants:
		var variant_offset: Vector2 = effect.spawn_offset + v.offset_delta
		var variant_dir: Vector2 = base_dir.rotated(deg_to_rad(v.angle_offset_degrees))
		var slot: int = spawn(source, ability, config, variant_dir, proj_target, variant_offset, echo_source)
		if slot < 0:
			continue
		_visual_scales[slot] = config.visual_scale * v.visual_scale_multiplier
		_impact_visual_scales[slot] = config.impact_visual_scale * v.visual_scale_multiplier
		_impact_aoe_radii[slot] = config.impact_aoe_radius * v.splash_radius_multiplier
		_damage_multipliers[slot] = v.damage_multiplier


func _spawn_at_targets(source: Node2D, ability: AbilityDefinition,
		effect: Resource, targets: Array,
		echo_source: EchoSourceConfig = null) -> void:
	## Spawn one projectile per pre-resolved target, each aimed at that target.
	for t in targets:
		if not is_instance_valid(t) or not t.is_alive:
			continue
		var dir = (t.position - (source.position + effect.spawn_offset)).normalized()
		var homing_target: Node2D = t if effect.projectile.motion_type == "homing" else null
		spawn(source, ability, effect.projectile, dir, homing_target, effect.spawn_offset, echo_source)


func _spawn_fountain(source: Node2D, ability: AbilityDefinition,
		effect: Resource, echo_source: EchoSourceConfig = null) -> void:
	## Spawn one arc projectile in a fountain pattern: launches upward from the
	## source, arcs to a random gaussian-distributed landing position within
	## fountain_radius. No flight collision; damage only at landing. The landing
	## distribution is center-weighted (Box-Muller gaussian, most impacts within
	## 20-25px, occasional outliers to fountain_radius).
	## First consumer: Wizard Firestorm.
	var origin: Vector2 = source.position + effect.spawn_offset
	var rng: RandomNumberGenerator = null
	if combat_manager and combat_manager.get("rng"):
		rng = combat_manager.rng

	# Gaussian landing offset (Box-Muller transform, center-weighted)
	var u1: float = rng.randf() if rng else randf()
	var u2: float = rng.randf() if rng else randf()
	# Clamp u1 to avoid log(0)
	u1 = maxf(u1, 1e-6)
	var sigma: float = effect.fountain_radius * 0.33  # ~99% within fountain_radius
	var r: float = sigma * sqrt(-2.0 * log(u1))
	r = minf(r, effect.fountain_radius)  # Hard clamp at max radius
	var theta: float = TAU * u2
	var landing_offset := Vector2(r * cos(theta), r * sin(theta))
	var landing_pos: Vector2 = origin + landing_offset

	# Clamp landing to screen bounds (leave a margin so impact VFX is visible)
	landing_pos.x = clampf(landing_pos.x, 5.0, 315.0)
	landing_pos.y = clampf(landing_pos.y, 10.0, 170.0)

	# Random arc height within configured range
	var arc_min: float = effect.fountain_arc_min
	var arc_max: float = effect.fountain_arc_max
	var arc_h: float = arc_min + (rng.randf() if rng else randf()) * (arc_max - arc_min)

	# Spawn the arc projectile. Direction is just for initial velocity calculation —
	# the arc system overrides positions via lerp. Set direction toward landing.
	var dir: Vector2 = (landing_pos - origin).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.UP  # Fallback for zero-distance landing

	var i := _claim_slot()
	if i < 0:
		return

	var config: ProjectileConfig = effect.projectile
	_alive[i] = 1
	_positions[i] = origin
	_speeds[i] = config.speed
	_max_ranges[i] = 0.0  # Arc projectiles expire on arrival, not range
	_distances[i] = 0.0
	_hit_radius_sqs[i] = config.hit_radius * config.hit_radius
	_factions[i] = source.faction
	_target_factions[i] = 1 if source.faction == 0 else 0
	_velocities[i] = dir * config.speed
	_rotations[i] = dir.angle() if not config.use_directional_anims else 0.0
	_configs[i] = config
	_sources[i] = source
	_abilities[i] = ability
	_targets[i] = null  # No tracking target — landing is pre-calculated
	_hit_lists[i] = []
	_pierce_counts[i] = config.pierce_count
	_motion_types[i] = MOTION_AIMED

	# Arc state: fixed start/end positions (not tracking a target)
	_arc_heights[i] = arc_h
	_arc_starts[i] = origin
	_arc_ends[i] = landing_pos
	var flight_dist: float = origin.distance_to(landing_pos)
	# Minimum flight distance for very close landings — ensures visible arc
	flight_dist = maxf(flight_dist, 30.0)
	_arc_durations[i] = flight_dist / maxf(config.speed, 1.0)
	_arc_times[i] = 0.0

	# Rendering
	_visual_scales[i] = config.visual_scale
	_textures[i] = _resolve_texture(config, dir)

	# Impact VFX
	_impact_sprite_frames[i] = config.impact_sprite_frames
	_impact_animations[i] = config.impact_animation if config.impact_animation != "" else ""
	_impact_visual_scales[i] = config.impact_visual_scale

	# Per-slot variant overrides: default to config values (non-variant paths unchanged)
	_impact_aoe_radii[i] = config.impact_aoe_radius
	_damage_multipliers[i] = 1.0
	_echo_sources[i] = echo_source

	queue_redraw()


# --- Queries ---

func clear_tracking_target(entity: Node2D) -> void:
	## Null out tracking references to a displaced entity so projectiles
	## continue to the last known position instead of following mid-flight.
	for i in _count:
		if _alive[i] and _targets[i] == entity:
			_targets[i] = null


func get_active_count() -> int:
	var count := 0
	for i in _count:
		if _alive[i]:
			count += 1
	return count


func clear_all() -> void:
	## Release all active projectiles (call on run end).
	for i in _count:
		if _alive[i]:
			_release_slot(i)
	_count = 0
	_free_list.clear()
