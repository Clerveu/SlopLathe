extends Node2D

signal run_ended(result: String)

var zone_def: ZoneDefinition

var run_time: float = 0.0
var distance_traveled: float = 0.0
var spawn_timer: float = 0.0
var is_run_over: bool = false

var combat_tracker := CombatTracker.new()
var spatial_grid := SpatialGrid.new()
var projectile_manager: ProjectileManager
var displacement_system: DisplacementSystem
var movement_system: MovementSystem
var vfx_manager: VfxManager
var particle_manager: ParticleManager
var debug_draw: DebugDraw

var rng := RandomNumberGenerator.new()

var entity_scene: PackedScene = preload("res://entities/entity.tscn")
var enemies: Array = []
var heroes: Array = []
var corpses: Array = []
var ground_zones: Array = []

var _enemy_roster: Array = []
var _triggered_waves: Array[int] = []
var _wave_last_fire_time: Dictionary = {}
var _wave_entities: Dictionary = {}

var _summon_expiries: Array = []
var _pending_heal_chains: Array = []
var _pending_echoes: Array = []


func _ready() -> void:
	if not zone_def:
		push_error("combat_manager: zone_def not set before _ready()")
		return

	rng.seed = randi()

	combat_tracker.combat_manager = self
	combat_tracker.connect_signals()

	projectile_manager = ProjectileManager.new()
	projectile_manager.spatial_grid = spatial_grid
	projectile_manager.combat_manager = self
	projectile_manager.z_index = 2
	add_child(projectile_manager)

	displacement_system = DisplacementSystem.new()
	add_child(displacement_system)

	movement_system = MovementSystem.new()
	movement_system.spatial_grid = spatial_grid
	add_child(movement_system)

	movement_system.ground_y_range = zone_def.ground_y_range

	vfx_manager = VfxManager.new()
	add_child(vfx_manager)

	particle_manager = ParticleManager.new()
	add_child(particle_manager)
	vfx_manager.particle_manager = particle_manager

	debug_draw = DebugDraw.new()
	debug_draw.enabled = false
	add_child(debug_draw)

	var feedback_mgr: Node2D = get_node_or_null("CombatFeedbackManager")
	if feedback_mgr:
		feedback_mgr.z_index = 2

	_build_enemy_roster()
	_spawn_initial_entities()
	spawn_timer = zone_def.initial_spawn_delay


func _exit_tree() -> void:
	combat_tracker.disconnect_signals()
	for hero in heroes:
		if is_instance_valid(hero) and hero.is_alive:
			hero.trigger_component.cleanup()
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.is_alive:
			enemy.trigger_component.cleanup()
	for corpse in corpses:
		if is_instance_valid(corpse):
			corpse.trigger_component.cleanup()


func _physics_process(delta: float) -> void:
	if is_run_over:
		return
	_advance_simulation(delta)


func _advance_simulation(delta: float) -> void:
	run_time += delta

	heroes = heroes.filter(func(e): return is_instance_valid(e) and e.is_alive)
	enemies = enemies.filter(func(e): return is_instance_valid(e) and e.is_alive)
	spatial_grid.rebuild(heroes, enemies)

	var has_real_hero := false
	for h in heroes:
		if not h.is_summon:
			has_real_hero = true
			break
	if not has_real_hero:
		_end_run_wipe()
		return

	movement_system.update(delta, heroes, enemies)

	_check_proximity_detonations()

	for hero in heroes:
		hero.status_effect_component.tick(delta)
		hero.ability_component.tick_cooldowns(delta)
		hero.behavior_component.tick(delta, hero)
	for enemy in enemies:
		enemy.status_effect_component.tick(delta)
		enemy.ability_component.tick_cooldowns(delta)
		enemy.behavior_component.tick(delta, enemy)

	_tick_ground_zones(delta)

	_check_wave_spawns()

	_check_summon_expiries()

	_tick_heal_chains()

	_tick_echoes()

	if zone_def.spawn_interval_base > 0.0:
		spawn_timer -= delta
		if spawn_timer <= 0.0:
			_spawn_enemy()
			spawn_timer = maxf(zone_def.spawn_interval_floor,
					zone_def.spawn_interval_base - run_time * zone_def.spawn_interval_decay)


