class_name StatusEffectComponent
extends Node
## Manages all active status effects on this entity.
## Handles stacking, duration, modifier registration/removal, and periodic ticks.

class ActiveStatus:
	var definition: StatusEffectDefinition
	var stacks: int = 1
	var time_remaining: float = 0.0
	var source: Node2D = null
	var tick_timer: float = 0.0
	var _runtime_modifiers: Array = []  ## Currently registered ModifierDefinitions
	var _has_decay_modifiers: bool = false  ## True if any modifier has decay = true (computed at apply)
	var _accumulated_shield: float = 0.0  ## Shield accrued during status lifetime (applied on expiry)
	var _accumulated_bank: float = 0.0    ## Damage payload accrued during status lifetime (read at dispatch, e.g. Crown Shot paint → banked shot)
	var _extension_count: int = 0          ## How many times this status has been extended (for max_extensions cap)
	var _applied_duration: float = 0.0    ## Duration value when this status was (re)applied — used by refresh_hots to restore to full
	## Source-driven runtime overrides — locked at first apply (talent scope is bound
	## to the source entity, doesn't change mid-fight). max_stacks bonus via additive
	## `<status_id>:max_stacks_bonus` on source modifier component; tick interval via
	## `<status_id>:tick_rate_bonus` (interval / (1 + bonus)). First consumer: Wizard
	## Accelerant (Burn max_stacks +3 → 8, tick rate +30%).
	var _runtime_max_stacks: int = 0       ## 0 = uninitialized (use definition.max_stacks)
	var _runtime_tick_interval: float = -1.0  ## < 0 = uninitialized (use definition.tick_interval)
	## Modifiers snapshotted from the source's status_modifier_injections at first
	## apply. Walked alongside definition modifiers in _sync_modifiers — scaled
	## per-stack identically. First consumer: Wizard Scorched (Burn → +3% Fire
	## vulnerability per stack on bearer).
	var _injected_modifiers: Array = []
	## Tick interval snapshotted at first apply (after source-driven overrides).
	## Used by AmplifyActiveStatusEffect to restore tick rate when enhancement
	## erodes — parallels _applied_duration for the tick-rate axis.
	var _applied_tick_interval: float = -1.0
	## Per-instance tick-power bonus snapshotted at first apply from bearer-side
	## amplifier modifiers (Witch Doctor Amplifier — Afflictor T3). Multiplies the
	## `power` factor in _execute_tick_effects as (1 + _tick_power_bonus) so an
	## amplified Burn deals +25% per tick for its full duration, independent of
	## bearer-wide tick_power and independent of whether the amplifier's own debuff
	## later falls off (sticky). Bearer-wide tick_power still applies on top
	## (Martyr's Resolve debuff dampening, etc.).
	var _tick_power_bonus: float = 0.0
	## Combat run_time after which this instance is no longer frozen. > 0 means
	## "frozen until" — tick() skips duration decrement while run_time < this
	## value. Set by SnapshotAmplifyStatusesEffect (Plague Tide). Auto-thaws when
	## run_time exceeds it; no cleanup hook required. 0.0 = never frozen.
	var _frozen_until: float = 0.0

	func get_max_stacks() -> int:
		return _runtime_max_stacks if _runtime_max_stacks > 0 else definition.max_stacks

	func get_tick_interval() -> float:
		return _runtime_tick_interval if _runtime_tick_interval >= 0.0 else definition.tick_interval

	func is_enhanced() -> bool:
		return _applied_duration > 0.0 and time_remaining > _applied_duration

signal status_expired(status_id: String)  ## Local signal for entity to listen to

var _active: Dictionary = {}  ## status_id -> ActiveStatus
## Per-status-id immunity timers (status_id → seconds remaining). Populated by
## ApplyCleanseImmunityEffect via TriggerComponent's special dispatch path
## (Cleric Retribution: cleansed statuses can't be reapplied to the same ally
## for N seconds). Parallels the existing tag-based `has_negation` immunity
## — tag-negation blocks by status tag, this blocks by exact status_id.
var _immune_status_ids: Dictionary = {}
var _modifier_comp: ModifierComponent = null
var _disable_count: int = 0  ## Number of active statuses with disables_actions = true
var _movement_disable_count: int = 0  ## Number of active statuses with disables_movement = true
var _ability_disable_count: int = 0  ## Number of active statuses with disables_abilities = true (Silence)
var _invulnerability_count: int = 0  ## Number of active statuses with grants_invulnerability = true (Empowered Revive post-revive buff)
var _death_prevention_count: int = 0  ## Number of active statuses with prevents_death = true
var _movement_override: String = ""  ## Active movement override (last applied wins, "" = none)
var _taunt_count: int = 0  ## Number of active statuses with grants_taunt = true
var _taunt_radius: float = 0.0  ## Largest active taunt radius (recomputed on change)
var _debuff_absorber_chance: float = 0.0  ## Largest active debuff_absorber_chance (recomputed on change). Queried by other entities' apply_status to roll for redirect — see Cleric Martyr's Resolve.
var combat_manager: Node2D = null  ## Set by combat_manager at spawn time — needed for scene-dependent effects


func setup(modifier_comp: ModifierComponent) -> void:
	_modifier_comp = modifier_comp
	set_process(false)  # Ticked explicitly by combat_manager, not by Godot's auto-callback


