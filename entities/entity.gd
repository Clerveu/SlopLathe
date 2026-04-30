extends Node2D
## Base entity script. Handles animation state and hit-frame damage.
## Heroes and enemies both use this. Combat decisions delegated to BehaviorComponent.

enum Faction { HERO, ENEMY }
enum CombatRole { MELEE, RANGED }
enum AnimState { IDLE, WALK, ATTACK, DMG, DIE }

@export var faction: Faction = Faction.HERO
@export var combat_role: CombatRole = CombatRole.MELEE
@export var move_speed: float = 25.0  ## World-space pixels/sec
@export var engage_distance: float = 20.0  ## Distance at which this entity engages

var entity_id: String = ""
var unit_def: UnitDefinition = null
var enemy_def: EnemyDefinition = null  ## Populated for enemies in setup_from_enemy_def; null for heroes. Carries xp_value consumed by CombatTracker._on_kill's XP distribution sweep.
var attack_target: Node2D = null
var engagement_target: Node2D = null  ## Source of truth for who I'm fighting — set by MovementSystem
var desired_position: Vector2 = Vector2.ZERO  ## Where MovementSystem wants me
var anim_state: AnimState = AnimState.IDLE
var is_alive: bool = true
var is_corpse: bool = false  ## True after die animation finishes when persist_as_corpse is set
var persist_as_corpse: bool = false  ## Set at spawn for non-summon heroes (corpse instead of free)
var is_attacking: bool = false
var is_channeling: bool = false  ## True during channeled abilities (suppresses behavior + movement)
var in_combat: bool = false  ## True while entity has a valid target — survives between swings
var formation_pos: Vector2 = Vector2.ZERO
var summoner: Node2D = null  ## Summoner entity (null for non-summons)
var is_summon: bool = false  ## True for summoned entities (Spirit Guardian, etc.)
var summon_id: String = ""  ## Identifies the summon type (matches SummonEffect.summon_id)
var is_untargetable: bool = false  ## True = excluded from spatial grid (can't be targeted by anything)
var _active_summons: Dictionary = {}  ## summon_id → Array[Node2D] (summoners track living summons; array because count>1 abilities exist)
var _summoning_ability_id: String = ""  ## Ability that created this summon (for cooldown reset on death)
var _summoning_resets_cooldown: bool = true  ## True → this summon's death resets summoner's ability cooldown (set at spawn from SummonEffect.reset_cooldown_on_death)
var combat_manager: Node2D = null  ## Set by combat_manager at spawn time (for run_time access)
var spatial_grid: SpatialGrid = null  ## Set by combat_manager at spawn time
var _slot_index: int = -1  ## Cached engagement slot index for O(1) lookup (-1 = no slot)
var advance_for_cast_range: float = 0.0  ## Set by BehaviorComponent when a short-range ability needs advance
var advance_cast_target: Node2D = null  ## Target to advance toward for cast_range ability
var aggro_range: float = 0.0  ## 0.0 = always aware (backward-compatible)
var is_aggroed: bool = false  ## Permanently true once an enemy enters aggro_range
var retarget_timer: float = 0.0  ## Counts down; re-evaluate target at 0
var retarget_interval: float = 1.5  ## Seconds between target re-evaluations
var preferred_range: float = 0.0  ## Ranged positioning distance (0 = use default formation math)
var talent_picks: Array[String] = []  ## Talent IDs selected for this entity (set at spawn, empty for enemies)
var priority_role: String = ""  ## Classification for multi-tier priority targeting ("healer", "caster", ""). Heroes default to empty; enemies populate from EnemyDefinition.
var is_elite: bool = false  ## Elite classification (propagated from EnemyDefinition). Used by priority-tier targeting.
var is_boss: bool = false  ## Boss classification (propagated from EnemyDefinition). Used by priority-tier targeting.
var _last_position: Vector2 = Vector2.ZERO  ## Previous frame position for facing direction
var _velocity: Vector2 = Vector2.ZERO  ## Live velocity for inertia-based motion smoothing. Updated every frame by MovementSystem; target velocity is direction × effective_speed when moving, zero when frozen (is_attacking / is_channeling / _ability_anim_active) or at destination. Decays / ramps toward target via MovementSystem.MOVE_ACCEL so entities glide to/from rest instead of step-functioning velocity.
var is_invulnerable: bool = false  ## True during abilities with grants_invulnerability (e.g. Blink)
var last_hit_by: Node2D = null
var last_hit_time: float = -1e18  ## combat run_time (seconds) of last damage taken
var _last_hit_time_by_tag: Dictionary = {}  ## ability tag → run_time seconds (for tag-filtered conditions)
var _echo_cast_counters: Dictionary = {}  ## EchoSourceConfig.source_id → eligible cast count (for cadence_every_n gating). First consumer: Ranger Echo Shot.
var _overflow_damage_accumulator: float = 0.0  ## Tracks total damage dealt during ability execution (for overflow heal)
var _hit_frame_fired: bool = false
var _vfx_frame_fired: bool = false
var _hit_frames_fired: Dictionary = {}  ## Tracks which multi-hit frames have fired (frame → true)
var _hit_frame: int = 3  ## Which frame deals damage (0-indexed, entity default)
var _current_attack_anim: String = "attack"  ## Resolved per-ability from anim_override
var _current_hit_frame: int = 3  ## Resolved per-ability from hit_frame_override
var _ability_anim_active: bool = false  ## True while an ability (not auto-attack) animation is playing

## Pending ability to execute on next hit frame (null = auto-attack)
var _pending_ability: AbilityDefinition = null
var _pending_targets: Array = []
var _channel_status_id: String = ""  ## Status ID tied to current channel (for expiry detection)
var _anim_on_complete: String = ""  ## Follow-up animation after primary anim finishes (two-phase abilities)