func _spawn_initial_entities() -> void:
	pass


# --- Spawning ---

func spawn_unit(unit_def: UnitDefinition, unit_faction: int, pos: Vector2,
		base_stats: Dictionary = {}, threat: float = 0.0) -> Node2D:
	var entity := entity_scene.instantiate()
	add_child(entity)
	_seed_base_stats(entity, base_stats)
	entity.combat_manager = self
	entity.spatial_grid = spatial_grid
	entity.status_effect_component.combat_manager = self
	entity.trigger_component.combat_manager = self
	entity.persist_as_corpse = true
	entity.setup_from_unit_def(unit_def, unit_faction)
	entity.position = pos
	entity.formation_pos = pos
	entity._last_position = pos
	if threat != 0.0:
		_seed_threat(entity, threat)
	entity.health.died.connect(_on_entity_died)
	heroes.append(entity)
	combat_tracker.register_entity(entity)
	return entity


func spawn_enemy_entity(enemy_def: EnemyDefinition, pos: Vector2) -> Node2D:
	var enemy := entity_scene.instantiate()
	add_child(enemy)
	_seed_base_stats(enemy, enemy_def.base_stats)
	enemy.combat_manager = self
	enemy.spatial_grid = spatial_grid
	enemy.status_effect_component.combat_manager = self
	enemy.trigger_component.combat_manager = self
	enemy.setup_from_enemy_def(enemy_def, enemy.Faction.ENEMY)
	enemy.position = pos
	enemy._last_position = pos
	enemy.health.died.connect(_on_entity_died)
	enemies.append(enemy)
	combat_tracker.register_entity(enemy)
	return enemy


func apply_upgrades(entity: Node2D, tree: TalentTreeDefinition,
		picks: Array[String]) -> void:
	# Phase 1: modifiers (before setup, for stat derivation)
	for talent_id in picks:
		var talent: TalentDefinition = tree.get_talent(talent_id)
		if not talent:
			continue
		for mod in talent.modifiers:
			entity.modifier_component.add_modifier(mod)

	# Phase 2: triggers + statuses (after setup)
	for talent_id in picks:
		var talent: TalentDefinition = tree.get_talent(talent_id)
		if not talent:
			continue
		for listener in talent.trigger_listeners:
			if listener is TriggerListenerDefinition:
				entity.trigger_component.register_listener(
						"talent_" + talent_id, listener, entity)
		for status_data in talent.apply_statuses:
			if status_data is ApplyStatusEffectData:
				entity.status_effect_component.apply_status(
						status_data.status, entity, status_data.stacks, status_data.duration)
		for echo_source in talent.echo_sources:
			if echo_source is EchoSourceConfig:
				entity.modifier_component.add_echo_source(
						echo_source, "talent_" + talent_id)

	# Phase 3: ability modifications (after setup)
	for talent_id in picks:
		var talent: TalentDefinition = tree.get_talent(talent_id)
		if not talent:
			continue
		for mod in talent.ability_modifications:
			if mod is AbilityModification and mod.replacement_ability != null:
				entity.ability_component.replace_ability(
						mod.target_ability_id, mod.replacement_ability)
	for talent_id in picks:
		var talent: TalentDefinition = tree.get_talent(talent_id)
		if not talent:
			continue
		for mod in talent.ability_modifications:
			if mod is AbilityModification:
				entity.ability_component.register_ability_modification(
						mod.target_ability_id, mod.additional_effects,
						mod.on_displacement_arrival, mod.cooldown_flat_reduction)
				if not mod.projectile_variants_overlay.is_empty():
					entity.ability_component.register_projectile_variant_overlay(
							mod.target_ability_id, mod.projectile_variants_overlay)
				if mod.targeting_override != null:
					entity.ability_component.register_targeting_override(
							mod.target_ability_id, mod.targeting_override)
				if mod.projectile_arc_height >= 0.0 or mod.projectile_no_flight_collision:
					entity.ability_component.apply_projectile_patch(
							mod.target_ability_id,
							mod.projectile_arc_height,
							mod.projectile_no_flight_collision)