func apply_status(status_def: StatusEffectDefinition, source: Node2D,
		stacks: int = 1, duration_override: float = -1.0,
		intercepted: bool = false,
		suppress_triggers: bool = false) -> void:
	## Apply or stack a status effect. duration_override > 0 overrides base_duration.
	## `intercepted` is set true on recursive calls from the debuff-absorber redirect
	## path so a second-order absorber can't intercept the first redirect (recursion
	## guard — first proc wins, no ping-pong between two absorbing entities).
	## `suppress_triggers` skips the on_status_applied EventBus emission so
	## secondary applications (e.g. Chain Control's expire-transfer) don't re-arm
	## on_status_applied listeners and cascade. Modifiers, counters, and status
	## lifecycle still run normally — only the event fan-out is suppressed.
	if not _modifier_comp:
		return

	# Summon-applied statuses are re-sourced to the summoner so persistent DOTs /
	# HoTs survive the summon's death without freeing the source reference.
	# Wizard Kindle: Fire Familiar applies Burn → source is the Wizard, not the
	# familiar. Attribution goes to the real owner, damage scaling is identical
	# (summoner.Int == summon.Int via stat_map), and tick-time source lookups
	# stay valid after the summon expires. Only applies when the summoner is
	# still alive — if the summoner already died, keep source = summon so the
	# tick-time validity check catches it instead.
	if is_instance_valid(source) and source.get("is_summon") and source.is_summon:
		var summoner: Node2D = source.get("summoner")
		if is_instance_valid(summoner) and summoner.is_alive:
			source = summoner

	# Check immunity via Negate modifiers (tag-based)
	for tag in status_def.tags:
		if _modifier_comp.has_negation(tag):
			EventBus.on_status_resisted.emit(source, get_parent(), status_def.status_id)
			_try_apply_resist_stepdown(status_def, source, stacks, duration_override,
					intercepted, suppress_triggers)
			return
	# Polarity-based negation — a "debuff" / "buff" synthetic tag blocks ALL
	# statuses of that polarity regardless of the status's own tags. Mirrors
	# how Martyr's Resolve uses the same synthetic tags for `tick_power`.
	# Catches polarity-negative statuses that don't carry the capitalized
	# "Debuff" tag (e.g. stun, which is tagged ["CC", "Stun"]). First
	# consumer: Cleric Divine Purge's `divine_purge_immunity` (4s full
	# debuff immunity for every ally after a purge).
	var polarity_tag: String = "debuff" if not status_def.is_positive else "buff"
	if _modifier_comp.has_negation(polarity_tag):
		EventBus.on_status_resisted.emit(source, get_parent(), status_def.status_id)
		_try_apply_resist_stepdown(status_def, source, stacks, duration_override,
				intercepted, suppress_triggers)
		return
	# Check per-status-id immunity (Retribution's post-cleanse immunity window)
	if _immune_status_ids.has(status_def.status_id):
		EventBus.on_status_resisted.emit(source, get_parent(), status_def.status_id)
		_try_apply_resist_stepdown(status_def, source, stacks, duration_override,
				intercepted, suppress_triggers)
		return

	# Debuff absorber check — when a non-positive status is about to land, walk
	# the bearer's faction master list for an entity carrying an absorber status
	# (Cleric Martyr's Resolve). First proc redirects the application to the
	# absorber. The recursive apply_status call carries `intercepted = true` so
	# the absorber's own apply path skips this check (terminates ping-pong if
	# multiple absorbers exist in the same party).
	if not intercepted and not status_def.is_positive and combat_manager:
		var bearer: Node2D = get_parent()
		var bearer_faction: int = int(bearer.faction)
		var faction_list: Array = combat_manager.heroes if bearer_faction == 0 else combat_manager.enemies
		for candidate in faction_list:
			if not is_instance_valid(candidate) or not candidate.is_alive:
				continue
			if candidate == bearer:
				continue  # Don't intercept your own debuffs
			var chance: float = candidate.status_effect_component._debuff_absorber_chance
			if chance <= 0.0:
				continue
			if combat_manager.rng.randf() < chance:
				candidate.status_effect_component.apply_status(
						status_def, source, stacks, duration_override, true)
				return

	var duration := duration_override if duration_override > 0.0 else status_def.base_duration

	# Source's duration modifier amplifies/shortens the applied duration.
	# Permanent statuses (duration < 0) are unaffected. Read from the caster so
	# effects like Faithful (Cleric talent: +15% buff/debuff duration) extend
	# every status the caster applies — HoTs, DoTs, shields, party buffs alike.
	# Per-status duration_bonus stacks additively with the global duration bonus
	# (e.g. Pyromancer Persistent Flames: Burn-only +33% duration).
	# Tag-keyed duration_bonus stacks on top — a modifier keyed by any of the
	# applied status's tags contributes. First consumer: Witch Doctor Faithful
	# Rites (+30% "Debuff" AND +30% "CC" duration — CC debuffs get both).
	if duration > 0.0 and is_instance_valid(source) and source.get("modifier_component"):
		var src_mods_dur: ModifierComponent = source.modifier_component
		var duration_bonus: float = src_mods_dur.sum_modifiers("duration", "bonus")
		duration_bonus += src_mods_dur.sum_modifiers(status_def.status_id, "duration_bonus")
		for tag in status_def.tags:
			duration_bonus += src_mods_dur.sum_modifiers(tag, "duration_bonus")
		if duration_bonus != 0.0:
			duration = maxf(0.0, duration * (1.0 + duration_bonus))

	if _active.has(status_def.status_id):
		# Already active — add stacks up to max, refresh duration
		var active: ActiveStatus = _active[status_def.status_id]
		# Enhanced lockout: when an amplifier (Conflagration) has pushed this
		# instance's time_remaining above its natural _applied_duration, new
		# applications skip the stack-add and duration-refresh — the amplified
		# state must erode naturally. Signal still emits (the apply attempt was
		# made; listeners like Persistent Flames should evaluate it). Stacks
		# and modifiers stay unchanged.
		if active.is_enhanced():
			if not suppress_triggers:
				EventBus.on_status_applied.emit(source, get_parent(),
						status_def.status_id, active.stacks)
		else:
			active.stacks = mini(active.stacks + stacks, active.get_max_stacks())
			if duration > 0.0:
				if status_def.duration_refresh_mode == "max":
					active.time_remaining = maxf(active.time_remaining, duration)
				else:
					active.time_remaining = duration
				active._applied_duration = maxf(active._applied_duration, active.time_remaining)
			active.source = source
			_sync_modifiers(active)
			if not suppress_triggers:
				EventBus.on_status_applied.emit(source, get_parent(),
						status_def.status_id, active.stacks)
	else:
		# New status
		var active := ActiveStatus.new()
		active.definition = status_def
		# Capture source-driven runtime overrides ONCE at first apply (locked for the
		# status's lifetime — talent scope doesn't change mid-fight). max_stacks
		# bonus: additive integer; tick_rate bonus: multiplicative (interval / (1+b)).
		# Injected modifiers: snapshotted from source's ModifierComponent registry.
		if is_instance_valid(source) and source.get("modifier_component"):
			var src_mods_apply: ModifierComponent = source.modifier_component
			# max_stacks_bonus and tick_rate_bonus parity with duration_bonus:
			# both sum by status_id AND by each status tag, so a talent can key a
			# stack-cap / tick-rate uplift to a specific status (Accelerant → burn)
			# OR to a tag umbrella (Swollen Stacks → "Debuff") without enumerating
			# every status_id. duration_bonus already walks tags at the top of this
			# function; bringing these two lookups into parity closes the gap and
			# lets tag-keyed source-side uplifts compose.
			var stack_bonus: int = int(src_mods_apply.sum_modifiers(
					status_def.status_id, "max_stacks_bonus"))
			for s_tag in status_def.tags:
				stack_bonus += int(src_mods_apply.sum_modifiers(s_tag, "max_stacks_bonus"))
			if stack_bonus != 0:
				active._runtime_max_stacks = maxi(1, status_def.max_stacks + stack_bonus)
			var tick_rate_bonus: float = src_mods_apply.sum_modifiers(
					status_def.status_id, "tick_rate_bonus")
			for t_tag in status_def.tags:
				tick_rate_bonus += src_mods_apply.sum_modifiers(t_tag, "tick_rate_bonus")
			# Polarity pseudo-tag read parallels _execute_tick_effects' tick_power
			# lookup — "DoTs tick faster" / "HoTs tick faster" become single modifier
			# entries keyed by polarity instead of enumerating every status_id.
			var polarity_tick: String = "buff" if status_def.is_positive else "debuff"
			tick_rate_bonus += src_mods_apply.sum_modifiers(polarity_tick, "tick_rate_bonus")
			if tick_rate_bonus != 0.0 and status_def.tick_interval > 0.0:
				active._runtime_tick_interval = status_def.tick_interval / (1.0 + tick_rate_bonus)
			active._injected_modifiers = _filter_injections_for_bearer(
					src_mods_apply.get_status_modifier_injections(status_def.status_id),
					get_parent())
		# Bearer-side debuff amplification (Witch Doctor Amplifier — Afflictor T3).
		# When a non-positive status is about to land on this bearer and the bearer
		# already carries ally-sourced debuffs from other entities, each unique ally
		# source contributes its amp modifiers keyed by polarity "debuff":
		#   ally_debuff_stack_bonus    — additive int, adds to _runtime_max_stacks
		#   ally_debuff_duration_bonus — additive float, multiplies duration (1+bonus)
		#   ally_debuff_tick_power_bonus — additive float, snapshots onto ActiveStatus
		# Filters: skip same-applier (the amp-owner's own debuffs don't self-amplify),
		# skip faction mismatch (amp works ally→ally for debuff-side symmetry), skip
		# freed sources. visited_sources dedupes so an ally carrying multiple debuffs
		# on this bearer contributes its amp bonuses once per cast, not once per
		# debuff. Sticky: values bake into the ActiveStatus now and persist for its
		# lifetime — the amp-ally's own debuff later falling off does not un-amplify
		# this status.
		if not status_def.is_positive and is_instance_valid(source):
			var amp_stack_bonus: int = 0
			var amp_duration_mult: float = 0.0
			var amp_tick_power_bonus: float = 0.0
			var visited_sources: Dictionary = {}
			for other_id in _active:
				var other: ActiveStatus = _active[other_id]
				if other.definition.is_positive:
					continue
				if not is_instance_valid(other.source) or other.source == source:
					continue
				if int(other.source.faction) != int(source.faction):
					continue
				if visited_sources.has(other.source):
					continue
				visited_sources[other.source] = true
				if not other.source.get("modifier_component"):
					continue
				var amp_mods: ModifierComponent = other.source.modifier_component
				amp_stack_bonus += int(amp_mods.sum_modifiers(
						"debuff", "ally_debuff_stack_bonus"))
				amp_duration_mult += amp_mods.sum_modifiers(
						"debuff", "ally_debuff_duration_bonus")
				amp_tick_power_bonus += amp_mods.sum_modifiers(
						"debuff", "ally_debuff_tick_power_bonus")
			if amp_stack_bonus > 0:
				var base_max: int = active._runtime_max_stacks
				if base_max <= 0:
					base_max = status_def.max_stacks
				active._runtime_max_stacks = maxi(1, base_max + amp_stack_bonus)
			if amp_duration_mult != 0.0 and duration > 0.0:
				duration = maxf(0.0, duration * (1.0 + amp_duration_mult))
			if amp_tick_power_bonus != 0.0:
				active._tick_power_bonus = amp_tick_power_bonus
		active.stacks = mini(stacks, active.get_max_stacks())
		active.time_remaining = duration
		active._applied_duration = duration
		active._applied_tick_interval = active.get_tick_interval()
		active.source = source
		active.tick_timer = active.get_tick_interval()
		# Check for decaying modifiers (computed once at apply time — definition + injected)
		for mod in status_def.modifiers:
			if mod is ModifierDefinition and mod.decay:
				active._has_decay_modifiers = true
				break
		if not active._has_decay_modifiers:
			for mod in active._injected_modifiers:
				if mod is ModifierDefinition and mod.decay:
					active._has_decay_modifiers = true
					break
		_active[status_def.status_id] = active
		_sync_modifiers(active)
		if status_def.disables_actions:
			_disable_count += 1
		if status_def.disables_movement:
			_movement_disable_count += 1
		if status_def.disables_abilities:
			_ability_disable_count += 1
		if status_def.grants_invulnerability:
			_invulnerability_count += 1
		if status_def.prevents_death:
			_death_prevention_count += 1
			get_parent().health._death_prevention_count += 1
		if status_def.movement_override != "":
			_movement_override = status_def.movement_override
		if status_def.grants_taunt:
			_taunt_count += 1
			_taunt_radius = maxf(_taunt_radius, status_def.taunt_radius)
		if status_def.debuff_absorber_chance > 0.0:
			_debuff_absorber_chance = maxf(_debuff_absorber_chance, status_def.debuff_absorber_chance)
		# Register trigger listeners (e.g. SteadyAim's on_hit_dealt → apply Focus)
		_register_trigger_listeners(status_def, source)
		# Execute on_apply_effects (e.g. burst damage/heal on first application)
		var entity: Node2D = get_parent()
		for effect in status_def.on_apply_effects:
			EffectDispatcher.execute_effect(effect, source, entity, null, combat_manager, entity, status_def.status_id)
		if not suppress_triggers:
			EventBus.on_status_applied.emit(source, get_parent(),
					status_def.status_id, active.stacks)