## Choreography state (generic multi-phase ability sequences)
var _choreography: ChoreographyDefinition = null
var _choreography_ability: AbilityDefinition = null
var _choreography_phase_index: int = -1
var _choreography_timer: float = 0.0
var _choreography_targets: Array = []  ## Targets resolved for current phase
var _channel_scroll_anchor: bool = false  ## When true, MovementSystem drifts entity with scroll during channel; DisplacementSystem tweens track scroll in their start/end anchors. Set from ChoreographyDefinition.scroll_anchor by _start_spawn_intro / _start_choreography; cleared by _end_choreography.

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var shadow_sprite: AnimatedSprite2D = $ShadowSprite
@onready var health: HealthComponent = $HealthComponent
@onready var hp_bar: Node2D = $HPBar
@onready var modifier_component: ModifierComponent = $ModifierComponent
@onready var ability_component: AbilityComponent = $AbilityComponent
@onready var behavior_component: BehaviorComponent = $BehaviorComponent
@onready var status_effect_component: StatusEffectComponent = $StatusEffectComponent
@onready var trigger_component: TriggerComponent = $TriggerComponent


func _ready() -> void:
	set_physics_process(false)  # Only enabled during choreography phase monitoring — physics tick keeps choreography cadence deterministic (replay-safe) and synced with combat_manager's grid rebuild
	sprite.flip_h = (faction == Faction.ENEMY)
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.frame_changed.connect(_on_frame_changed)
	sprite.animation_changed.connect(_sync_shadow_animation)
	sprite.frame_changed.connect(_sync_shadow_frame)
	status_effect_component.status_expired.connect(_on_own_status_expired)
	if sprite.sprite_frames:
		_set_anim_state(AnimState.IDLE)


func _process(_delta: float) -> void:
	# Shadow is a passive visual mirror — flip_h has no signal, so poll here. Animation/frame sync is signal-driven above.
	if shadow_sprite.sprite_frames != null and shadow_sprite.flip_h != sprite.flip_h:
		shadow_sprite.flip_h = sprite.flip_h


func _sync_shadow_animation() -> void:
	if shadow_sprite.sprite_frames == null:
		return
	if not shadow_sprite.sprite_frames.has_animation(sprite.animation):
		return
	shadow_sprite.animation = sprite.animation
	shadow_sprite.frame = sprite.frame


func _sync_shadow_frame() -> void:
	if shadow_sprite.sprite_frames == null:
		return
	if not shadow_sprite.sprite_frames.has_animation(sprite.animation):
		return
	if shadow_sprite.animation != sprite.animation:
		shadow_sprite.animation = sprite.animation
	shadow_sprite.frame = sprite.frame


func _physics_process(delta: float) -> void:
	## Per-frame monitoring during choreography phases only. Physics tick
	## (not render tick) so branch evaluation cadence is fixed-rate: replays
	## reproduce across hardware, and the spatial grid queries executed by
	## branch conditions (e.g. Conceal Strike's "enemy within 20px" proximity
	## check) run on the same tick as combat_manager's grid rebuild, so the
	## grid's cell arrays never carry stale references from entities freed
	## between the last rebuild and this evaluation.
	if not is_alive or _choreography == null:
		_choreography = null
		_choreography_phase_index = -1
		set_physics_process(false)
		return

	var phase: ChoreographyPhase = _choreography.phases[_choreography_phase_index]

	if phase.exit_type == "wait":
		_choreography_timer -= delta
		# Evaluate branches each frame
		for branch in phase.branches:
			if _evaluate_choreography_branch(branch):
				_enter_choreography_phase(branch.next_phase)
				return
		# Timeout → default_next
		if _choreography_timer <= 0.0:
			_on_choreography_phase_exit()

	elif phase.exit_type == "displacement_complete":
		if not is_channeling:
			_on_choreography_phase_exit()


func get_engage_distance() -> float:
	## Engagement reach with modifier contribution layered on top of the base
	## stat. Aura-driven buffs (Goblin King's Commander aura → +20 engage on
	## scouts behind the barricade), debuffs that shrink reach, or item / talent
	## stat grants all flow through `engage_distance:add` modifiers. Returns the
	## base value unchanged when no modifier is registered.
	if modifier_component == null:
		return engage_distance
	return engage_distance + modifier_component.sum_modifiers("engage_distance", "add")


func setup_from_unit_def(p_unit_def: UnitDefinition, entity_faction: Faction,
		character_level: int = 1, unlocked_ultimate_ids: Array[String] = []) -> void:
	unit_def = p_unit_def
	faction = entity_faction
	entity_id = p_unit_def.unit_id.to_lower()
	combat_role = CombatRole.MELEE if p_unit_def.combat_role == "MELEE" else CombatRole.RANGED
	engage_distance = p_unit_def.engage_distance
	move_speed = p_unit_def.move_speed
	aggro_range = p_unit_def.aggro_range
	retarget_interval = p_unit_def.retarget_interval
	preferred_range = p_unit_def.preferred_range
	_hit_frame = p_unit_def.hit_frame

	$Sprite.sprite_frames = p_unit_def.sprite_sheet
	$Sprite.flip_h = (faction == Faction.ENEMY)
	$ShadowSprite.sprite_frames = p_unit_def.shadow_sheet
	$ShadowSprite.flip_h = (faction == Faction.ENEMY)
	$Sprite.play("idle")

	$HealthComponent.health_changed.connect($HPBar.update_bar)
	$HealthComponent.died.connect(_on_health_died)
	$HealthComponent.death_prevented.connect(_on_death_prevented)
	$HealthComponent.shield_depleted.connect(_on_shield_depleted)
	var stam: float = modifier_component.sum_modifiers("Stam", "add")
	var derived_hp: float = AttributeDerivation.derive_max_hp(stam)
	if derived_hp <= 0.0:
		derived_hp = 100.0
	$HealthComponent.setup(derived_hp)

	ability_component.setup_abilities(p_unit_def.auto_attack, p_unit_def.skills,
			character_level, unlocked_ultimate_ids)

	status_effect_component.setup(modifier_component)
	behavior_component.setup(modifier_component)
	behavior_component.ability_requested.connect(_on_ability_requested)
	behavior_component.auto_attack_requested.connect(_on_auto_attack_requested)

	if p_unit_def.auto_attack and p_unit_def.auto_attack.cooldown_base > 0.0:
		behavior_component.set_aa_interval(p_unit_def.auto_attack.cooldown_base)

	_check_heal_reactive_targeting(p_unit_def.auto_attack, p_unit_def.skills)