func _build_enemy_roster() -> void:
	_enemy_roster.clear()
	for entry in zone_def.enemy_roster:
		var enemy_id: String = entry.get("enemy_id", "")
		var weight: float = entry.get("weight", 1.0)
		var enemy_def: EnemyDefinition = UnitRegistry.get_enemy_def(enemy_id)
		if enemy_def:
			_enemy_roster.append({def = enemy_def, weight = weight})
		else:
			push_warning("combat_manager: unknown enemy_id '%s' in zone roster" % enemy_id)


func _spawn_enemy() -> void:
	if is_run_over or _enemy_roster.is_empty():
		return
	var enemy_def: EnemyDefinition = _pick_weighted_enemy()
	var ground_y: float = rng.randf_range(zone_def.ground_y_range.x, zone_def.ground_y_range.y)
	spawn_enemy_entity(enemy_def, Vector2(340.0, ground_y))


func _pick_weighted_enemy() -> EnemyDefinition:
	var total_weight: float = 0.0
	for entry in _enemy_roster:
		total_weight += entry.weight
	var roll: float = rng.randf() * total_weight
	var cumulative: float = 0.0
	for entry in _enemy_roster:
		cumulative += entry.weight
		if roll <= cumulative:
			return entry.def
	return _enemy_roster[-1].def


func _check_wave_spawns() -> void:
	for i in zone_def.waves.size():
		var wave: WaveDefinition = zone_def.waves[i]
		if _triggered_waves.has(i):
			if wave.repeat_interval > 0.0:
				var axis_time: float = _get_wave_axis_time(wave)
				var last_fire: float = float(_wave_last_fire_time.get(i, 0.0))
				if axis_time - last_fire >= wave.repeat_interval:
					if wave.max_alive > 0 and _count_alive_from_wave(i) >= wave.max_alive:
						continue
					_wave_last_fire_time[i] = axis_time
					for entry in wave.entries:
						var enemy_id: String = entry.get("enemy_id", "")
						var count: int = entry.get("count", 1)
						var enemy_def: EnemyDefinition = UnitRegistry.get_enemy_def(enemy_id)
						if not enemy_def:
							continue
						for _j in count:
							_spawn_wave_enemy(enemy_def, entry, wave, i)
			continue

		var triggered: bool = false
		match wave.trigger_type:
			"distance":
				triggered = distance_traveled >= wave.trigger_value
			"time":
				triggered = run_time >= wave.trigger_value
		if not triggered:
			continue

		if wave.max_alive > 0 and _count_alive_from_wave(i) >= wave.max_alive:
			continue

		_triggered_waves.append(i)
		_wave_last_fire_time[i] = _get_wave_axis_time(wave)

		for entry in wave.entries:
			var enemy_id: String = entry.get("enemy_id", "")
			var count: int = entry.get("count", 1)
			var enemy_def: EnemyDefinition = UnitRegistry.get_enemy_def(enemy_id)
			if not enemy_def:
				push_warning("combat_manager: wave references unknown enemy_id '%s'" % enemy_id)
				continue
			for _j in count:
				_spawn_wave_enemy(enemy_def, entry, wave, i)


func _get_wave_axis_time(wave: WaveDefinition) -> float:
	match wave.trigger_type:
		"distance":
			return distance_traveled
		"time":
			return run_time
	return run_time


func _count_alive_from_wave(wave_index: int) -> int:
	if not _wave_entities.has(wave_index):
		return 0
	var count: int = 0
	for e in _wave_entities[wave_index]:
		if is_instance_valid(e) and e.is_alive:
			count += 1
	return count