func _try_apply_resist_stepdown(status_def: StatusEffectDefinition, source: Node2D,
		stacks: int, duration_override: float,
		intercepted: bool, suppress_triggers: bool) -> void:
	## Inescapable (Witch Doctor Puppeteer capstone): when a WD-applied CC is
	## fully negated, the source's `stepdown_pierce` modifier (keyed by any of
	## the resisted status's tags — the CC surface is tag-driven; a "CC"+"Stun"
	## tagged status qualifies as long as the source has stepdown_pierce on
	## either) redirects the application to `status_def.resist_stepdown`.
	## The stepdown's own resist_stepdown (when set) chains recursively for
	## multi-axis immunity; terminal stepdowns set resist_stepdown = null so
	## the cascade unwinds when a fully immune target is encountered.
	##
	## Passes `duration_override`, `intercepted`, and `suppress_triggers`
	## through unchanged so callers like ChainControlTransferEffect that pass
	## 50%-duration + suppress_triggers keep their semantics when the transfer
	## target is CC-immune. `source` is re-used as-is — the pierce is a source
	## identity property, not per-application, so the recursive stepdown keeps
	## the same source and re-evaluates the gate on the next type.
	if status_def.resist_stepdown == null:
		return
	if not is_instance_valid(source):
		return
	var src_mods = source.get("modifier_component")
	if src_mods == null:
		return
	var pierce_active: bool = false
	for tag in status_def.tags:
		if src_mods.sum_modifiers(tag, "stepdown_pierce") > 0.0:
			pierce_active = true
			break
	if not pierce_active:
		return
	apply_status(status_def.resist_stepdown, source, stacks, duration_override,
			intercepted, suppress_triggers)


func _filter_injections_for_bearer(injections: Array, bearer: Node2D) -> Array:
	## Filter source-side status_modifier_injections by the injected modifier's
	## `require_target_priority_tier` field. Empty list = unconditional (snapshot
	## as-is — Wizard Scorched, Ranger Deep Mark). Non-empty list = the bearer
	## must match one of the listed tiers at apply time. First consumer: Ranger
	## Marked For Death (priority-gated +25% Physical vulnerability injection
	## into Mark). Delegates tier classification to TargetingRule's static
	## matcher so every primitive that reads priority tiers (targeting, trigger
	## conditions, apply-time filters) stays consistent.
	if injections.is_empty():
		return injections
	var filtered: Array = []
	for mod in injections:
		if mod is ModifierDefinition and not mod.require_target_priority_tier.is_empty():
			if not TargetingRule.entity_matches_any_priority_tier(
					bearer, mod.require_target_priority_tier):
				continue
		filtered.append(mod)
	return filtered