func setup_from_enemy_def(p_enemy_def: EnemyDefinition, entity_faction: Faction) -> void:
	## Set up entity from an EnemyDefinition resource.
	## Mirrors setup_from_unit_def() but reads from EnemyDefinition.
	faction = entity_faction
	enemy_def = p_enemy_def
	entity_id = p_enemy_def.enemy_id
	combat_role = CombatRole.MELEE if p_enemy_def.combat_role == "MELEE" else CombatRole.RANGED
	engage_distance = p_enemy_def.engage_distance
	move_speed = p_enemy_def.move_speed
	aggro_range = p_enemy_def.aggro_range
	retarget_interval = p_enemy_def.retarget_interval
	preferred_range = p_enemy_def.preferred_range
	_hit_frame = p_enemy_def.hit_frame
	priority_role = p_enemy_def.priority_role
	is_elite = p_enemy_def.is_elite
	is_boss = p_enemy_def.is_boss

	$Sprite.sprite_frames = p_enemy_def.sprite_sheet
	$Sprite.flip_h = (faction == Faction.ENEMY)
	$ShadowSprite.sprite_frames = p_enemy_def.shadow_sheet
	$ShadowSprite.flip_h = (faction == Faction.ENEMY)
	$Sprite.play("idle")

	# Wire health
	$HealthComponent.health_changed.connect($HPBar.update_bar)
	$HealthComponent.died.connect(_on_health_died)
	$HealthComponent.death_prevented.connect(_on_death_prevented)
	$HealthComponent.shield_depleted.connect(_on_shield_depleted)
	var stam: float = modifier_component.sum_modifiers("Stam", "add")
	var derived_hp: float = AttributeDerivation.derive_max_hp(stam)
	if derived_hp <= 0.0:
		derived_hp = 100.0
	$HealthComponent.setup(derived_hp)

	# Abilities — enemies use all abilities (no level gating), pass level 99
	ability_component.setup_abilities(p_enemy_def.auto_attack, p_enemy_def.skills, 99)

	# Components
	status_effect_component.setup(modifier_component)
	behavior_component.setup(modifier_component)
	behavior_component.ability_requested.connect(_on_ability_requested)
	behavior_component.auto_attack_requested.connect(_on_auto_attack_requested)

	# Override AA interval if specified (Dex-derived can't produce intervals > 0.5s)
	if p_enemy_def.aa_interval_override > 0.0:
		behavior_component._auto_attack_interval = p_enemy_def.aa_interval_override

	# Enable heal-reactive targeting if any ability uses it
	_check_heal_reactive_targeting(p_enemy_def.auto_attack, p_enemy_def.skills)

	# Innate statuses (auras, passive self-buffs) — parallels talent.apply_statuses
	# on heroes. Self-applied so source = bearer; downstream attribution
	# (aura_tick_effects, on-hit listeners) all resolves to this entity.
	for status_data in p_enemy_def.apply_statuses:
		if status_data is ApplyStatusEffectData:
			status_effect_component.apply_status(
					status_data.status, self, status_data.stacks, status_data.duration)


# --- Ability / Auto-attack Execution ---

func _on_ability_requested(ability: AbilityDefinition, targets: Array) -> void:
	# Don't interrupt an in-progress ability animation (auto-attacks CAN be interrupted)
	if _ability_anim_active:
		return

	_pending_ability = ability
	_pending_targets = targets
	_resolve_attack_params(ability)

	# Echo replay scheduling — captures BEFORE any path routing (non-animated dispatch,
	# animated attack, channel start, choreography start) so a cast that APPLIES echo
	# (Cleric Salvation) does not self-echo. Runs once per cast; multi-hit hit-frame
	# re-entries never reach this function.
	_schedule_echo_replays(ability, targets)

	# Multi-phase choreography abilities (conceal, dash-strike-retreat, etc.)
	if ability.choreography != null:
		_pending_ability = null  # Phase effects handle dispatch, not _execute_pending_effects
		_pending_targets = []
		_start_choreography(ability)
		return

	# Channeled abilities: play animation sequence, apply effects immediately
	if ability.tags.has("Channel"):
		_start_channel(ability)
		return

	# Abilities with animated effects play the attack animation and fire on hit frame.
	# Non-animated abilities (buffs, status applications) fire immediately.
	# anim_override explicitly declares "this ability wants a custom animation" —
	# always honor it, even if the only effects are status applications (Word of Pain, Denounce).
	var has_animated_effect := ability.anim_override != ""
	if not has_animated_effect:
		for effect in ability.effects:
			if effect is DealDamageEffect or effect is SpawnProjectilesEffect or effect is HealEffect:
				has_animated_effect = true
				break

	if has_animated_effect:
		_ability_anim_active = true
		_anim_on_complete = ability.anim_on_complete
		if ability.grants_invulnerability:
			is_invulnerable = true
		# Restart attack animation so VFX and hit frame fire cleanly
		is_attacking = false
		anim_state = AnimState.IDLE
		start_attack()
	else:
		EventBus.on_ability_used.emit(self, ability)
		_execute_pending_effects()


func _on_auto_attack_requested(ability: AbilityDefinition, targets: Array) -> void:
	if is_attacking:
		return  # Auto-attacks never interrupt ongoing attacks
	_pending_ability = ability
	_pending_targets = targets
	_resolve_attack_params(ability)

	# Echo replay scheduling — AA casts need the same pre-dispatch capture as
	# ability casts so AA-eligible echo sources (Ranger Echo Shot's cadence
	# counter, Fusillade's per-AA echo, future AA-driven echoes) can schedule.
	# Mirrors the call in _on_ability_requested; runs once per AA cast.
	_schedule_echo_replays(ability, targets)

	start_attack()


func _resolve_attack_params(ability: AbilityDefinition) -> void:
	## Set animation and hit frame from ability overrides, falling back to entity defaults.
	_current_attack_anim = ability.anim_override if ability.anim_override != "" else "attack"
	_current_hit_frame = ability.hit_frame_override if ability.hit_frame_override >= 0 else _hit_frame