func _spawn_wave_enemy(enemy_def: EnemyDefinition, entry: Dictionary,
		wave: WaveDefinition, wave_index: int = -1) -> void:
	var enemy := entity_scene.instantiate()
	add_child(enemy)
	_seed_base_stats(enemy, enemy_def.base_stats)
	enemy.combat_manager = self
	enemy.spatial_grid = spatial_grid
	enemy.status_effect_component.combat_manager = self
	enemy.trigger_component.combat_manager = self
	enemy.setup_from_enemy_def(enemy_def, enemy.Faction.ENEMY)

	if entry.has("spawn_position_absolute"):
		enemy.position = entry["spawn_position_absolute"]
	else:
		var ground_y: float = rng.randf_range(zone_def.ground_y_range.x, zone_def.ground_y_range.y)
		var spawn_x: float = 340.0
		var offset: Vector2 = entry.get("spawn_offset", Vector2.ZERO)
		if offset != Vector2.ZERO:
			spawn_x += offset.x
			ground_y += offset.y
			ground_y = clampf(ground_y, zone_def.ground_y_range.x, zone_def.ground_y_range.y)
		enemy.position = Vector2(spawn_x, ground_y)
	enemy._last_position = enemy.position
	enemy.health.died.connect(_on_entity_died)
	enemies.append(enemy)
	combat_tracker.register_entity(enemy)

	if wave.aggro_on_spawn or wave.is_boss_wave:
		enemy.is_aggroed = true

	if wave_index >= 0:
		if not _wave_entities.has(wave_index):
			_wave_entities[wave_index] = []
		_wave_entities[wave_index].append(enemy)

	var intro: ChoreographyDefinition = entry.get("spawn_intro", null)
	if intro == null:
		intro = enemy_def.spawn_intro
	if intro != null:
		enemy._start_spawn_intro(intro)


# --- Proximity Detonation ---

func _check_proximity_detonations() -> void:
	for i in range(enemies.size() - 1, -1, -1):
		var enemy: Node2D = enemies[i]
		if not enemy.is_alive or enemy.enemy_def == null:
			continue
		if enemy.enemy_def.detonate_range <= 0.0:
			continue
		var range_sq: float = enemy.enemy_def.detonate_range * enemy.enemy_def.detonate_range
		for hero in heroes:
			if not hero.is_alive:
				continue
			if enemy.position.distance_squared_to(hero.position) <= range_sq:
				enemy.health.current_hp = 0.0
				enemy.health.is_dead = true
				enemy.health.health_changed.emit(0.0, enemy.health.max_hp)
				enemy.health.died.emit(enemy)
				break


# --- Death Handling ---

func _on_entity_died(entity: Node2D) -> void:
	movement_system.cleanup_entity(entity)
	vfx_manager.cleanup_entity(entity)

	if entity.engagement_target != null:
		EventBus.on_proximity_exit.emit(entity, entity.engagement_target)
		entity.engagement_target = null

	for hero in heroes:
		if hero.engagement_target == entity:
			EventBus.on_proximity_exit.emit(hero, entity)
			hero.engagement_target = null
	for enemy in enemies:
		if enemy.engagement_target == entity:
			EventBus.on_proximity_exit.emit(enemy, entity)
			enemy.engagement_target = null

	entity.trigger_component.cleanup()

	if entity.enemy_def and not entity.enemy_def.on_death_effects.is_empty():
		for effect in entity.enemy_def.on_death_effects:
			EffectDispatcher.execute_effect(effect, entity, entity, null, self, entity)

	var killer: Node2D = entity.last_hit_by if is_instance_valid(entity.last_hit_by) else null
	EventBus.on_death.emit(entity)
	if is_instance_valid(killer):
		EventBus.on_kill.emit(killer, entity)
		var overkill: float = entity.health.last_overkill
		if overkill > 0.0:
			EventBus.on_overkill.emit(killer, entity, overkill)

	if entity.is_summon and is_instance_valid(entity.summoner):
		EventBus.on_summon_death.emit(entity.summoner, entity)
		if entity.summoner.is_alive:
			if entity._summoning_ability_id != "" and entity._summoning_resets_cooldown:
				entity.summoner.ability_component.force_cooldown_by_id(
						entity._summoning_ability_id)
			if entity.summoner._active_summons.has(entity.summon_id):
				var owner_list: Array = entity.summoner._active_summons[entity.summon_id]
				owner_list.erase(entity)
				if owner_list.is_empty():
					entity.summoner._active_summons.erase(entity.summon_id)

	if not entity._active_summons.is_empty():
		var summon_lists: Array = entity._active_summons.values()
		for summon_list in summon_lists:
			var snapshot: Array = summon_list.duplicate()
			for summon in snapshot:
				if is_instance_valid(summon) and summon.is_alive:
					summon.health.current_hp = 0.0
					summon.health.is_dead = true
					summon.health.health_changed.emit(0.0, summon.health.max_hp)
					summon.health.died.emit(summon)
		entity._active_summons.clear()

	if entity.faction == entity.Faction.HERO:
		for ally in heroes:
			if ally != entity and is_instance_valid(ally) and ally.is_alive:
				EventBus.on_ally_death.emit(entity, ally)
	else:
		for ally in enemies:
			if ally != entity and is_instance_valid(ally) and ally.is_alive:
				EventBus.on_ally_death.emit(entity, ally)

	if entity.persist_as_corpse and not entity.is_alive:
		corpses.append(entity)

	for wave_index in _wave_entities:
		_wave_entities[wave_index].erase(entity)


