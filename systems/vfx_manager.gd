class_name VfxManager
extends Node
## Manages visual effect lifecycle: ability VFX (one-shot) and status VFX (looping).
## Listens to EventBus signals directly. Child of combat_manager.
##
## vfx_layers / target_vfx_layers / on_stack_vfx_layers arrays accept either
## VfxLayerConfig (sprite-based) or ParticleVfxLayerConfig (pooled CPUParticles2D)
## — every iteration site branches on type. Sprite layers spawn/free VfxEffect
## nodes; particle layers claim/release ParticleManager pool slots.

var particle_manager: ParticleManager  ## Injected by combat_manager after creation

var _status_vfx: Dictionary = {}  ## entity → {status_id → Array[VfxEffect]}
var _status_particle_slots: Dictionary = {}  ## entity → {status_id → Array[int]}


func _ready() -> void:
	EventBus.on_ability_used.connect(_on_ability_used)
	EventBus.on_status_applied.connect(_on_status_applied)
	EventBus.on_status_expired.connect(_on_status_expired)
	EventBus.on_cleanse.connect(_on_cleanse)


func _is_headless() -> bool:
	var cm: Node2D = get_parent()
	return cm and cm.get("is_headless") and cm.is_headless


func cleanup_entity(entity: Node2D) -> void:
	_status_vfx.erase(entity)  # VFX nodes auto-free as entity children
	_status_particle_slots.erase(entity)
	if particle_manager:
		particle_manager.cleanup_entity(entity)


func spawn_target_vfx(target: Node2D, layers: Array) -> void:
	## One-shot target VFX for effect consumers outside the ability hit-frame path
	## (e.g. deferred heal chain hops). Mirrors entity._spawn_target_vfx but takes
	## the target + layers directly so any system can spawn consistent target FX.
	if layers.is_empty() or not is_instance_valid(target):
		return
	if _is_headless():
		return
	for layer in layers:
		if layer is ParticleVfxLayerConfig:
			_dispatch_particle_ability_layer(layer, target)
		else:
			var offset := Vector2(layer.offset)
			if target.sprite.flip_h:
				offset.x = -offset.x
			var fx = VfxEffect.create(layer.sprite_frames, layer.animation, false,
					layer.z_index, offset, layer.scale)
			target.add_child(fx)


func _on_ability_used(entity: Node2D, ability: AbilityDefinition) -> void:
	if not is_instance_valid(entity) or ability.vfx_layers.is_empty():
		return
	if _is_headless():
		return
	for layer in ability.vfx_layers:
		if layer is ParticleVfxLayerConfig:
			_dispatch_particle_ability_layer(layer, entity)
		else:
			var offset = Vector2(layer.offset)
			if entity.sprite.flip_h:
				offset.x = -offset.x
			var fx = VfxEffect.create(layer.sprite_frames, layer.animation, false,
					layer.z_index, offset, layer.scale)
			entity.add_child(fx)


func _on_status_applied(_source: Node2D, target: Node2D, status_id: String, _stacks: int) -> void:
	if not is_instance_valid(target):
		return
	if _is_headless():
		return
	var status_def = target.status_effect_component.get_definition(status_id)
	if not status_def:
		return
	# Looping VFX: spawn once on first application, skip on stack refresh
	if not status_def.vfx_layers.is_empty():
		var already_spawned: bool = (_status_vfx.has(target) and _status_vfx[target].has(status_id)) \
				or (_status_particle_slots.has(target) and _status_particle_slots[target].has(status_id))
		if not already_spawned:
			for layer in status_def.vfx_layers:
				if layer is ParticleVfxLayerConfig:
					_dispatch_particle_status_layer(layer, target, status_id)
				else:
					var offset = Vector2(layer.offset)
					if target.sprite.flip_h:
						offset.x = -offset.x
					_add_status_vfx(target, status_id, layer, offset)
	# One-shot stack VFX: spawn on every application/stack (no dedup)
	for layer in status_def.on_stack_vfx_layers:
		if layer is ParticleVfxLayerConfig:
			_dispatch_particle_ability_layer(layer, target)
		else:
			var offset = Vector2(layer.offset)
			if target.sprite.flip_h:
				offset.x = -offset.x
			var fx = VfxEffect.create(layer.sprite_frames, layer.animation, false,
					layer.z_index, offset, layer.scale)
			target.add_child(fx)


