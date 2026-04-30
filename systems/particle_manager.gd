class_name ParticleManager
extends Node2D
## Pooled CPUParticles2D emitter manager. Sibling of VfxManager / ProjectileManager
## under combat_manager. Presets are applied to dormant pool slots on claim —
## one-shot emitters auto-release via the CPUParticles2D.finished signal, looping
## emitters are released manually (status expiry) or via cleanup_entity on death.
##
## Pool size is a tuning dial — bump POOL_SIZE if _peak_active approaches the cap.
## A dormant CPUParticles2D with emitting=false is effectively free (no _process
## cost, a few KB of state).

const POOL_SIZE := 128

var _emitters: Array[CPUParticles2D] = []
var _alive: PackedByteArray
var _free_list: Array[int] = []
var _follow_targets: Array = []        ## Per-slot Node2D or null (for cleanup_entity)
var _peak_active: int = 0              ## Debug high-water mark — never decrements
var _warned_this_frame: bool = false   ## Throttle push_warning on pool exhaustion


func _ready() -> void:
	_init_pool()


func _process(_delta: float) -> void:
	_warned_this_frame = false


func _init_pool() -> void:
	_alive.resize(POOL_SIZE)
	_follow_targets.resize(POOL_SIZE)
	_emitters.resize(POOL_SIZE)
	for i in POOL_SIZE:
		var emitter := CPUParticles2D.new()
		emitter.emitting = false
		emitter.local_coords = false
		emitter.one_shot = false
		add_child(emitter)
		emitter.finished.connect(_on_emitter_finished.bind(i))
		_emitters[i] = emitter
		_alive[i] = 0
		_follow_targets[i] = null
	# Reverse push so pop_back yields slot 0 first (locality — low slots fill first)
	for i in range(POOL_SIZE - 1, -1, -1):
		_free_list.append(i)


# --- Public API ---

func claim(preset: ParticleFxPreset, world_pos: Vector2, parent_node: Node,
		follow_entity: bool, z_index: int = 0) -> int:
	## Claim a pool slot, apply the preset, reparent the emitter, start emission.
	## Returns the slot index, or -1 if headless/exhausted. Callers may ignore the
	## return value for one-shot presets (finished signal auto-releases the slot).
	var cm: Node2D = get_parent() as Node2D
	if cm and cm.get("is_headless") and cm.is_headless:
		return -1
	if not is_instance_valid(parent_node):
		return -1
	if _free_list.is_empty():
		if not _warned_this_frame:
			push_warning("ParticleManager: pool exhausted (%d slots)" % POOL_SIZE)
			_warned_this_frame = true
		return -1

	var slot: int = _free_list.pop_back()
	_alive[slot] = 1
	var emitter: CPUParticles2D = _emitters[slot]

	# Reparent. Use reparent() to preserve global position while swapping parents.
	# But we want to *set* the position after reparent, so plain remove+add is simpler.
	if emitter.get_parent() != parent_node:
		emitter.get_parent().remove_child(emitter)
		parent_node.add_child(emitter)

	if follow_entity:
		emitter.position = world_pos  # interpreted as local offset under parent
	else:
		emitter.position = world_pos.round()

	_apply_preset(emitter, preset)
	emitter.z_index = z_index
	_follow_targets[slot] = parent_node if follow_entity else null
	emitter.emitting = true

	var active: int = POOL_SIZE - _free_list.size()
	if active > _peak_active:
		_peak_active = active

	return slot


func claim_line(preset: ParticleFxPreset, origin: Vector2, target_pos: Vector2,
		parent_node: Node, travel_time: float, z_index: int = 0) -> int:
	## Line-oriented claim: claims a slot with the preset, then overrides the
	## emitter's direction, initial velocity, and lifetime so the burst travels
	## from origin to target_pos in travel_time seconds. Used for directional
	## tether/chain/tether VFX where the preset defines look-and-feel and the
	## trajectory is computed per-spawn.
	##
	## The preset should be a one-shot explosive burst (explosiveness=1.0) so the
	## full pack travels together along the line. Spread is preserved — a small
	## spread (~10°) gives a tight bolt, wider spreads give a cone.
	if travel_time <= 0.0:
		return -1
	var delta: Vector2 = target_pos - origin
	var distance: float = delta.length()
	if distance < 0.01:
		return -1
	var slot: int = claim(preset, origin, parent_node, false, z_index)
	if slot < 0:
		return -1
	var emitter: CPUParticles2D = _emitters[slot]
	var speed: float = distance / travel_time
	var dir: Vector2 = delta / distance
	emitter.direction = dir
	emitter.initial_velocity_min = speed
	emitter.initial_velocity_max = speed
	emitter.lifetime = travel_time
	emitter.restart()
	return slot


func release(slot: int) -> void:
	## Stop emission, reparent back to self, return slot to the free list.
	## Safe to call on an already-released slot (no-op).
	if slot < 0 or slot >= POOL_SIZE:
		return
	if _alive[slot] == 0:
		return
	_alive[slot] = 0
	var emitter: CPUParticles2D = _emitters[slot]
	if is_instance_valid(emitter):
		emitter.emitting = false
		var parent := emitter.get_parent()
		if parent != self:
			if parent:
				parent.remove_child(emitter)
			add_child(emitter)
		emitter.position = Vector2.ZERO
	_follow_targets[slot] = null
	_free_list.append(slot)


func cleanup_entity(entity: Node2D) -> void:
	## Release every slot whose follow target is this entity. Called from
	## VfxManager.cleanup_entity() on death. Mirrors VfxManager behavior.
	for i in POOL_SIZE:
		if _alive[i] == 1 and _follow_targets[i] == entity:
			release(i)


func get_active_count() -> int:
	return POOL_SIZE - _free_list.size()


func get_peak_active() -> int:
	return _peak_active


# --- Internals ---

func _on_emitter_finished(slot: int) -> void:
	## CPUParticles2D.finished fires when a one_shot emission completes.
	## For looping emitters (emitting=true with one_shot=false) this never fires,
	## so it's the correct auto-release hook for one-shot presets.
	release(slot)


func _apply_preset(emitter: CPUParticles2D, preset: ParticleFxPreset) -> void:
	emitter.amount = preset.amount
	emitter.lifetime = preset.lifetime
	emitter.one_shot = preset.one_shot
	emitter.explosiveness = preset.explosiveness
	emitter.emission_shape = preset.emission_shape
	emitter.emission_rect_extents = Vector2(preset.emission_box_extents.x,
			preset.emission_box_extents.y)
	emitter.emission_sphere_radius = preset.emission_sphere_radius
	emitter.direction = Vector2(preset.direction.x, preset.direction.y)
	emitter.spread = preset.spread
	emitter.initial_velocity_min = preset.initial_velocity_min
	emitter.initial_velocity_max = preset.initial_velocity_max
	emitter.gravity = Vector2(preset.gravity.x, preset.gravity.y)
	emitter.angular_velocity_min = preset.angular_velocity_min
	emitter.angular_velocity_max = preset.angular_velocity_max
	emitter.scale_amount_min = preset.scale_amount_min
	emitter.scale_amount_max = preset.scale_amount_max
	emitter.color_ramp = preset.color_ramp
	emitter.texture = preset.texture
	emitter.fixed_fps = preset.fixed_fps
	emitter.fract_delta = preset.fract_delta
	emitter.local_coords = false
	emitter.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	emitter.restart()