func _end_run_wipe() -> void:
	is_run_over = true
	var wipe_label: Label = get_node_or_null("PartyWipeLabel")
	if wipe_label:
		wipe_label.visible = true
	run_ended.emit("wiped")


func _end_run_clear() -> void:
	is_run_over = true
	run_ended.emit("cleared")


func _seed_base_stats(entity: Node2D, stats: Dictionary) -> void:
	for stat_name in stats:
		var mod := ModifierDefinition.new()
		mod.target_tag = stat_name
		mod.operation = "add"
		mod.value = stats[stat_name]
		mod.source_name = "base_stats"
		entity.modifier_component.add_modifier(mod)


func _seed_threat(entity: Node2D, value: float) -> void:
	if value == 0.0:
		return
	var mod := ModifierDefinition.new()
	mod.target_tag = "Threat"
	mod.operation = "add"
	mod.value = value
	mod.source_name = "innate_threat"
	entity.modifier_component.add_modifier(mod)


# --- Summons ---

func spawn_summon(summoner: Node2D, ability: AbilityDefinition,
		effect: SummonEffect) -> void:
	var spawn_count: int = maxi(1, effect.count)
	for i in spawn_count:
		_spawn_one_summon(summoner, ability, effect)


func _spawn_one_summon(summoner: Node2D, ability: AbilityDefinition,
		effect: SummonEffect) -> void:
	var summon := entity_scene.instantiate()
	add_child(summon)

	for summon_stat in effect.stat_map:
		var mapping: Dictionary = effect.stat_map[summon_stat]
		var from_attr: String = mapping["from"]
		var coeff: float = mapping["coeff"]
		var value: float = summoner.modifier_component.sum_modifiers(from_attr, "add") * coeff
		var mod := ModifierDefinition.new()
		mod.target_tag = summon_stat
		mod.operation = "add"
		mod.value = value
		mod.source_name = "summon_inheritance"
		summon.modifier_component.add_modifier(mod)

	summon.combat_manager = self
	summon.spatial_grid = spatial_grid
	summon.status_effect_component.combat_manager = self
	summon.trigger_component.combat_manager = self
	summon.setup_from_unit_def(effect.summon_class, summoner.faction, 1)

	summon.summoner = summoner
	summon.is_summon = true
	summon.summon_id = effect.summon_id
	summon._summoning_ability_id = ability.ability_id
	summon._summoning_resets_cooldown = effect.reset_cooldown_on_death
	summon.is_untargetable = effect.is_untargetable

	if effect.is_untargetable and not enemies.is_empty():
		var visible_enemies: Array = []
		for e in enemies:
			if e.position.x >= 0.0 and e.position.x <= 320.0:
				visible_enemies.append(e)
		if visible_enemies.is_empty():
			visible_enemies = enemies
		var rand_enemy: Node2D = visible_enemies[rng.randi() % visible_enemies.size()]
		var y_offset: float = rng.randf_range(-50.0, 50.0)
		summon.position = Vector2(
			clampf(rand_enemy.position.x, 0.0, 290.0),
			clampf(rand_enemy.position.y + y_offset,
					zone_def.ground_y_range.x, zone_def.ground_y_range.y))
	else:
		var spawn_offset := Vector2(20, 0) if not summoner.sprite.flip_h else Vector2(-20, 0)
		summon.position = summoner.position + spawn_offset

	if effect.spawn_spread > 0.0:
		var angle: float = rng.randf() * TAU
		var radius: float = rng.randf() * effect.spawn_spread
		summon.position += Vector2(cos(angle) * radius, sin(angle) * radius)

	summon._last_position = summon.position

	if effect.threat_modifier != 0.0:
		_seed_threat(summon, effect.threat_modifier)

	summon.is_channeling = true
	if summon.sprite.sprite_frames and summon.sprite.sprite_frames.has_animation("summon"):
		summon.sprite.play("summon")
	else:
		summon.sprite.play("idle")
		summon.is_channeling = false

	if not summoner._active_summons.has(effect.summon_id):
		summoner._active_summons[effect.summon_id] = []
	summoner._active_summons[effect.summon_id].append(summon)
	summon.health.died.connect(_on_entity_died)
	heroes.append(summon)
	combat_tracker.register_entity(summon)

	if effect.duration > 0.0:
		_summon_expiries.append({summon = summon, expiry_time = run_time + effect.duration})

	EventBus.on_summon.emit(summoner, summon)