func tick(delta: float) -> void:
	var entity: Node2D = get_parent()
	var expired: Array[String] = []
	# Build frozen status set: union of all active statuses' freezes_status_ids
	var frozen_ids: Dictionary = {}
	for sid in _active:
		var a: ActiveStatus = _active[sid]
		for fid in a.definition.freezes_status_ids:
			frozen_ids[fid] = true
	# Per-instance freeze timer (Plague Tide snapshot freeze) reads combat run_time
	# directly off the ActiveStatus — no shared set needed because the freeze is
	# already baked into each instance.
	var run_time: float = combat_manager.run_time if combat_manager else 0.0
	for status_id in _active:
		var active: ActiveStatus = _active[status_id]

		# Periodic tick effects (interval honors source-driven runtime override)
		var tick_iv: float = active.get_tick_interval()
		if tick_iv > 0.0:
			active.tick_timer -= delta
			if active.tick_timer <= 0.0:
				active.tick_timer += tick_iv
				_execute_tick_effects(active, entity)

		# Decrement duration (negative = permanent, never expires)
		# Skip duration decrement for frozen statuses: status-id freeze (Rampage
		# freezing Frenzy) OR per-instance freeze (Plague Tide window).
		var per_instance_frozen: bool = active._frozen_until > 0.0 and run_time < active._frozen_until
		if active.time_remaining > 0.0 and not frozen_ids.has(status_id) and not per_instance_frozen:
			active.time_remaining -= delta
			if active.time_remaining <= 0.0:
				expired.append(status_id)
			elif active._applied_tick_interval > 0.0 \
					and active._runtime_tick_interval > 0.0 \
					and active.time_remaining <= active._applied_duration \
					and active._runtime_tick_interval < active._applied_tick_interval:
				# Enhanced tick rate eroded: restore to pre-amplification interval
				active._runtime_tick_interval = active._applied_tick_interval
			elif active._has_decay_modifiers:
				# Re-sync decaying modifiers each tick (value scales with time_remaining)
				_sync_modifiers(active)

	for status_id in expired:
		_expire_status(status_id)

	# Decay per-status-id immunity timers (Retribution cleanse-immunity window).
	# Entries are sparse — only populated by ApplyCleanseImmunityEffect — so the
	# empty-check short-circuits the common case.
	if not _immune_status_ids.is_empty():
		var expired_immunities: Array[String] = []
		for sid in _immune_status_ids:
			_immune_status_ids[sid] -= delta
			if _immune_status_ids[sid] <= 0.0:
				expired_immunities.append(sid)
		for sid in expired_immunities:
			_immune_status_ids.erase(sid)


func add_status_id_immunity(status_id: String, duration: float) -> void:
	## Grant per-status-id immunity for `duration` seconds. If the id is already
	## immune, take the max so overlapping windows don't shorten an existing one.
	## Used by ApplyCleanseImmunityEffect via TriggerComponent (Retribution).
	if duration <= 0.0 or status_id == "":
		return
	var current: float = _immune_status_ids.get(status_id, 0.0)
	_immune_status_ids[status_id] = maxf(current, duration)


func is_status_id_immune(status_id: String) -> bool:
	return _immune_status_ids.has(status_id)


func is_disabled() -> bool:
	## Returns true if any active status disables actions (Stun, Freeze, etc.)
	return _disable_count > 0


func is_movement_disabled() -> bool:
	## Returns true if any active status disables movement (Root, etc.)
	return _movement_disable_count > 0


func is_abilities_disabled() -> bool:
	## Returns true if any active status disables abilities (Silence). Does NOT
	## block auto-attacks or movement — BehaviorComponent consults this only at
	## the skill-dispatch step. Stun / Fear (disables_actions) continue to block
	## everything via is_disabled().
	return _ability_disable_count > 0


func is_invulnerability_active() -> bool:
	## Returns true if any active status grants_invulnerability. Damage gate —
	## entity.take_damage early-returns when this passes, matching the existing
	## is_invulnerable flag path (ability-animation-driven). CC still lands.
	## First consumer: Witch Doctor Empowered Revive (5s post-revive buff).
	return _invulnerability_count > 0


func has_status_with_tag(tag: String) -> bool:
	## Returns true if any active status carries `tag` in its tags array. First
	## consumer: Chain Control's "uncontrolled enemy" filter (skip candidates
	## carrying any "CC"-tagged status). Small N (active statuses per entity are
	## typically <10) so linear scan is fine at 300x density.
	for status_id in _active:
		if _active[status_id].definition.tags.has(tag):
			return true
	return false


func get_movement_override() -> String:
	## Returns the active movement override ("flee_right", etc.) or "" if none.
	return _movement_override


func has_taunt() -> bool:
	return _taunt_count > 0


func get_taunt_radius() -> float:
	return _taunt_radius


func get_definition(status_id: String) -> StatusEffectDefinition:
	## Returns the StatusEffectDefinition for an active status, or null if not active.
	if _active.has(status_id):
		return _active[status_id].definition
	return null


func has_status(status_id: String) -> bool:
	return _active.has(status_id)


func has_any_positive_status() -> bool:
	## Returns true if any active status has is_positive = true.
	## Used by trigger conditions that key off buffed target state (e.g. Righteous Wrath).
	for status_id in _active:
		if _active[status_id].definition.is_positive:
			return true
	return false


func has_any_negative_status() -> bool:
	## Returns true if any active status has is_positive = false.
	## Used by trigger conditions that key off debuffed target state (e.g. Cleric
	## Absolution — Healing Words only cleanses if the target has a debuff to remove).
	for status_id in _active:
		if not _active[status_id].definition.is_positive:
			return true
	return false


func get_negative_status_ids() -> Array[String]:
	## Returns a snapshot (new Array) of every active non-positive status_id.
	## Safe to iterate while removing from _active (caller typically calls
	## force_remove_status on each id). First consumer: Divine Purge's
	## PurgeWithRetaliationEffect (per-debuff cleanse + retaliate loop).
	var out: Array[String] = []
	for status_id in _active:
		if not _active[status_id].definition.is_positive:
			out.append(status_id)
	return out


func get_status_applier(status_id: String) -> Node2D:
	## Returns the original applier of an active status (the entity that put it
	## on the bearer), or null if the status isn't active or the applier was freed.
	if _active.has(status_id):
		var src: Node2D = _active[status_id].source
		if is_instance_valid(src):
			return src
	return null


func has_active_hot() -> bool:
	## Returns true if any active status is a HoT (positive + "Heal" tag + tick_interval > 0).
	## Used by calculate_healing's hot_target_bonus amplifier (Cleric Deepening Faith).
	for status_id in _active:
		var def: StatusEffectDefinition = _active[status_id].definition
		if def.is_positive and def.tick_interval > 0.0 and def.tags.has("Heal"):
			return true
	return false


func get_active_echo_sources() -> Array:
	## Returns [[status_id: String, config: EchoSourceConfig], ...] for every active
	## status whose definition.echo_source != null. Iterated by entity._schedule_echo_replays
	## once per cast (status-driven echo sources fire alongside modifier-driven ones).
	var out: Array = []
	for status_id in _active:
		var def: StatusEffectDefinition = _active[status_id].definition
		if def.echo_source != null:
			out.append([status_id, def.echo_source])
	return out


func count_active_hots() -> int:
	## Returns the number of active HoT statuses (positive + "Heal" tag + tick_interval > 0).
	## Used by TriggerConditionTargetHotCount (Deepening Faith 2+ HoT refresh threshold).
	var count: int = 0
	for status_id in _active:
		var def: StatusEffectDefinition = _active[status_id].definition
		if def.is_positive and def.tick_interval > 0.0 and def.tags.has("Heal"):
			count += 1
	return count


func refresh_hots() -> void:
	## Reset time_remaining on all active HoT statuses to their originally-applied
	## duration. Preserves source's duration bonus (Faithful) because _applied_duration
	## was recorded at apply time. Used by RefreshHotsEffect (Deepening Faith).
	## maxf guard: if an amplifier (Conflagration) has pushed time_remaining above
	## _applied_duration, the refresh preserves the enhanced duration.
	for status_id in _active:
		var active: ActiveStatus = _active[status_id]
		var def: StatusEffectDefinition = active.definition
		if def.is_positive and def.tick_interval > 0.0 and def.tags.has("Heal"):
			if active._applied_duration > 0.0:
				active.time_remaining = maxf(active._applied_duration, active.time_remaining)