func _schedule_echo_replays(ability: AbilityDefinition, targets: Array) -> void:
	## Gather active echo sources on this entity and schedule replays for each
	## eligible source. Called once per cast from _on_ability_requested, before
	## any effect dispatch runs. Pre-dispatch capture is load-bearing: a cast
	## that APPLIES echo (e.g. Cleric Salvation applying Echo to all allies
	## including the caster) must NOT trigger self-echo; by capturing here, the
	## caster's echo state is read before Salvation's effects fire.
	##
	## echoable is opt-in: most abilities are not echoable (buffs, debuffs, CC,
	## utility, movement). Damage abilities, heals, summons, projectiles, and
	## AOE damage opt in by setting echoable = true in their data factory.
	## Toggle-mode abilities are universally excluded — toggling on/off should
	## not consume an echo replay.
	if combat_manager == null:
		return
	if not ability.echoable:
		return
	if ability.mode == "Toggle":
		return

	var status_sources: Array = status_effect_component.get_active_echo_sources()
	var modifier_sources: Array = modifier_component.get_echo_sources()

	# Status-driven sources first (deterministic processing order), then modifier-driven.
	for pair in status_sources:
		var status_id: String = pair[0]
		var config: EchoSourceConfig = pair[1]
		if not _echo_source_eligible(ability, config):
			continue
		if config.proc_chance < 1.0 and combat_manager.rng.randf() > config.proc_chance:
			continue
		if not _echo_cadence_ready(config):
			continue
		var effective_delay: float
		if ability.echo_delay_override >= 0.0:
			effective_delay = ability.echo_delay_override
		else:
			effective_delay = config.delay
		var captured: Array = []
		if config.capture_targets:
			captured = targets.duplicate()
		combat_manager.schedule_echo(self, ability, config, effective_delay, captured)
		if config.consumes_source:
			status_effect_component.remove_status(status_id)

	for config in modifier_sources:
		if not _echo_source_eligible(ability, config):
			continue
		if config.proc_chance < 1.0 and combat_manager.rng.randf() > config.proc_chance:
			continue
		if not _echo_cadence_ready(config):
			continue
		var effective_delay: float
		if ability.echo_delay_override >= 0.0:
			effective_delay = ability.echo_delay_override
		else:
			effective_delay = config.delay
		var captured: Array = []
		if config.capture_targets:
			captured = targets.duplicate()
		combat_manager.schedule_echo(self, ability, config, effective_delay, captured)
		# Modifier-driven sources don't self-consume — they're permanent for the run.


func _echo_source_eligible(ability: AbilityDefinition, config: EchoSourceConfig) -> bool:
	var is_aa: bool = (ability == ability_component.get_auto_attack())
	var is_channel: bool = ability.tags.has("Channel")
	if is_aa and not config.allow_auto_attacks:
		return false
	if is_channel and not config.allow_channels:
		return false
	# Skills = neither AA nor Channel. Opt-in per-config so AA-only echo sources
	# (Ranger Echo Shot) can refuse skill casts. Default true preserves Salvation.
	if not is_aa and not is_channel and not config.allow_skills:
		return false
	# Ability-tag filters (item-driven). Whitelist empty = any tag passes;
	# non-empty requires at least one listed tag. Blacklist empty = no
	# exclusions; non-empty rejects when any listed tag is present. Both
	# evaluated together so a config can declare both gates.
	if not config.ability_tag_whitelist.is_empty():
		var any_match: bool = false
		for tag in config.ability_tag_whitelist:
			if ability.tags.has(tag):
				any_match = true
				break
		if not any_match:
			return false
	if not config.ability_tag_blacklist.is_empty():
		for tag in config.ability_tag_blacklist:
			if ability.tags.has(tag):
				return false
	return true


func _echo_cadence_ready(config: EchoSourceConfig) -> bool:
	## When cadence_every_n > 0, echo fires every Nth eligible cast for this
	## source. Counter is keyed by config.source_id on this entity (so two
	## different echo sources on the same bearer tick independently). Counter
	## increments regardless of gate outcome — "every 3rd AA" means the 3rd,
	## 6th, 9th ... AA in global cast order, not "3 AAs that passed every prior
	## gate." The existing proc_chance gate runs BEFORE this check and can
	## short-circuit the increment; that's intentional — a proc_chance=1.0
	## config (Echo Shot's shape) always reaches cadence evaluation.
	if config.cadence_every_n <= 0:
		return true
	var key: String = config.source_id
	var counter: int = int(_echo_cast_counters.get(key, 0)) + 1
	_echo_cast_counters[key] = counter
	return counter % config.cadence_every_n == 0


# --- Channeling ---

func _start_channel(ability: AbilityDefinition) -> void:
	## Begin a channeled ability: lock out behavior, apply effects, play animation sequence.
	## Three channel modes:
	##   Multi-hit (has anim_override + hit_frames): play anim, fire effects on each hit frame.
	##   Single-animation (has anim_override, no hit_frames): play anim, end on finish.
	##   Multi-phase block (no anim_override): block_up → block_impact → block_down,
	##     tied to status duration via _channel_status_id.

	# Only track status expiry for multi-phase channels (Sword Guard pattern)
	if ability.anim_override == "":
		for effect in ability.effects:
			if effect is ApplyStatusEffectData:
				_channel_status_id = effect.status.status_id
				break

	is_channeling = true
	is_attacking = true  # Suppresses DMG animation and prevents attack restarts

	# Multi-hit channels defer effects to hit frames — don't fire immediately.
	# VFX fires on vfx_frame via _on_frame_changed (not here — avoids double emit).
	if not ability.hit_frames.is_empty():
		_hit_frames_fired.clear()
		_hit_frame_fired = false
		_vfx_frame_fired = false
	else:
		# Apply effects immediately (status application starts protection)
		EventBus.on_ability_used.emit(self, ability)
		_execute_pending_effects()

	# Start appropriate animation — reset speed_scale to native 1.0 in case a
	# prior AA left it scaled (attack_speed:bonus affects AA animations only).
	sprite.speed_scale = 1.0
	if ability.anim_override != "":
		sprite.play(ability.anim_override)
	else:
		sprite.play("block_up")


func _end_channel() -> void:
	## Channel status expired — play recovery animation. Still locked out during recovery.
	sprite.speed_scale = 1.0
	sprite.play("block_down")


func _on_own_status_expired(status_id: String) -> void:
	if is_channeling and status_id == _channel_status_id:
		_end_channel()


# --- Animation ---