func _check_summon_expiries() -> void:
	var i := _summon_expiries.size() - 1
	while i >= 0:
		var entry: Dictionary = _summon_expiries[i]
		if not is_instance_valid(entry.summon) or not entry.summon.is_alive:
			_summon_expiries.remove_at(i)
		elif run_time >= entry.expiry_time:
			_expire_summon(entry.summon)
			_summon_expiries.remove_at(i)
		i -= 1


func _expire_summon(summon: Node2D) -> void:
	if not is_instance_valid(summon) or not summon.is_alive:
		return
	summon.health.current_hp = 0.0
	summon.health.is_dead = true
	summon.health.health_changed.emit(0.0, summon.health.max_hp)
	summon.health.died.emit(summon)


# --- Heal Chains ---

func _tick_heal_chains() -> void:
	var i: int = _pending_heal_chains.size() - 1
	while i >= 0:
		var entry: Dictionary = _pending_heal_chains[i]
		var source: Node2D = entry.source
		if not is_instance_valid(source) or not source.is_alive:
			_pending_heal_chains.remove_at(i)
			i -= 1
			continue
		if run_time < entry.next_fire_time:
			i -= 1
			continue
		var hop_index: int = entry.hop_index
		var resolved: Array = entry.resolved
		if hop_index >= resolved.size():
			_pending_heal_chains.remove_at(i)
			i -= 1
			continue
		var target: Node2D = resolved[hop_index]
		if not is_instance_valid(target) or not target.is_alive \
				or target.health.current_hp >= target.health.max_hp:
			_pending_heal_chains.remove_at(i)
			i -= 1
			continue
		var hop: Resource = entry.hops[hop_index]
		EffectDispatcher.execute_effect(
				hop, source, target, entry.ability, self, null, entry.attribution_tag)
		if vfx_manager and not entry.target_vfx_layers.is_empty():
			vfx_manager.spawn_target_vfx(target, entry.target_vfx_layers)
		var next_hop_index: int = hop_index + 1
		if next_hop_index < resolved.size() and entry.get("chain_preset") and particle_manager:
			var next_target: Node2D = resolved[next_hop_index]
			if is_instance_valid(next_target):
				particle_manager.claim_line(
						entry.chain_preset,
						target.position,
						next_target.position,
						self,
						entry.chain_delay,
						1)
		entry.hop_index = next_hop_index
		entry.next_fire_time = run_time + entry.chain_delay
		if entry.hop_index >= resolved.size():
			_pending_heal_chains.remove_at(i)
		i -= 1


# --- Echo Replays ---

func schedule_echo(source: Node2D, ability: AbilityDefinition,
		config: EchoSourceConfig, effective_delay: float,
		captured_targets: Array = []) -> void:
	if not is_instance_valid(source) or not source.is_alive or ability == null or config == null:
		return
	var entry: Dictionary = {
		source = source,
		ability = ability,
		fire_time = run_time + effective_delay,
		config = config,
		captured_targets = captured_targets.duplicate() if not captured_targets.is_empty() else [],
		recursion_remaining = config.recursion_cap - 1,
	}
	_pending_echoes.append(entry)