func _on_status_expired(entity: Node2D, status_id: String) -> void:
	if not is_instance_valid(entity):
		return
	_remove_status_vfx(entity, status_id)
	_remove_status_particles(entity, status_id)


func _on_cleanse(_source: Node2D, target: Node2D, status_id: String, _applier,
		_stacks: int, _definition) -> void:
	if not is_instance_valid(target):
		return
	_remove_status_vfx(target, status_id)
	_remove_status_particles(target, status_id)


func _add_status_vfx(entity: Node2D, status_id: String, layer: Resource,
		offset: Vector2) -> void:
	var fx: VfxEffect
	if layer.start_animation != "" or layer.end_animation != "":
		fx = VfxEffect.create_phased(layer.sprite_frames, layer.animation,
				layer.start_animation, layer.end_animation,
				layer.z_index, offset, layer.scale)
	else:
		fx = VfxEffect.create(layer.sprite_frames, layer.animation, true,
				layer.z_index, offset, layer.scale)
	entity.add_child(fx)
	if not _status_vfx.has(entity):
		_status_vfx[entity] = {}
	if not _status_vfx[entity].has(status_id):
		_status_vfx[entity][status_id] = []
	_status_vfx[entity][status_id].append(fx)


func _remove_status_vfx(entity: Node2D, status_id: String) -> void:
	if not _status_vfx.has(entity):
		return
	if not _status_vfx[entity].has(status_id):
		return
	var fx_list: Array = _status_vfx[entity][status_id]
	for fx in fx_list:
		if is_instance_valid(fx):
			fx.stop_effect()
	_status_vfx[entity].erase(status_id)


# --- Particle dispatch ---

func _dispatch_particle_ability_layer(layer: ParticleVfxLayerConfig, entity: Node2D) -> void:
	## One-shot particle layer, no lifetime tracking — the finished signal on the
	## pooled emitter auto-releases the slot when the preset's one_shot burst ends.
	if not particle_manager:
		return
	if not is_instance_valid(entity):
		return
	var cm: Node2D = get_parent() as Node2D
	var offset := Vector2(layer.offset)
	if entity.sprite.flip_h:
		offset.x = -offset.x
	offset = offset.round()
	var parent: Node
	var pos: Vector2
	if layer.follow_entity:
		parent = entity
		pos = offset
	else:
		parent = cm
		pos = (entity.position + offset).round()
	particle_manager.claim(layer.preset, pos, parent, layer.follow_entity, layer.z_index)


func _dispatch_particle_status_layer(layer: ParticleVfxLayerConfig, entity: Node2D,
		status_id: String) -> void:
	## Looping particle layer tied to a status. Slot index recorded so it can be
	## released on status expiry or cleanse.
	if not particle_manager:
		return
	if not is_instance_valid(entity):
		return
	var cm: Node2D = get_parent() as Node2D
	var offset := Vector2(layer.offset)
	if entity.sprite.flip_h:
		offset.x = -offset.x
	offset = offset.round()
	var parent: Node
	var pos: Vector2
	if layer.follow_entity:
		parent = entity
		pos = offset
	else:
		parent = cm
		pos = (entity.position + offset).round()
	var slot: int = particle_manager.claim(layer.preset, pos, parent, layer.follow_entity, layer.z_index)
	if slot < 0:
		return
	if not _status_particle_slots.has(entity):
		_status_particle_slots[entity] = {}
	if not _status_particle_slots[entity].has(status_id):
		_status_particle_slots[entity][status_id] = []
	_status_particle_slots[entity][status_id].append(slot)


func _remove_status_particles(entity: Node2D, status_id: String) -> void:
	if not _status_particle_slots.has(entity):
		return
	if not _status_particle_slots[entity].has(status_id):
		return
	var slots: Array = _status_particle_slots[entity][status_id]
	for slot in slots:
		if particle_manager:
			particle_manager.release(slot)
	_status_particle_slots[entity].erase(status_id)