func _set_anim_state(new_state: AnimState) -> void:
	if anim_state == new_state and sprite.is_playing():
		return
	anim_state = new_state
	# Animation speed_scale: AA animations scale with attack_speed:bonus so
	# high-AS builds actually deliver throughput past the raw-animation-duration
	# floor. Ability animations (anim_override set via _pending_ability != AA),
	# channels, choreography, and non-attack states all play at native 1.0 rate —
	# ability cast speed is a separate concept that hasn't been wired yet.
	# The AA's BehaviorComponent timer already scales by (1 + bonus); scaling the
	# animation with the same factor keeps timer and animation aligned so no
	# double-scaling occurs — both drop in lockstep as AS stacks.
	if new_state == AnimState.ATTACK and _is_pending_ability_aa():
		sprite.speed_scale = _get_aa_anim_speed_scale()
	elif new_state == AnimState.ATTACK and _pending_ability != null:
		# Non-AA ability cast: scale animation by `cast_speed:bonus` so item
		# / talent grants speed up the swing visibly. Cooldowns are unaffected
		# (CDR is the existing lever); this is animation-speed only — the timer
		# that controls when the next ability can fire still runs at native rate.
		sprite.speed_scale = _get_cast_anim_speed_scale()
	else:
		sprite.speed_scale = 1.0
	match new_state:
		AnimState.IDLE:
			sprite.play("idle")
		AnimState.WALK:
			sprite.play("walk")
		AnimState.ATTACK:
			sprite.play(_current_attack_anim)
		AnimState.DMG:
			sprite.play("dmg")
		AnimState.DIE:
			sprite.play("die")


func _is_pending_ability_aa() -> bool:
	## True when the in-flight animation is an auto-attack (not an ability cast).
	## Used to gate AA-only speed_scale application in _set_anim_state.
	return _pending_ability != null and _pending_ability == ability_component.get_auto_attack()


func _get_aa_anim_speed_scale() -> float:
	## Scales the AA sprite animation by (1 + attack_speed:bonus), clamped at a
	## small positive floor to prevent reverse playback if modifiers ever sum
	## below -1. Read each AA start — mid-animation modifier changes don't
	## retroactively adjust the currently-playing swing; the NEXT AA picks up
	## the new scale.
	if not modifier_component:
		return 1.0
	var bonus: float = modifier_component.sum_modifiers("attack_speed", "bonus")
	return maxf(0.1, 1.0 + bonus)


func _get_cast_anim_speed_scale() -> float:
	## Parallels _get_aa_anim_speed_scale for non-AA ability casts. Reads
	## `cast_speed:bonus` so an item granting +50% cast speed plays the ability
	## animation at 1.5× rate. Same floor convention prevents reverse playback.
	if not modifier_component:
		return 1.0
	var bonus: float = modifier_component.sum_modifiers("cast_speed", "bonus")
	return maxf(0.1, 1.0 + bonus)


func _on_animation_finished() -> void:
	if not is_alive:
		return
	# Choreography animation handling (multi-phase abilities)
	if _choreography != null:
		_on_choreography_animation_finished()
		return
	# Channeled ability animation handling
	if is_channeling:
		# Multi-phase block channel (Sword Guard): block_up → block_impact → block_down → idle
		if sprite.animation == "block_up":
			sprite.speed_scale = 1.0  # Channel loops play at native rate
			sprite.play("block_impact")  # Loops until status expires
			return
		if sprite.animation == "block_down":
			is_channeling = false
			is_attacking = false
			_channel_status_id = ""
			_set_anim_state(AnimState.IDLE)
			return
		if sprite.animation == "block_impact":
			return  # Looping — shouldn't fire finished
		# Single-animation channel (Fire Torrent, etc.): animation done, end channel
		is_channeling = false
		is_attacking = false
		_ability_anim_active = false
		_pending_ability = null
		_pending_targets = []
		_hit_frames_fired.clear()
		_set_anim_state(AnimState.IDLE)
		return

	if anim_state == AnimState.DMG:
		# Hit reaction interrupted the attack — reset so BehaviorComponent can restart
		is_attacking = false
		_ability_anim_active = false
		is_invulnerable = false
		_anim_on_complete = ""
		_pending_ability = null
		_pending_targets = []
		_set_anim_state(AnimState.IDLE)
		return
	if anim_state == AnimState.ATTACK:
		# Two-phase animation: primary finished, chain to follow-up (e.g. teleport_start → teleport_end)
		if _anim_on_complete != "":
			var next_anim := _anim_on_complete
			_anim_on_complete = ""
			_current_attack_anim = next_anim
			# Two-phase abilities are ability casts, not AAs — reset to native
			# rate (any AA scaling that might have leaked in is irrelevant here).
			sprite.speed_scale = 1.0
			sprite.play(next_anim)
			return
		# Attack animation done — go idle, wait for BehaviorComponent to request next action
		is_attacking = false
		_ability_anim_active = false
		is_invulnerable = false  # Clear invulnerability when final animation completes
		_set_anim_state(AnimState.IDLE)


func set_marching(is_marching: bool) -> void:
	if not is_alive or is_channeling or _ability_anim_active:
		return
	is_attacking = false
	_ability_anim_active = false
	in_combat = false
	attack_target = null
	_pending_ability = null
	_pending_targets = []
	_set_anim_state(AnimState.WALK if is_marching else AnimState.IDLE)


func start_attack() -> void:
	if not is_alive or is_channeling:
		return
	in_combat = true
	if is_attacking:
		return  # Already mid-swing — don't restart animation
	is_attacking = true
	_hit_frame_fired = false
	_vfx_frame_fired = false
	_hit_frames_fired.clear()
	_set_anim_state(AnimState.ATTACK)


# --- Hit-frame damage (fires through DamageCalculator) ---