func refresh_status_duration(status_id: String) -> void:
	## Reset time_remaining on a specific active status to its applied duration.
	## maxf guard: if an amplifier has pushed time_remaining above _applied_duration,
	## the refresh preserves the enhanced duration rather than trampling it.
	if not _active.has(status_id):
		return
	var active: ActiveStatus = _active[status_id]
	if active._applied_duration > 0.0:
		active.time_remaining = maxf(active._applied_duration, active.time_remaining)


func snapshot_amplify_polarity(polarity: String, stack_multiplier: float,
		tick_power_bonus: float, freeze_duration: float, run_time: float) -> int:
	## Walks active statuses matching `polarity` and applies snapshot amplification:
	##   _runtime_max_stacks → max(1, current_max * stack_multiplier)
	##   _tick_power_bonus   += tick_power_bonus
	##   _frozen_until       = max(prev, run_time + freeze_duration)  (when > 0)
	## Returns the count of affected statuses. Permanent statuses (Dark Pact,
	## Soul) are skipped only on the freeze axis — caps and tick power can still
	## bake in but freezing a permanent has no observable effect (no decay to
	## pause), so the run_time stamp is harmlessly written. First consumer:
	## Witch Doctor Plague Tide via SnapshotAmplifyStatusesEffect.
	var affected: int = 0
	for status_id in _active:
		var active: ActiveStatus = _active[status_id]
		var matches: bool = false
		match polarity:
			"debuff":
				matches = not active.definition.is_positive
			"buff":
				matches = active.definition.is_positive
			"any":
				matches = true
			_:
				return 0
		if not matches:
			continue
		if stack_multiplier != 1.0:
			var current_max: int = active.get_max_stacks()
			active._runtime_max_stacks = maxi(1,
					int(round(float(current_max) * stack_multiplier)))
		if tick_power_bonus != 0.0:
			active._tick_power_bonus += tick_power_bonus
		if freeze_duration > 0.0:
			active._frozen_until = maxf(active._frozen_until, run_time + freeze_duration)
		affected += 1
	return affected


func amplify_status(status_id: String, duration_mult: float, tick_rate_mult: float) -> bool:
	## In-place amplification of an active status instance. Multiplies time_remaining
	## by duration_mult and divides _runtime_tick_interval by tick_rate_mult. The
	## resulting "enhanced" state (time_remaining > _applied_duration) triggers the
	## application lockout in apply_status and auto-restores tick rate in tick() when
	## the enhanced portion erodes. No-op on absent or permanent statuses.
	## Returns true if amplification occurred.
	if not _active.has(status_id):
		return false
	var active: ActiveStatus = _active[status_id]
	if active._applied_duration <= 0.0:
		return false
	if duration_mult != 1.0:
		active.time_remaining *= duration_mult
	if tick_rate_mult != 1.0 and active.get_tick_interval() > 0.0:
		var current_iv: float = active.get_tick_interval()
		active._runtime_tick_interval = current_iv / tick_rate_mult
		active.tick_timer = minf(active.tick_timer, active._runtime_tick_interval)
	return true


func get_stacks(status_id: String) -> int:
	if _active.has(status_id):
		return _active[status_id].stacks
	return 0


func get_status_time_remaining(status_id: String) -> float:
	## Returns the remaining duration on an active status, or 0.0 if absent.
	if _active.has(status_id):
		return _active[status_id].time_remaining
	return 0.0


func get_accumulated_bank(status_id: String) -> float:
	## Returns the payload banked during this status's lifetime (see
	## StatusEffectDefinition.bank_damage_*). 0.0 when the status isn't active —
	## dispatchers must call this at a context where the status still exists
	## (on_expire_effects run before _active.erase, so on_expire is valid).
	## First consumer: SpawnBankedShotEffect (Ranger Crown Shot finishing shot).
	if _active.has(status_id):
		return _active[status_id]._accumulated_bank
	return 0.0


func get_runtime_max_stacks(status_id: String) -> int:
	## Returns the runtime max stacks of an active status (honors source-driven
	## overrides like Accelerant's max_stacks_bonus). Returns 0 if not active.
	## Used by trigger conditions that need to compare current stacks against
	## the effective cap, not the raw definition.max_stacks.
	if _active.has(status_id):
		return _active[status_id].get_max_stacks()
	return 0


func expire_statuses_with_tag(tag: String) -> void:
	## Expire all active statuses that have the given tag. Used for shield depletion
	## ("Shield" tag) and any future tag-driven expiry. Reuses _expire_status() so
	## modifier cleanup, disable_count, and EventBus signals all fire correctly.
	var to_expire: Array[String] = []
	for status_id in _active:
		var active: ActiveStatus = _active[status_id]
		if active.definition.tags.has(tag):
			to_expire.append(status_id)
	for status_id in to_expire:
		_expire_status(status_id)


func remove_status(status_id: String) -> void:
	## Remove a status (consumed by another ability). Fires on_status_consumed.
	if not _active.has(status_id):
		return
	var active: ActiveStatus = _active[status_id]
	_unregister_modifiers(active)
	_unregister_trigger_listeners(active.definition)
	if active.definition.disables_actions:
		_disable_count -= 1
	if active.definition.disables_movement:
		_movement_disable_count -= 1
	if active.definition.disables_abilities:
		_ability_disable_count -= 1
	if active.definition.grants_invulnerability:
		_invulnerability_count -= 1
	if active.definition.prevents_death:
		_death_prevention_count -= 1
		get_parent().health._death_prevention_count -= 1
	if active.definition.movement_override != "":
		_recompute_movement_override()
	if active.definition.grants_taunt:
		_taunt_count -= 1
		_recompute_taunt_radius()
	var had_absorber: bool = active.definition.debuff_absorber_chance > 0.0
	var stacks := active.stacks
	_active.erase(status_id)
	if had_absorber:
		_recompute_debuff_absorber_chance()
	EventBus.on_status_consumed.emit(get_parent(), status_id, stacks)


func consume_stacks(status_id: String, count: int) -> int:
	## Consume stacks from a status. Returns number consumed.
	## count = -1 or >= current stacks → removes the status entirely.
	## count < current stacks → reduces stacks and syncs modifiers.
	## Executes on_consume_effects from the StatusEffectDefinition before removal.
	if not _active.has(status_id):
		return 0
	var active: ActiveStatus = _active[status_id]
	var current: int = active.stacks
	var consumed: int = current if count < 0 else mini(count, current)
	var entity: Node2D = get_parent()

	if consumed >= current:
		# Full removal — execute on_consume_effects, then clean up
		for effect in active.definition.on_consume_effects:
			EffectDispatcher.execute_effect(effect, active.source, entity, null, combat_manager, entity, active.definition.status_id)
		_unregister_modifiers(active)
		_unregister_trigger_listeners(active.definition)
		if active.definition.disables_actions:
			_disable_count -= 1
		if active.definition.disables_movement:
			_movement_disable_count -= 1
		if active.definition.disables_abilities:
			_ability_disable_count -= 1
		if active.definition.grants_invulnerability:
			_invulnerability_count -= 1
		if active.definition.prevents_death:
			_death_prevention_count -= 1
			entity.health._death_prevention_count -= 1
		if active.definition.movement_override != "":
			_recompute_movement_override()
		if active.definition.grants_taunt:
			_taunt_count -= 1
			_recompute_taunt_radius()
		var had_absorber: bool = active.definition.debuff_absorber_chance > 0.0
		_active.erase(status_id)
		if had_absorber:
			_recompute_debuff_absorber_chance()
		EventBus.on_status_consumed.emit(entity, status_id, consumed)
	else:
		# Partial — reduce stacks, re-sync modifiers
		active.stacks -= consumed
		_sync_modifiers(active)
		EventBus.on_status_consumed.emit(entity, status_id, consumed)

	return consumed