func _tick_echoes() -> void:
	var i: int = _pending_echoes.size() - 1
	while i >= 0:
		var entry: Dictionary = _pending_echoes[i]
		var source: Node2D = entry.source
		if not is_instance_valid(source) or not source.is_alive:
			_pending_echoes.remove_at(i)
			i -= 1
			continue
		if run_time < entry.fire_time:
			i -= 1
			continue
		var ability: AbilityDefinition = entry.ability
		var config: EchoSourceConfig = entry.config

		var fresh_targets: Array = []
		if config.capture_targets and not entry.captured_targets.is_empty():
			for t in entry.captured_targets:
				if is_instance_valid(t) and t.is_alive:
					fresh_targets.append(t)
		else:
			if ability.hit_targeting:
				fresh_targets = source.behavior_component.resolve_targets_with_rule(
						ability.hit_targeting, source)
			elif ability.targeting:
				fresh_targets = source.behavior_component.resolve_targets_with_rule(
						ability.targeting, source)

		var has_targetless: bool = false
		for effect in ability.effects:
			if effect is SpawnProjectilesEffect or effect is SummonEffect:
				has_targetless = true
				break
		if fresh_targets.is_empty() and not has_targetless:
			_pending_echoes.remove_at(i)
			i -= 1
			continue

		EffectDispatcher.execute_effects(ability.effects, source, fresh_targets,
				ability, self, null, config.source_id, config.power_multiplier, config)

		var mod_effects: Array = source.ability_component.get_ability_modifications(ability.ability_id)
		if not mod_effects.is_empty():
			EffectDispatcher.execute_effects(mod_effects, source, fresh_targets,
					ability, self, null, config.source_id + "_mod:" + ability.ability_id,
					config.power_multiplier, config)

		if vfx_manager and not ability.target_vfx_layers.is_empty():
			for target in fresh_targets:
				vfx_manager.spawn_target_vfx(target, ability.target_vfx_layers)

		EventBus.on_echo.emit(source, ability, config.source_id,
				config.power_multiplier, fresh_targets)

		_pending_echoes.remove_at(i)
		i -= 1


func _find_heal_chain_target(from_pos: Vector2, faction: int, range_sq: float,
		hit_set: Dictionary) -> Node2D:
	if not spatial_grid:
		return null
	var candidates: Array = spatial_grid.get_nearby_in_range(from_pos, faction, range_sq)
	var best: Node2D = null
	var best_dist_sq: float = INF
	for e in candidates:
		if hit_set.has(e):
			continue
		if not is_instance_valid(e) or not e.is_alive:
			continue
		if e.health.current_hp >= e.health.max_hp:
			continue
		var d_sq: float = from_pos.distance_squared_to(e.position)
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best = e
	return best


# --- Ground Zones ---

func spawn_ground_zone(effect: GroundZoneEffect, source: Node2D, pos: Vector2) -> void:
	var zone := GroundZone.new()
	zone.setup(effect, source, pos, self)
	add_child(zone)
	ground_zones.append(zone)


func _tick_ground_zones(delta: float) -> void:
	var i := ground_zones.size() - 1
	while i >= 0:
		var zone: GroundZone = ground_zones[i]
		if not is_instance_valid(zone) or zone.is_expired:
			if is_instance_valid(zone):
				zone.release_vfx()
				zone.queue_free()
			ground_zones.remove_at(i)
		else:
			zone.tick(delta)
		i -= 1


# --- Resurrection ---

func revive_entity(corpse: Node2D, hp_percent: float, _source: Node2D) -> void:
	if not is_instance_valid(corpse) or corpse.is_alive:
		return

	corpses.erase(corpse)
	if not heroes.has(corpse):
		heroes.append(corpse)

	corpse.is_alive = true
	corpse.is_corpse = false
	corpse.is_attacking = false
	corpse.in_combat = false
	corpse.attack_target = null
	corpse.engagement_target = null
	corpse._last_position = corpse.position
	corpse.desired_position = Vector2.ZERO

	corpse.health.is_dead = false
	corpse.health.current_hp = corpse.health.max_hp * hp_percent
	corpse.health.health_changed.emit(corpse.health.current_hp, corpse.health.max_hp)

	corpse.hp_bar.visible = true
	corpse.sprite.play("idle")

	EventBus.on_revive.emit(_source, corpse)


func get_nearest_corpse(from_pos: Vector2, faction) -> Node2D:
	var best: Node2D = null
	var best_dist_sq := INF
	for corpse in corpses:
		if not is_instance_valid(corpse):
			continue
		if corpse.faction != faction:
			continue
		var d_sq: float = from_pos.distance_squared_to(corpse.position)
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best = corpse
	return best