func _on_frame_changed() -> void:
	if not is_attacking or not is_alive:
		return
	# Choreography phase: fire phase effects on hit frame
	if _choreography != null:
		var phase: ChoreographyPhase = _choreography.phases[_choreography_phase_index]
		if phase.hit_frame >= 0 and sprite.animation == _current_attack_anim \
				and sprite.frame == phase.hit_frame and not _hit_frame_fired:
			_hit_frame_fired = true
			_execute_choreography_phase_effects(phase)
		return
	# Multi-phase channels (Sword Guard, no anim_override) skip frame dispatch entirely.
	# Single-animation channels with hit_frames (Fire Torrent) allow frame dispatch.
	if is_channeling and (_pending_ability == null or _pending_ability.hit_frames.is_empty()):
		return
	if sprite.animation != _current_attack_anim:
		return

	# VFX frame — fire ability VFX before damage lands
	if _pending_ability and not _vfx_frame_fired and sprite.frame == _pending_ability.vfx_frame:
		_vfx_frame_fired = true
		EventBus.on_ability_used.emit(self, _pending_ability)
		# Spawn target VFX for heal effects (visual starts now, heal applies on hit frame)
		_spawn_target_vfx()

	# Multi-hit frames — re-resolve targets each hit (AOE channels like Fire Torrent)
	if _pending_ability and not _pending_ability.hit_frames.is_empty():
		if _pending_ability.hit_frames.has(sprite.frame) and not _hit_frames_fired.has(sprite.frame):
			_hit_frames_fired[sprite.frame] = true
			_execute_pending_effects(true)  # keep_pending = true
		return

	# Single hit frame — deal damage
	if sprite.frame == _current_hit_frame and not _hit_frame_fired:
		_hit_frame_fired = true
		_execute_pending_effects()


func _spawn_target_vfx() -> void:
	## Spawn one-shot VFX on pending targets from ability.target_vfx_layers.
	## Called on vfx_frame so the visual starts before the effect fires on hit_frame.
	if not _pending_ability or _pending_ability.target_vfx_layers.is_empty():
		return
	var targets: Array = _pending_targets if not _pending_targets.is_empty() \
			else ([attack_target] if is_instance_valid(attack_target) and attack_target.is_alive else [])
	var pm: ParticleManager = combat_manager.particle_manager if combat_manager else null
	for target in targets:
		if not is_instance_valid(target) or not target.is_alive:
			continue
		for layer in _pending_ability.target_vfx_layers:
			if layer is ParticleVfxLayerConfig:
				if not pm:
					continue
				var p_offset := Vector2(layer.offset)
				if target.sprite.flip_h:
					p_offset.x = -p_offset.x
				p_offset = p_offset.round()
				var parent: Node
				var pos: Vector2
				if layer.follow_entity:
					parent = target
					pos = p_offset
				else:
					parent = combat_manager
					pos = (target.position + p_offset).round()
				pm.claim(layer.preset, pos, parent, layer.follow_entity)
			else:
				var vfx_offset := Vector2(layer.offset)
				if target.sprite.flip_h:
					vfx_offset.x = -vfx_offset.x
				var fx = VfxEffect.create(layer.sprite_frames, layer.animation,
						false, layer.z_index, vfx_offset, layer.scale)
				target.add_child(fx)


func _execute_pending_effects(keep_pending: bool = false) -> void:
	var ability := _pending_ability
	if not ability:
		ability = ability_component.get_auto_attack()
	if not ability:
		return
	_overflow_damage_accumulator = 0.0

	# Clear stale overkill on targets before effects execute — prevents
	# OverflowChainEffect from reading overkill from kills by OTHER sources
	# that happened between targeting resolution and this hit frame.
	for t in _pending_targets:
		if is_instance_valid(t):
			t.health.last_overkill = 0.0

	# Determine targets — re-resolve using hit_targeting when available
	var targets: Array = []
	if ability.hit_targeting:
		# hit_targeting set: always re-resolve at hit time using the wider damage area
		# (trigger targeting determined when to fire; hit_targeting determines who gets hit)
		targets = behavior_component.resolve_targets_with_rule(ability.hit_targeting, self)
	elif keep_pending and ability.targeting:
		# Multi-hit re-resolution (AOE channels without hit_targeting)
		targets = behavior_component.resolve_targets_with_rule(ability.targeting, self)
	elif not _pending_targets.is_empty():
		targets = _pending_targets
	elif is_instance_valid(attack_target) and attack_target.is_alive:
		targets = [attack_target]

	# Some effects don't need pre-resolved targets — projectiles find their own
	# via collision, summons spawn near the caster. Allow execution even with empty targets.
	if targets.is_empty():
		var has_targetless_effect := false
		for effect in ability.effects:
			if effect is SpawnProjectilesEffect or effect is SummonEffect:
				has_targetless_effect = true
				break
		if not has_targetless_effect:
			return

	# Execute all effects via centralized dispatcher
	EffectDispatcher.execute_effects(ability.effects, self, targets, ability, get_parent(), null, ability.ability_id)

	# Dispatch talent/item ability modifications grouped by registration source.
	# Item-sourced groups carry a contributors list so downstream HitData
	# attributes the item-driven delta back to the wearer's item.
	for group in ability_component.get_ability_modification_groups(ability.ability_id):
		var group_src: String = group[0]
		var group_effects: Array = group[1]
		if group_effects.is_empty():
			continue
		var group_contributors: Array = []
		if group_src.begins_with("item_"):
			group_contributors = [{
				"entity": self,
				"source_name": group_src,
				"role": "item_ability_modification",
			}]
		EffectDispatcher.execute_effects(group_effects, self, targets, ability,
				get_parent(), null, "mod:" + ability.ability_id, 1.0, null, group_contributors)

	# Clear pending (unless multi-hit — keep ability alive for remaining frames)
	if not keep_pending:
		_pending_ability = null
		_pending_targets = []


# --- Choreography (generic multi-phase ability sequences) ---

func _start_choreography(ability: AbilityDefinition) -> void:
	## Begin a choreography sequence. Sets up state and enters phase 0.
	## Phase effects default to `find_nearest` when no phase-level `retarget`
	## is set — the ability's cast-time resolved target is deliberately NOT
	## carried through. Defensive/reactive choreographies (Conceal Strike) want
	## phase dispatch to re-read the world at strike time, not lock onto a
	## target chosen at cast. Choreographies that need cast-time locking should
	## set `phase.retarget` explicitly.
	_choreography = ability.choreography
	_choreography_ability = ability
	_choreography_targets = []
	_channel_scroll_anchor = _choreography.scroll_anchor

	is_channeling = true
	is_attacking = true  # Suppresses DMG animation
	_ability_anim_active = true  # Prevents interruption
	attack_target = null
	in_combat = false

	EventBus.on_ability_used.emit(self, ability)
	_enter_choreography_phase(0)