func force_remove_status(status_id: String, source: Node2D = null) -> void:
	## Remove a specific status by ID. Same cleanup as cleanse but targeted.
	## Emits on_cleanse (forced external removal, not natural expiry or consumption).
	if not _active.has(status_id):
		return
	var entity := get_parent()
	var cleanse_source: Node2D = source if is_instance_valid(source) else entity
	var active: ActiveStatus = _active[status_id]
	# Capture applier + stacks + definition BEFORE removal so on_cleanse
	# listeners can re-read the cleansed state (Purifying Fire targets the
	# applier; Backfire Hex redistributes the definition at 2× stacks). applier
	# may be null/freed if the applier died — listeners must handle invalidity.
	var applier: Node2D = active.source
	var cleansed_stacks: int = active.stacks
	var cleansed_def: StatusEffectDefinition = active.definition
	_unregister_modifiers(active)
	_unregister_trigger_listeners(active.definition)
	if active.definition.disables_actions:
		_disable_count -= 1
	if active.definition.disables_movement:
		_movement_disable_count -= 1
	if active.definition.disables_abilities:
		_ability_disable_count -= 1
	if active.definition.grants_invulnerability:
		_invulnerability_count -= 1
	if active.definition.prevents_death:
		_death_prevention_count -= 1
		entity.health._death_prevention_count -= 1
	if active.definition.movement_override != "":
		_recompute_movement_override()
	if active.definition.grants_taunt:
		_taunt_count -= 1
		_recompute_taunt_radius()
	var had_absorber: bool = active.definition.debuff_absorber_chance > 0.0
	_active.erase(status_id)
	if had_absorber:
		_recompute_debuff_absorber_chance()
	status_expired.emit(status_id)
	EventBus.on_cleanse.emit(cleanse_source, entity, status_id, applier,
			cleansed_stacks, cleansed_def)


func cleanse(count: int, target_type: String, source: Node2D = null) -> void:
	## Remove statuses by polarity. Oldest first (Dictionary insertion order).
	## count = -1 means remove all matching. Does NOT fire on_consume_effects.
	var entity := get_parent()
	var cleanse_source: Node2D = source if is_instance_valid(source) else entity
	var to_remove: Array[String] = []
	for status_id in _active:
		var active: ActiveStatus = _active[status_id]
		var matches := false
		match target_type:
			"negative":
				matches = not active.definition.is_positive
			"positive":
				matches = active.definition.is_positive
			"any":
				matches = true
		if matches:
			to_remove.append(status_id)
			if count > 0 and to_remove.size() >= count:
				break

	var needs_movement_override_recompute := false
	var needs_absorber_recompute := false
	for status_id in to_remove:
		var active: ActiveStatus = _active[status_id]
		# Capture applier + stacks + definition BEFORE removal so cleanse-trigger
		# listeners can re-read the cleansed state (Purifying Fire targets the
		# applier; Backfire Hex redistributes the definition at 2× stacks to
		# nearby enemies). applier may be null/freed.
		var applier: Node2D = active.source
		var cleansed_stacks: int = active.stacks
		var cleansed_def: StatusEffectDefinition = active.definition
		_unregister_modifiers(active)
		_unregister_trigger_listeners(active.definition)
		if active.definition.disables_actions:
			_disable_count -= 1
		if active.definition.disables_movement:
			_movement_disable_count -= 1
		if active.definition.disables_abilities:
			_ability_disable_count -= 1
		if active.definition.grants_invulnerability:
			_invulnerability_count -= 1
		if active.definition.prevents_death:
			_death_prevention_count -= 1
			entity.health._death_prevention_count -= 1
		if active.definition.movement_override != "":
			needs_movement_override_recompute = true
		if active.definition.grants_taunt:
			_taunt_count -= 1
		if active.definition.debuff_absorber_chance > 0.0:
			needs_absorber_recompute = true
		_active.erase(status_id)
		status_expired.emit(status_id)  # Local signal — entity-internal reactions (channeling recovery)
		EventBus.on_cleanse.emit(cleanse_source, entity, status_id, applier,
				cleansed_stacks, cleansed_def)
	if needs_movement_override_recompute:
		_recompute_movement_override()
	if _taunt_count <= 0:
		_recompute_taunt_radius()
	if needs_absorber_recompute:
		_recompute_debuff_absorber_chance()


func on_death_prevented() -> void:
	## Called when HealthComponent prevents death. Finds the first status with
	## prevents_death, fires its on_death_prevented_effects, then removes the status.
	var entity: Node2D = get_parent()
	for status_id in _active:
		var active: ActiveStatus = _active[status_id]
		if not active.definition.prevents_death:
			continue
		# Fire on_death_prevented_effects (immunity, max stacks, cooldown reapply)
		for effect in active.definition.on_death_prevented_effects:
			EffectDispatcher.execute_effect(effect, entity, entity, null, combat_manager, entity, active.definition.status_id)
		# Remove the status (cleanup counters, modifiers, triggers)
		_unregister_modifiers(active)
		_unregister_trigger_listeners(active.definition)
		if active.definition.disables_actions:
			_disable_count -= 1
		if active.definition.disables_movement:
			_movement_disable_count -= 1
		if active.definition.disables_abilities:
			_ability_disable_count -= 1
		if active.definition.grants_invulnerability:
			_invulnerability_count -= 1
		if active.definition.prevents_death:
			_death_prevention_count -= 1
			entity.health._death_prevention_count -= 1
		if active.definition.movement_override != "":
			_recompute_movement_override()
		if active.definition.grants_taunt:
			_taunt_count -= 1
			_recompute_taunt_radius()
		var had_absorber: bool = active.definition.debuff_absorber_chance > 0.0
		_active.erase(status_id)
		if had_absorber:
			_recompute_debuff_absorber_chance()
		status_expired.emit(status_id)
		break  # Only consume one death prevention status per lethal hit


func extend_status_duration(status_id: String, seconds: float) -> bool:
	## Extend an active status's remaining duration. Returns false if status not active
	## or max_extensions already reached. Respects definition.max_extensions cap.
	if not _active.has(status_id):
		return false
	var active: ActiveStatus = _active[status_id]
	if active.definition.max_extensions > 0 and active._extension_count >= active.definition.max_extensions:
		return false
	active.time_remaining += seconds
	active._extension_count += 1
	return true


func set_max_stacks(status_id: String) -> void:
	## Set an active status to its maximum stacks. No-op if status not present.
	if not _active.has(status_id):
		return
	var active: ActiveStatus = _active[status_id]
	active.stacks = active.get_max_stacks()
	if active.time_remaining > 0.0:
		active.time_remaining = active.definition.base_duration  # Refresh duration
	_sync_modifiers(active)