func _start_spawn_intro(choreography: ChoreographyDefinition) -> void:
	## Spawn-time variant of _start_choreography. No ability context — used for
	## entity intros (Deep One emerge/jump/land, future burrow-up / drop-in / etc.).
	## Skips EventBus.on_ability_used (not an ability cast) and leaves
	## _choreography_ability null; effect/mod-group paths in
	## _execute_choreography_phase_effects null-guard on it.
	_choreography = choreography
	_choreography_ability = null
	_choreography_targets = []
	_channel_scroll_anchor = choreography.scroll_anchor

	is_channeling = true
	is_attacking = true
	_ability_anim_active = true
	attack_target = null
	in_combat = false

	_enter_choreography_phase(0)


func _enter_choreography_phase(index: int) -> void:
	## Enter a specific phase of the choreography. index = -1 ends the choreography.
	if index < 0 or index >= _choreography.phases.size():
		_end_choreography()
		return

	_choreography_phase_index = index
	var phase: ChoreographyPhase = _choreography.phases[index]

	# Re-assert channeling. The "displacement_complete" exit type consumes
	# is_channeling as its done-signal (DisplacementSystem._on_arrival clears it
	# to wake the phase-exit detector in _physics_process). Subsequent phases
	# need it restored, otherwise MovementSystem wakes the AI mid-choreography.
	# Only _end_choreography clears channeling for real.
	is_channeling = true

	# Entity state flags for this phase
	is_untargetable = phase.set_untargetable
	is_invulnerable = phase.set_invulnerable

	# Retarget if this phase specifies a targeting rule
	if phase.retarget and spatial_grid:
		var targets: Array = behavior_component.resolve_targets_with_rule(phase.retarget, self)
		if not targets.is_empty():
			_choreography_targets = targets

	# Execute displacement if specified
	if phase.displacement:
		var cm: Node2D = get_parent()
		if cm and cm.get("displacement_system"):
			# For displacement: source context depends on choreography targets
			# If we have targets, first target is the "source" for direction computation
			var disp_source: Node2D = _choreography_targets[0] if not _choreography_targets.is_empty() else self
			cm.displacement_system.execute(disp_source, _choreography_ability, phase.displacement, [self])

	# Fire effects immediately if no hit_frame specified (hit_frame = -1 means fire on entry)
	if phase.hit_frame < 0 and not phase.effects.is_empty():
		_execute_choreography_phase_effects(phase)

	# Play animation or set up wait/displacement monitoring
	if phase.animation != "":
		_current_attack_anim = phase.animation
		_hit_frame_fired = false
		_vfx_frame_fired = false
		is_attacking = true

		# Face toward nearest enemy before attack phases (facing suppressed during channeling)
		if phase.hit_frame >= 0 and spatial_grid:
			var enemy_faction_id: int = 1 if faction == Faction.HERO else 0
			var nearest: Node2D = spatial_grid.find_nearest(position, enemy_faction_id)
			if nearest:
				sprite.flip_h = nearest.position.x < position.x

		# Reset speed_scale to native — choreography phases aren't AAs and shouldn't
		# inherit any prior AA scaling.
		sprite.speed_scale = 1.0
		sprite.play(phase.animation)

	# Set up phase exit monitoring
	match phase.exit_type:
		"wait":
			_choreography_timer = phase.wait_duration
			set_physics_process(true)
		"displacement_complete":
			set_physics_process(true)
		"anim_finished":
			# Handled by _on_choreography_animation_finished
			if phase.animation == "":
				# No animation and anim_finished exit → immediate transition
				_on_choreography_phase_exit()


func _on_choreography_animation_finished() -> void:
	## Animation finished during a choreography phase.
	var phase: ChoreographyPhase = _choreography.phases[_choreography_phase_index]
	if phase.exit_type == "anim_finished":
		_on_choreography_phase_exit()
	# Other exit types: animation may finish but phase continues (e.g. displacement_complete)


func _on_choreography_phase_exit() -> void:
	## Current phase is complete. Evaluate default_next to transition.
	set_physics_process(false)
	var phase: ChoreographyPhase = _choreography.phases[_choreography_phase_index]
	_enter_choreography_phase(phase.default_next)


func _execute_choreography_phase_effects(phase: ChoreographyPhase) -> void:
	## Fire effects for the current choreography phase.
	## _choreography_ability may be null (spawn intros) — ability-id / mod-group
	## paths are guarded so intros with effects still work.
	var ability_id: String = _choreography_ability.ability_id if _choreography_ability else ""
	var mod_groups: Array = []
	if _choreography_ability:
		mod_groups = ability_component.get_ability_modification_groups(ability_id)
	if phase.effects.is_empty() and mod_groups.is_empty():
		return

	# Resolve targets: use choreography targets, fall back to nearest enemy
	var targets: Array = _choreography_targets.duplicate()
	if targets.is_empty() and spatial_grid:
		var enemy_faction_id: int = 1 if faction == Faction.HERO else 0
		var nearest: Node2D = spatial_grid.find_nearest(position, enemy_faction_id)
		if nearest:
			targets = [nearest]

	# Set attack_target so projectile spawn (aimed_single) can find its aim direction
	if not targets.is_empty():
		attack_target = targets[0]

	if not phase.effects.is_empty():
		EffectDispatcher.execute_effects(phase.effects, self, targets, _choreography_ability, get_parent(), null, ability_id)

	# Per-group dispatch of talent/item ability modifications. Same pattern as
	# _execute_pending_effects — item-sourced groups carry a contributors list.
	for group in mod_groups:
		var group_src: String = group[0]
		var group_effects: Array = group[1]
		if group_effects.is_empty():
			continue
		var group_contributors: Array = []
		if group_src.begins_with("item_"):
			group_contributors = [{
				"entity": self,
				"source_name": group_src,
				"role": "item_ability_modification",
			}]
		EffectDispatcher.execute_effects(group_effects, self, targets,
				_choreography_ability, get_parent(), null,
				"mod:" + ability_id, 1.0, null, group_contributors)


func _evaluate_choreography_branch(branch: ChoreographyBranch) -> bool:
	## Evaluate a single choreography branch condition.
	## Uses the same condition types as ability conditions but evaluated against
	## spatial/entity state rather than ability readiness.
	if not branch.condition:
		return true  # No condition = always taken

	var condition: Resource = branch.condition
	if condition is ConditionEntityCount:
		return ability_component._check_entity_count(condition, self)
	elif condition is ConditionStackCount:
		return ability_component._check_stack_count(condition, self)
	# Future condition types can be added here as match arms
	return false


func _end_choreography() -> void:
	## Clean up all choreography state and return to normal behavior.
	_choreography = null
	_choreography_ability = null
	_choreography_phase_index = -1
	_choreography_timer = 0.0
	_choreography_targets = []
	_channel_scroll_anchor = false
	is_untargetable = false
	is_invulnerable = false
	is_channeling = false
	is_attacking = false
	_ability_anim_active = false
	engagement_target = null  # Force movement system to re-engage fresh (prevents stale no-op)
	attack_target = null
	in_combat = false
	_pending_ability = null
	_pending_targets = []
	formation_pos = position  # Hold post-displacement position (no-op if position unchanged)
	_last_position = position  # Prevent phantom facing from stale position
	set_physics_process(false)
	_set_anim_state(AnimState.IDLE)


# --- Facing ---

func update_facing() -> void:
	## Update sprite facing based on attack target, desired position, or movement direction.
	## Called by MovementSystem after position updates each frame.
	if not is_alive or is_channeling:
		_last_position = position
		return
	if is_instance_valid(attack_target) and attack_target.is_alive:
		sprite.flip_h = attack_target.position.x < position.x
	elif desired_position != Vector2.ZERO and position.distance_squared_to(desired_position) > 1.0:
		# Face toward desired_position when moving (handles dead zone frames
		# where position hasn't changed yet but intent is clear)
		var desired_dx: float = desired_position.x - position.x
		if absf(desired_dx) > 0.5:
			sprite.flip_h = desired_dx < 0.0
	else:
		var dx: float = position.x - _last_position.x
		if absf(dx) > 0.5:
			sprite.flip_h = dx < 0.0
		elif not in_combat:
			# Idle at destination — face faction default (heroes right, enemies left)
			sprite.flip_h = (faction == Faction.ENEMY)
	_last_position = position


func _check_heal_reactive_targeting(auto_attack: AbilityDefinition,
		skills: Array) -> void:
	## Scan abilities for heal-reactive targeting type. If any use it,
	## enable the on_heal listener on BehaviorComponent.
	if auto_attack and auto_attack.targeting and auto_attack.targeting.type == "most_recently_healed_enemy":
		behavior_component.enable_heal_reactive_targeting()
		return
	for skill in skills:
		if skill.ability and skill.ability.targeting and skill.ability.targeting.type == "most_recently_healed_enemy":
			behavior_component.enable_heal_reactive_targeting()
			return


func take_damage(hit_data) -> void:
	if not is_alive:
		return
	if is_invulnerable:
		return
	if status_effect_component.is_invulnerability_active():
		return
	last_hit_by = hit_data.source if hit_data is HitData else hit_data.get("source")
	last_hit_time = combat_manager.run_time if combat_manager else 0.0
	# Track per-tag hit times for tag-filtered conditions (e.g. ConditionTakingDamage with required_tag)
	if hit_data is HitData and hit_data.ability:
		var now: float = last_hit_time
		for tag in hit_data.ability.tags:
			_last_hit_time_by_tag[tag] = now
	health.apply_damage(hit_data)
	var source = hit_data.source if hit_data is HitData else hit_data.get("source")
	EventBus.on_hit_dealt.emit(source, self, hit_data)
	EventBus.on_hit_received.emit(source, self, hit_data)
	# Crit event
	if hit_data is HitData and hit_data.is_crit:
		EventBus.on_crit.emit(source, self, hit_data)
	# Status on-hit-received effects (e.g. Sword Guard stacking damage bonus)
	status_effect_component.notify_hit_received(hit_data)
	# Status on-hit-dealt effects (e.g. Denounce bonus Holy damage)
	# Only fires for ability-driven hits to prevent recursion (proc damage has null ability)
	# Skip if target died from this hit — effects against dead targets are wasted work
	if is_alive and hit_data is HitData and hit_data.ability != null:
		if is_instance_valid(source) and source.is_alive:
			source.status_effect_component.notify_hit_dealt(self, hit_data)
	# Hit reaction: suppressed by attacking (uninterruptible) and channeling (bracing).
	# Stunned entities DO play hit reactions — stun locks actions, not reactions.
	if is_alive and not is_attacking and not is_channeling:
		_set_anim_state(AnimState.DMG)


# --- Death ---

func _on_death_prevented(_entity: Node2D) -> void:
	status_effect_component.on_death_prevented()


func _on_shield_depleted(_entity: Node2D) -> void:
	status_effect_component.expire_statuses_with_tag("Shield")


func _on_health_died(_entity: Node2D) -> void:
	if not is_alive:
		return
	is_alive = false
	is_attacking = false
	_ability_anim_active = false
	is_channeling = false
	is_invulnerable = false
	is_untargetable = false
	_channel_status_id = ""
	_anim_on_complete = ""
	_choreography = null
	_choreography_ability = null
	_choreography_phase_index = -1
	set_physics_process(false)
	attack_target = null
	engagement_target = null
	if sprite.sprite_frames.has_animation("die"):
		_set_anim_state(AnimState.DIE)
		await sprite.animation_finished
		# Revived mid-die (Undying Pact fired on_death, combat_manager.revive_entity
		# restored is_alive before the die animation completed): skip the corpse-
		# freeze path entirely. The revive has already played "idle" on the sprite
		# and reset state — any post-await corpse mutation here would clobber it.
		if is_alive:
			return
		if persist_as_corpse:
			is_corpse = true
			# Freeze on corpse frame: last frame before the 8-frame despawn effect
			sprite.stop()
			sprite.frame = sprite.sprite_frames.get_frame_count("die") - 9
			hp_bar.visible = false
		else:
			queue_free()
	else:
		_spawn_death_poof()
		sprite.visible = false
		hp_bar.visible = false
		await get_tree().create_timer(0.4).timeout
		if is_alive:
			return
		queue_free()


func _spawn_death_poof() -> void:
	pass