func notify_hit_received(hit_data = null) -> void:
	## Called by entity.take_damage(). Executes on_hit_received_effects for active statuses.
	## hit_data: HitData or null. When provided, damage_filter and shield_on_hit_absorbed are checked.
	## Reflected (thorns) damage skips all processing to prevent infinite recursion.
	## Echo-replayed hits also skip — "no free proc velocity" principle (Ranger Echo
	## Shot spec: echoes cannot deepen Mark; applies uniformly to every reactive
	## self-stacking status, e.g. Witch Doctor sickness self-refresh).
	if hit_data is HitData and hit_data.is_reflected:
		return
	if hit_data is HitData and hit_data.is_echo:
		return
	var entity: Node2D = get_parent()
	var total_thorns: float = 0.0
	var flat_thorns: float = 0.0
	for status_id in _active:
		var active: ActiveStatus = _active[status_id]
		# Accrue shield from absorbed damage (Fortified Guard pattern — applied on expiry)
		if active.definition.shield_on_hit_absorbed_percent > 0.0 and hit_data is HitData:
			var absorbed: float = hit_data.dr_mitigated
			if absorbed > 0.0:
				active._accumulated_shield += absorbed * active.definition.shield_on_hit_absorbed_percent
		# Damage banking (Crown Shot paint pattern — consumed at dispatch by SpawnBankedShotEffect).
		# Post-pipeline amount from the attacker's perspective IS the "drain" the bank represents —
		# banking the hit_data.amount avoids re-running the pipeline on the finishing shot.
		if hit_data is HitData and hit_data.amount > 0.0 \
				and (active.definition.bank_damage_from_source_percent > 0.0
					or active.definition.bank_damage_from_source_allies_percent > 0.0):
			var pass_filter: bool = active.definition.bank_damage_filter.is_empty() \
					or active.definition.bank_damage_filter.has(hit_data.damage_type)
			if pass_filter and is_instance_valid(hit_data.source) \
					and is_instance_valid(active.source):
				if hit_data.source == active.source:
					active._accumulated_bank += hit_data.amount \
							* active.definition.bank_damage_from_source_percent
				elif int(hit_data.source.faction) == int(active.source.faction):
					active._accumulated_bank += hit_data.amount \
							* active.definition.bank_damage_from_source_allies_percent
		# Accumulate thorns percent from all active statuses
		if active.definition.thorns_percent > 0.0:
			total_thorns += active.definition.thorns_percent
		# Accumulate flat thorns (attribute-scaled, e.g. Str × 0.15)
		if active.definition.thorns_flat_scaling_coefficient > 0.0 and _modifier_comp:
			var attr_val: float = _modifier_comp.sum_modifiers(
					active.definition.thorns_flat_scaling_attribute, "add")
			flat_thorns += active.definition.thorns_flat_scaling_coefficient * attr_val
		if active.definition.on_hit_received_effects.is_empty():
			continue
		# Damage type filter: skip if hit doesn't match required types
		if not active.definition.on_hit_received_damage_filter.is_empty() and hit_data is HitData:
			if not active.definition.on_hit_received_damage_filter.has(hit_data.damage_type):
				continue
		for effect in active.definition.on_hit_received_effects:
			EffectDispatcher.execute_effect(effect, active.source, entity, null, combat_manager, entity, active.definition.status_id)
	# Thorns reflection: deal percent + flat thorns back to the attacker
	if (total_thorns > 0.0 or flat_thorns > 0.0) and hit_data is HitData:
		var attacker: Node2D = hit_data.source
		if is_instance_valid(attacker) and attacker.is_alive:
			var reflect_amount: float = hit_data.amount * total_thorns + flat_thorns
			if reflect_amount > 0.0:
				var reflect_hit := HitData.create(reflect_amount, hit_data.damage_type, entity, attacker, null)
				reflect_hit.is_reflected = true
				reflect_hit.attribution_tag = "thorns"
				attacker.take_damage(reflect_hit)
				EventBus.on_reflect.emit(entity, attacker, reflect_hit)


func notify_hit_dealt(target: Node2D, _hit_data) -> void:
	## Called after entity deals a hit. Executes on_hit_dealt_effects for active statuses.
	## Source for damage calc = status source (the caster), not the entity bearing the status.
	## Iterates over a snapshot of _active.keys() so an effect that consumes its own
	## status mid-fire (e.g. Cleric Retribution's ConsumeStacksEffect with consume_from_bearer)
	## doesn't crash the loop. The has() guard skips entries already removed by a prior
	## effect in the same fire pass.
	for status_id in _active.keys():
		if not _active.has(status_id):
			continue
		var active: ActiveStatus = _active[status_id]
		if active.definition.on_hit_dealt_effects.is_empty():
			continue
		_execute_on_hit_dealt_effects(active, target)


func _expire_status(status_id: String) -> void:
	if not _active.has(status_id):
		return
	var active: ActiveStatus = _active[status_id]
	_unregister_modifiers(active)
	_unregister_trigger_listeners(active.definition)
	if active.definition.disables_actions:
		_disable_count -= 1
	if active.definition.disables_movement:
		_movement_disable_count -= 1
	if active.definition.disables_abilities:
		_ability_disable_count -= 1
	if active.definition.grants_invulnerability:
		_invulnerability_count -= 1
	if active.definition.prevents_death:
		_death_prevention_count -= 1
		get_parent().health._death_prevention_count -= 1
	if active.definition.movement_override != "":
		_recompute_movement_override()
	if active.definition.grants_taunt:
		_taunt_count -= 1
		_recompute_taunt_radius()
	var had_absorber: bool = active.definition.debuff_absorber_chance > 0.0
	# Apply accrued shield on expiry (Fortified Guard pattern — capped by max HP %)
	var entity: Node2D = get_parent()
	if active._accumulated_shield > 0.0:
		var shield_amount: float = active._accumulated_shield
		if active.definition.shield_cap_percent_max_hp > 0.0:
			var cap: float = entity.health.max_hp * active.definition.shield_cap_percent_max_hp
			shield_amount = minf(shield_amount, maxf(0.0, cap - entity.health.shield_hp))
		if shield_amount > 0.0:
			var shield_source: Node2D = active.source if is_instance_valid(active.source) else null
			entity.health.add_shield(shield_amount, active.definition.status_id, shield_source)
	# Execute on_expire_effects (e.g. Doom detonation, buff expiry triggers)
	for effect in active.definition.on_expire_effects:
		EffectDispatcher.execute_effect(effect, active.source, entity, null, combat_manager, entity, active.definition.status_id)
	_active.erase(status_id)
	if had_absorber:
		_recompute_debuff_absorber_chance()
	status_expired.emit(status_id)
	EventBus.on_status_expired.emit(get_parent(), status_id)


func _recompute_movement_override() -> void:
	## Recompute the active movement override from remaining statuses (last applied wins).
	_movement_override = ""
	for status_id in _active:
		var active: ActiveStatus = _active[status_id]
		if active.definition.movement_override != "":
			_movement_override = active.definition.movement_override


func _recompute_taunt_radius() -> void:
	## Recompute taunt radius from remaining statuses (largest wins).
	_taunt_radius = 0.0
	for status_id in _active:
		var active: ActiveStatus = _active[status_id]
		if active.definition.grants_taunt:
			_taunt_radius = maxf(_taunt_radius, active.definition.taunt_radius)


func _recompute_debuff_absorber_chance() -> void:
	## Recompute the bearer's max debuff absorber chance from remaining statuses.
	## Same shape as _recompute_taunt_radius — multiple absorber sources don't sum,
	## the largest active chance wins. Falls to 0.0 when no absorber statuses remain.
	_debuff_absorber_chance = 0.0
	for status_id in _active:
		var active: ActiveStatus = _active[status_id]
		if active.definition.debuff_absorber_chance > 0.0:
			_debuff_absorber_chance = maxf(_debuff_absorber_chance, active.definition.debuff_absorber_chance)


func _sync_modifiers(active: ActiveStatus) -> void:
	## Remove old modifiers and re-register scaled by current stacks.
	## Decaying modifiers additionally scale by time_remaining / base_duration.
	## Threshold modifiers (min_stacks > 0) are flat — active only when stacks >= min_stacks.
	## Walks BOTH definition modifiers and source-injected modifiers (talent-driven extras
	## like Wizard Scorched's per-stack Fire vulnerability) — both scale per-stack identically.
	_unregister_modifiers(active)
	var decay_factor: float = 1.0
	if active._has_decay_modifiers and active.definition.base_duration > 0.0:
		decay_factor = clampf(active.time_remaining / active.definition.base_duration, 0.0, 1.0)
	for base_mod in active.definition.modifiers:
		_register_scaled_modifier(active, base_mod, decay_factor)
	for base_mod in active._injected_modifiers:
		_register_scaled_modifier(active, base_mod, decay_factor)


func _register_scaled_modifier(active: ActiveStatus, base_mod: ModifierDefinition,
		decay_factor: float) -> void:
	# Threshold check: skip if stacks below required minimum
	if base_mod.min_stacks > 0 and active.stacks < base_mod.min_stacks:
		return
	var runtime_mod := ModifierDefinition.new()
	runtime_mod.target_tag = base_mod.target_tag
	runtime_mod.operation = base_mod.operation
	var mod_decay: float = decay_factor if base_mod.decay else 1.0
	# Threshold modifiers are flat (value × 1), per-stack modifiers scale (value × stacks)
	var stack_mult: int = 1 if base_mod.min_stacks > 0 else active.stacks
	runtime_mod.value = base_mod.value * stack_mult * mod_decay
	runtime_mod.source_name = active.definition.status_id
	active._runtime_modifiers.append(runtime_mod)
	_modifier_comp.add_modifier(runtime_mod)


func _execute_tick_effects(active: ActiveStatus, entity: Node2D) -> void:
	## Execute tick_effects for a status that just ticked.
	## tick_power scaling: bearer's modifier component carries a per-polarity
	## "tick_power" multiplier that scales the production of bearer-targeted tick
	## effects. "buff" tag for is_positive statuses, "debuff" for non-positive.
	## Applied as `1 + bonus`, floored at 0 — symmetric with damage_taken's shape.
	## Threaded as `power_multiplier` through EffectDispatcher (same parameter the
	## echo system uses) so DealDamage / Heal / ApplyShield / AreaDamage all scale
	## without per-effect knowledge. Aura outputs are NOT scaled — they target
	## other entities, not the bearer; the bearer's incoming-tick multiplier
	## doesn't apply to its outgoing aura. First consumer: Cleric Martyr's Resolve
	## (Exorcist T3 — debuff ticks on the Cleric tick at 50% effectiveness).
	var power: float = 1.0
	if _modifier_comp:
		var tag: String = "buff" if active.definition.is_positive else "debuff"
		var bonus: float = _modifier_comp.sum_modifiers(tag, "tick_power")
		if bonus != 0.0:
			power = maxf(0.0, 1.0 + bonus)
	# Per-stack tick scaling: multiply power by current stacks for DOTs whose tick
	# damage scales with stack count (Burn: each stack adds Int × 0.15/s).
	if active.definition.tick_scales_with_stacks and active.stacks > 1:
		power *= float(active.stacks)
	# Per-instance amplifier bonus: sticky, baked at first apply from ally-side
	# amp modifiers. Applied as (1 + bonus), floored at 0 — same shape as the
	# bearer-wide tick_power above so Amplifier + Martyr's Resolve compose
	# predictably (an amplified debuff tick on the Cleric is 1.25 × 0.5 of base).
	if active._tick_power_bonus != 0.0:
		power *= maxf(0.0, 1.0 + active._tick_power_bonus)
	# Defensive: if the original applier has been freed between apply and tick
	# (summon expiry + dead summoner, or any other mid-status cleanup we haven't
	# anticipated), skip the tick rather than crashing the damage calculator.
	# apply_status already re-sources summon-applied statuses to the summoner —
	# this guard catches remaining edge cases (e.g. summoner died too).
	if not is_instance_valid(active.source):
		return
	for effect in active.definition.tick_effects:
		EffectDispatcher.execute_effect(effect, active.source, entity, null, combat_manager, entity, active.definition.status_id, power)
	# Aura dispatch: apply aura_tick_effects to nearby entities of the target faction
	if active.definition.aura_radius > 0.0 and not active.definition.aura_tick_effects.is_empty():
		_execute_aura_tick(active, entity)
	# Targeting count threshold: apply/let-expire conditional self-buff
	if active.definition.targeting_count_threshold > 0 and active.definition.targeting_count_status:
		_check_targeting_threshold(active, entity)


func _execute_aura_tick(active: ActiveStatus, entity: Node2D) -> void:
	## Dispatch aura_tick_effects to nearby entities of the specified faction.
	if not combat_manager or not combat_manager.get("spatial_grid"):
		return
	var grid: SpatialGrid = combat_manager.spatial_grid
	var aura_faction: int
	match active.definition.aura_target_faction:
		"enemy":
			aura_faction = 1 - int(entity.faction)
		"ally":
			aura_faction = int(entity.faction)
		_:
			return
	var range_sq: float = active.definition.aura_radius * active.definition.aura_radius
	var targets: Array = grid.get_nearby_in_range(entity.position, aura_faction, range_sq)
	for aura_target in targets:
		if not aura_target.is_alive:
			continue
		for effect in active.definition.aura_tick_effects:
			EffectDispatcher.execute_effect(effect, active.source, aura_target, null, combat_manager, entity, active.definition.status_id)


func _check_targeting_threshold(active: ActiveStatus, entity: Node2D) -> void:
	## Count enemies targeting this entity. If >= threshold, apply conditional sub-status.
	## Sub-status has short duration (refreshed each tick); drops naturally when under threshold.
	if not combat_manager or not combat_manager.get("spatial_grid"):
		return
	var grid: SpatialGrid = combat_manager.spatial_grid
	var enemy_faction: int = 1 - int(entity.faction)
	var enemies: Array = grid.get_all(enemy_faction)
	var count: int = 0
	for e in enemies:
		if is_instance_valid(e) and e.is_alive and e.attack_target == entity:
			count += 1
	if count >= active.definition.targeting_count_threshold:
		apply_status(active.definition.targeting_count_status, entity)


func _execute_on_hit_dealt_effects(active: ActiveStatus, target: Node2D) -> void:
	## Execute on_hit_dealt_effects for a status. Source = status caster (not bearer).
	var fallback: Node2D = get_parent()
	for effect in active.definition.on_hit_dealt_effects:
		EffectDispatcher.execute_effect(effect, active.source, target, null, combat_manager, fallback, active.definition.status_id)


func _register_trigger_listeners(status_def: StatusEffectDefinition, source: Node2D) -> void:
	if status_def.trigger_listeners.is_empty():
		return
	var entity: Node2D = get_parent()
	var trigger_comp = entity.get("trigger_component")
	if not trigger_comp:
		return
	for listener in status_def.trigger_listeners:
		trigger_comp.register_listener(status_def.status_id, listener, source)


func _unregister_trigger_listeners(status_def: StatusEffectDefinition) -> void:
	if status_def.trigger_listeners.is_empty():
		return
	var entity: Node2D = get_parent()
	var trigger_comp = entity.get("trigger_component")
	if not trigger_comp:
		return
	trigger_comp.unregister_listeners_for_source(status_def.status_id)


func _unregister_modifiers(active: ActiveStatus) -> void:
	for mod in active._runtime_modifiers:
		_modifier_comp.remove_modifier(mod)
	active._runtime_modifiers.clear()
