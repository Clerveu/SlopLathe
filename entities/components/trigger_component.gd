class_name TriggerComponent
extends Node
## Manages this entity's event listeners (from statuses, items, talents, run buffs).
## Connects to EventBus signals, evaluates trigger conditions against event data,
## and dispatches effects via EffectDispatcher when conditions pass.
##
## Only connects to signals that have active listeners — zero overhead for
## entities without triggers. Signal connections are refcounted per event type.

## Per-listener runtime data
class ActiveListener:
	var definition: TriggerListenerDefinition
	var source_id: String          ## Status/item/talent ID that registered this listener
	var source_entity: Node2D      ## Who applied the status (for effect scaling)

## Active listeners grouped by event type: { event_name → Array[ActiveListener] }
var _listeners: Dictionary = {}

## Refcount of listeners per event type (for connect/disconnect management)
var _event_refcounts: Dictionary = {}

## Back-reference for scene-dependent effect dispatch (projectiles, summons, displacement)
var combat_manager: Node2D = null


func register_listener(source_id: String, listener: TriggerListenerDefinition,
		source_entity: Node2D) -> void:
	## Register a trigger listener. Called by StatusEffectComponent on status apply,
	## and by entity setup for item/talent/run buff listeners.
	var event: String = listener.event
	if not _listeners.has(event):
		_listeners[event] = []
	var active := ActiveListener.new()
	active.definition = listener
	active.source_id = source_id
	active.source_entity = source_entity
	_listeners[event].append(active)

	# Connect to EventBus if this is the first listener for this event type
	var count: int = _event_refcounts.get(event, 0)
	if count == 0:
		_connect_event(event)
	_event_refcounts[event] = count + 1


func unregister_listeners_for_source(source_id: String) -> void:
	## Remove all listeners registered by a specific source (status/item/talent).
	## Called by StatusEffectComponent on status expire/cleanse/consume.
	var events_to_clean: Array[String] = []
	for event in _listeners:
		var list: Array = _listeners[event]
		var i: int = list.size() - 1
		while i >= 0:
			if list[i].source_id == source_id:
				list.remove_at(i)
				_event_refcounts[event] -= 1
			i -= 1
		if list.is_empty():
			events_to_clean.append(event)

	for event in events_to_clean:
		_disconnect_event(event)
		_listeners.erase(event)
		_event_refcounts.erase(event)


func cleanup() -> void:
	## Disconnect all listeners. Called on entity death.
	for event in _event_refcounts:
		_disconnect_event(event)
	_listeners.clear()
	_event_refcounts.clear()


# --- EventBus signal handlers ---
# Each handler extracts relevant entities from the signal parameters,
# then delegates to _evaluate_and_dispatch for condition checking + effect execution.

func _on_hit_dealt(source: Node2D, target: Node2D, hit_data) -> void:
	_evaluate_and_dispatch("on_hit_dealt", source, target, hit_data)


func _on_hit_received(source: Node2D, target: Node2D, hit_data) -> void:
	_evaluate_and_dispatch("on_hit_received", source, target, hit_data)


func _on_kill(killer: Node2D, victim: Node2D) -> void:
	_evaluate_and_dispatch("on_kill", killer, victim, null)


func _on_crit(source: Node2D, target: Node2D, hit_data) -> void:
	_evaluate_and_dispatch("on_crit", source, target, hit_data)


func _on_block(source: Node2D, target: Node2D, hit_data, _mitigated: float) -> void:
	_evaluate_and_dispatch("on_block", source, target, hit_data)


func _on_dodge(source: Node2D, target: Node2D, hit_data) -> void:
	_evaluate_and_dispatch("on_dodge", source, target, hit_data)


func _on_heal(source: Node2D, target: Node2D, amount: float,
		attribution_tag: String = "") -> void:
	# Dict payload carries amount (for HealByAmountEffect) and attribution_tag
	# (for AttributionTag condition, e.g. Spirit Link's recursion filter).
	_evaluate_and_dispatch("on_heal", source, target,
			{"amount": amount, "attribution_tag": attribution_tag})


func _on_death(entity: Node2D) -> void:
	_evaluate_and_dispatch("on_death", entity, entity, null)


func _on_status_applied(source: Node2D, target: Node2D, status_id: String,
		_stacks: int) -> void:
	_evaluate_and_dispatch("on_status_applied", source, target, {"status_id": status_id})


func _on_status_expired(entity: Node2D, status_id: String) -> void:
	_evaluate_and_dispatch("on_status_expired", entity, entity, {"status_id": status_id})


func _on_absorb(entity: Node2D, hit_data, _absorbed: float,
		_drain_sources: Array = []) -> void:
	_evaluate_and_dispatch("on_absorb", entity, entity, hit_data)


func _on_displacement_resisted(resisted_by: Node2D, attempted_by: Node2D) -> void:
	_evaluate_and_dispatch("on_displacement_resisted", resisted_by, attempted_by, null)


func _on_cleanse(source: Node2D, target: Node2D, status_id: String, applier,
		stacks: int, definition) -> void:
	# applier = the entity that originally applied the cleansed status (may be
	# null/freed). stacks + definition snapshotted by StatusEffectComponent before
	# removal so listeners can re-read the cleansed state (Backfire Hex
	# redistributes the definition at 2× stacks to enemies near the cleanse).
	# Threaded through the payload so listeners with target_event_applier can
	# route effects back to the original status source — Cleric Purifying Fire
	# uses this to deal Holy damage to the enemy that cast the cleansed debuff.
	_evaluate_and_dispatch("on_cleanse", source, target,
			{
				"status_id": status_id,
				"applier": applier,
				"stacks": stacks,
				"definition": definition,
			})


# --- Core evaluation + dispatch ---

func _evaluate_and_dispatch(event: String, source: Node2D, target: Node2D,
		hit_data) -> void:
	if not _listeners.has(event):
		return
	var entity: Node2D = get_parent()
	if not entity.is_alive:
		return

	for active_listener in _listeners[event]:
		var def: TriggerListenerDefinition = active_listener.definition
		# Proc-hit recursion guard: hit-shaped events with no ability context
		# are derived hits (DOT ticks, thorns, trigger-produced damage). Skip
		# listener evaluation unless the listener explicitly opts in. Mirrors
		# entity.take_damage's `notify_hit_dealt` gate — without this, an
		# on_hit_dealt listener that itself deals damage would re-fire on its
		# own derived hit and recurse to stack overflow.
		if hit_data is HitData and hit_data.ability == null and not def.allow_proc_hits:
			continue
		if not _check_trigger_conditions(def.conditions, entity, source, target, hit_data):
			continue
		# Proc chance gate: rolled after conditions pass, before trigger_fired
		# emit and effect dispatch. Default 1.0 = always proc (existing listeners
		# unchanged). < 1.0 gates via combat_manager.rng so replays are
		# deterministic. First consumer: Wizard Sympathetic Flames (20%).
		if def.proc_chance < 1.0:
			if not combat_manager or not combat_manager.get("rng"):
				continue
			if combat_manager.rng.randf() >= def.proc_chance:
				continue
		# Emit trigger fired event for combat tracker
		EventBus.on_trigger_fired.emit(entity, active_listener.source_id, event)
		# Determine effect source and target
		var effect_source: Node2D = entity
		var effect_target: Node2D
		if def.target_self:
			effect_target = entity
		elif def.target_event_source:
			effect_target = source if is_instance_valid(source) else entity
		elif def.target_event_applier:
			# Resolve the original status applier from the event payload (on_cleanse).
			# Falls back to the nearest ALIVE enemy of the trigger bearer when the
			# applier is dead/freed — keeps Purifying Fire useful even when the
			# source mob is already gone. Skip if no living enemy exists at all.
			# Walks the spatial grid candidates manually instead of trusting
			# find_nearest's first hit, because the grid may carry an entity that
			# died earlier in the same frame (rebuild happens at frame start).
			var applier = null
			if hit_data is Dictionary and hit_data.has("applier"):
				applier = hit_data["applier"]
			if not (is_instance_valid(applier) and applier is Node2D and applier.is_alive):
				applier = null
				if combat_manager and combat_manager.get("spatial_grid"):
					var grid: SpatialGrid = combat_manager.spatial_grid
					var enemy_faction: int = 1 - int(entity.faction)
					var pool: Array = grid.get_all(enemy_faction)
					var best_dist_sq: float = INF
					for candidate in pool:
						if not is_instance_valid(candidate) or not candidate.is_alive:
							continue
						var d_sq: float = entity.position.distance_squared_to(candidate.position)
						if d_sq < best_dist_sq:
							best_dist_sq = d_sq
							applier = candidate
			if not is_instance_valid(applier) or not applier.is_alive:
				continue
			effect_target = applier
		elif def.target_nearest_debuffed_ally_to_source:
			# Proximity resolver: nearest allied hero (excludes summons) within
			# target_radius of the event SOURCE's position, carrying at least one
			# negative status, and NOT carrying target_excludes_status_id (per-ally
			# ICD marker). Walks the spatial grid in cell rings around the source
			# rather than the bearer — load-bearing because the bearer (e.g. the
			# Cleric) may be far from the summon (e.g. Spirit Guardian) that fired
			# the event. Skips the listener entirely when no eligible candidate
			# exists, so the per-ally ICD never burns on no-op cleanses.
			# First consumer: Cleric Consecrated Spirit.
			if not is_instance_valid(source):
				continue
			if not combat_manager or not combat_manager.get("spatial_grid"):
				continue
			var grid: SpatialGrid = combat_manager.spatial_grid
			var ally_faction: int = int(entity.faction)
			var radius_sq: float = def.target_radius * def.target_radius
			var candidates: Array = grid.get_nearby_in_range(
					source.position, ally_faction, radius_sq)
			var best: Node2D = null
			var best_dist_sq: float = INF
			for cand in candidates:
				if not is_instance_valid(cand) or not cand.is_alive:
					continue
				if cand.is_summon:
					continue  # Heroes only — summons don't get cleansed by other summons
				if not cand.status_effect_component.has_any_negative_status():
					continue
				if def.target_excludes_status_id != "" \
						and cand.status_effect_component.has_status(def.target_excludes_status_id):
					continue
				var d_sq: float = source.position.distance_squared_to(cand.position)
				if d_sq < best_dist_sq:
					best_dist_sq = d_sq
					best = cand
			if best == null:
				continue
			effect_target = best
		elif def.target_random_near_event_target:
			# Random resolver: pick one same-faction-as-event-target entity within
			# target_radius of the event target's position. Optional stack filter
			# (target_fewer_stacks_status_id) requires the candidate to have fewer
			# stacks of that status than the event target — spread-to-weaker
			# semantics. Skips the listener entirely when no eligible candidate
			# exists. Uses combat_manager.rng for deterministic replays.
			# First consumer: Wizard Sympathetic Flames.
			if not is_instance_valid(target):
				continue
			if not combat_manager or not combat_manager.get("spatial_grid") \
					or not combat_manager.get("rng"):
				continue
			var grid: SpatialGrid = combat_manager.spatial_grid
			var cand_faction: int = int(target.faction)
			var radius_sq: float = def.target_radius * def.target_radius
			var candidates: Array = grid.get_nearby_in_range(
					target.position, cand_faction, radius_sq)
			var target_stack_count: int = 0
			if def.target_fewer_stacks_status_id != "":
				target_stack_count = target.status_effect_component.get_stacks(
						def.target_fewer_stacks_status_id)
			var eligible: Array = []
			for cand in candidates:
				if cand == target:
					continue
				if not is_instance_valid(cand) or not cand.is_alive:
					continue
				if def.target_fewer_stacks_status_id != "":
					var cand_stacks: int = cand.status_effect_component.get_stacks(
							def.target_fewer_stacks_status_id)
					if cand_stacks >= target_stack_count:
						continue
				eligible.append(cand)
			if eligible.is_empty():
				continue
			effect_target = eligible[combat_manager.rng.randi_range(0, eligible.size() - 1)]
		elif not def.target_priority_tiers.is_empty():
			# Walk the bearer's enemy pool by priority tier. First tier with any
			# LIVING match wins; pick nearest candidate from the bearer's position.
			# NO nearest-fallback (unlike "priority_tiered_enemy" targeting rule) -
			# listener is skipped entirely when no priority target is on the field.
			# Filters is_alive because the spatial grid rebuilds at frame start and
			# may still contain a just-killed victim (on_kill fires mid-frame,
			# post-death). First consumer: Ranger Waste Not (prime next priority
			# with 5 Mark stacks on-kill; noop when no next priority exists).
			if not combat_manager or not combat_manager.get("spatial_grid"):
				continue
			var pt_grid: SpatialGrid = combat_manager.spatial_grid
			var pt_enemy_faction: int = 1 - int(entity.faction)
			var pt_pool: Array = pt_grid.get_all(pt_enemy_faction)
			var pt_best: Node2D = null
			for tier in def.target_priority_tiers:
				var pt_best_dist_sq: float = INF
				for cand in pt_pool:
					if not is_instance_valid(cand) or not cand.is_alive:
						continue
					if not TargetingRule.entity_matches_priority_tier(cand, tier):
						continue
					var pt_d_sq: float = entity.position.distance_squared_to(cand.position)
					if pt_d_sq < pt_best_dist_sq:
						pt_best_dist_sq = pt_d_sq
						pt_best = cand
				if pt_best != null:
					break
			if pt_best == null:
				continue
			effect_target = pt_best
		elif def.target_summon_id != "":
			# Fan out to all living summons of this id on the bearer (e.g. Spirit
			# Link → every spirit_guardian the Cleric has). Skip the listener
			# entirely if none are alive. Multi-summon natively supported: post-echo
			# Spirit Link fires twice when 2 guardians exist, once per normal.
			var summon_list: Array = entity._active_summons.get(def.target_summon_id, [])
			var living_summons: Array = []
			for s in summon_list:
				if is_instance_valid(s) and s.is_alive:
					living_summons.append(s)
			if living_summons.is_empty():
				continue
			# Dispatch effects once per living summon (matches EffectDispatcher's
			# per-target loop for targeted effects). Skip the default single-target
			# dispatch below via the trailing continue.
			for summon in living_summons:
				for effect in def.effects:
					if effect is HealByAmountEffect:
						_dispatch_heal_by_amount(effect, effect_source, summon, hit_data)
					elif effect is DamageByAmountEffect:
						_dispatch_damage_by_amount(effect, source, summon, hit_data)
					else:
						EffectDispatcher.execute_effect(effect, effect_source, summon,
								null, combat_manager, entity, active_listener.source_id)
			continue
		else:
			effect_target = target if is_instance_valid(target) else entity
		# Item-driven listeners build a contributors entry so any HitData produced
		# downstream attributes the cross-entity item flow back to the wearer.
		# Mechanical `hit.source` stays the acting entity (thorns / leech / kill
		# credit unaffected); contributors is reporting-only.
		var listener_contributors: Array = []
		if active_listener.source_id.begins_with("item_"):
			listener_contributors = [{
				"entity": active_listener.source_entity,
				"source_name": active_listener.source_id,
				"role": "item_trigger",
			}]
		# Dispatch effects via EffectDispatcher (same pipeline as abilities/statuses)
		for effect in def.effects:
			if effect is HealByAmountEffect:
				# Special path: needs the event's amount (from hit_data dict/HitData).
				_dispatch_heal_by_amount(effect, effect_source, effect_target, hit_data)
			elif effect is DamageByAmountEffect:
				# Special path: needs the event's amount. Attacker (original event
				# source) remains the damage source so thorns/last_hit_by chains stay
				# coherent; the trigger bearer is the redirect DESTINATION, not source.
				_dispatch_damage_by_amount(effect, source, effect_target, hit_data)
			elif effect is ApplyCleanseImmunityEffect:
				# Special path: needs the on_cleanse event's status_id from the
				# Dictionary payload. Grants per-status-id immunity to effect_target
				# — first consumer: Cleric Retribution (cleansed debuff can't be
				# reapplied to the same ally for 3s).
				_dispatch_apply_cleanse_immunity(effect, effect_target, hit_data)
			elif effect is RedistributeCleansedStatusEffect:
				# Special path: needs the cleansed definition + stacks from the
				# on_cleanse payload. Redistributes the cleansed status to enemies
				# of the bearer within radius of the cleanse target's position.
				# First consumer: Witch Doctor Backfire Hex.
				_dispatch_redistribute_cleansed_status(effect, entity, target, hit_data)
			else:
				EffectDispatcher.execute_effect(effect, effect_source, effect_target,
						null, combat_manager, entity, active_listener.source_id,
						1.0, null, listener_contributors)


func _check_trigger_conditions(conditions: Array, entity: Node2D,
		source: Node2D, target: Node2D, hit_data) -> bool:
	## Evaluate trigger conditions against event data.
	## These are fundamentally different from ability conditions — they check
	## event parameters, not game state.
	for condition in conditions:
		if condition is TriggerConditionSourceIsSelf:
			var is_self: bool = (source == entity)
			if condition.negate:
				if is_self:
					return false
			else:
				if not is_self:
					return false
		elif condition is TriggerConditionSourceIsSummon:
			# Filter to events triggered by one of the bearer's own summons. The
			# summon is removed from _active_summons immediately on death (see
			# combat_manager._on_entity_died), so a hash check against the array
			# doubles as a liveness check — no separate is_alive guard needed.
			# First consumer: Cleric Consecrated Spirit (spirit_guardian hits).
			if not is_instance_valid(source):
				return false
			var owned: Array = entity._active_summons.get(condition.summon_id, [])
			if not owned.has(source):
				return false
		elif condition is TriggerConditionTargetIsSelf:
			var is_self: bool = (target == entity)
			if condition.negate:
				if is_self:
					return false
			else:
				if not is_self:
					return false
		elif condition is TriggerConditionNotCrit:
			if hit_data is HitData and hit_data.is_crit:
				return false
		elif condition is TriggerConditionHitIsEcho:
			# Fails on non-hit events (no HitData) — listeners attaching this
			# condition must fire on hit-shaped events.
			if not (hit_data is HitData):
				return false
			var is_echo_hit: bool = hit_data.is_echo
			if condition.negate:
				if is_echo_hit:
					return false
			else:
				if not is_echo_hit:
					return false
		elif condition is TriggerConditionEventEntityFaction:
			var check_entity: Node2D
			match condition.entity_role:
				"source":
					check_entity = source
				"target":
					check_entity = target
				_:
					return false
			if not is_instance_valid(check_entity):
				return false
			# Resolve faction relative to the entity bearing the trigger
			var expected_faction: int
			match condition.faction:
				"enemy":
					expected_faction = 1 - int(entity.faction)
				"ally":
					expected_faction = int(entity.faction)
				_:
					return false
			if int(check_entity.faction) != expected_faction:
				return false
		elif condition is TriggerConditionApplierIsSelf:
			# Read applier from payload Dict (on_cleanse carries applier).
			# Non-cleanse events lacking an applier key fail the condition.
			if not (hit_data is Dictionary and hit_data.has("applier")):
				return false
			var applier = hit_data["applier"]
			var applier_is_self: bool = (is_instance_valid(applier) and applier == entity)
			if condition.negate:
				if applier_is_self:
					return false
			else:
				if not applier_is_self:
					return false
		elif condition is TriggerConditionStatusId:
			if not (hit_data is Dictionary and hit_data.has("status_id")):
				return false
			var matches_id: bool = (hit_data["status_id"] == condition.status_id)
			if condition.negate:
				if matches_id:
					return false
			else:
				if not matches_id:
					return false
		elif condition is TriggerConditionHpThreshold:
			var check_entity: Node2D
			match condition.entity_role:
				"self":
					check_entity = entity
				"target":
					check_entity = target
				"source":
					check_entity = source
				_:
					return false
			if not is_instance_valid(check_entity) or not check_entity.get("health"):
				return false
			var hp_pct: float = check_entity.health.current_hp / check_entity.health.max_hp
			match condition.direction:
				"below":
					if hp_pct >= condition.threshold:
						return false
				"above":
					if hp_pct <= condition.threshold:
						return false
				_:
					return false
		elif condition is TriggerConditionAbilityId:
			if hit_data is HitData and hit_data.ability != null:
				if hit_data.ability.ability_id != condition.ability_id:
					return false
			else:
				return false
		elif condition is TriggerConditionAbilityHasTag:
			if not (hit_data is HitData) or hit_data.ability == null:
				return false
			var has_tag: bool = hit_data.ability.tags.has(condition.tag)
			if condition.negate:
				if has_tag:
					return false
			else:
				if not has_tag:
					return false
		elif condition is TriggerConditionTargetHitByTag:
			if not is_instance_valid(target):
				return false
			var tag_time: float = target._last_hit_time_by_tag.get(condition.tag, -1e18)
			var current_time: float = entity.combat_manager.run_time if entity.combat_manager else 0.0
			if (current_time - tag_time) > condition.window:
				return false
		elif condition is TriggerConditionAttributionTag:
			# Resolve attribution from HitData (hit events) or Dictionary payload (on_heal etc.)
			var payload_tag: String = ""
			var has_tag: bool = false
			if hit_data is HitData:
				payload_tag = hit_data.attribution_tag
				has_tag = true
			elif hit_data is Dictionary and hit_data.has("attribution_tag"):
				payload_tag = hit_data["attribution_tag"]
				has_tag = true
			if not has_tag:
				return false
			var matches: bool = (payload_tag == condition.tag)
			if condition.negate:
				if matches:
					return false
			else:
				if not matches:
					return false
		elif condition is TriggerConditionTargetHasPositiveStatus:
			if not is_instance_valid(target):
				return false
			if not target.status_effect_component.has_any_positive_status():
				return false
		elif condition is TriggerConditionTargetHasNegativeStatus:
			if not is_instance_valid(target):
				return false
			if not target.status_effect_component.has_any_negative_status():
				return false
		elif condition is TriggerConditionTargetHotCount:
			if not is_instance_valid(target):
				return false
			if target.status_effect_component.count_active_hots() < condition.min_count:
				return false
		elif condition is TriggerConditionTargetHasStatus:
			if not is_instance_valid(target):
				return false
			var present: bool = target.status_effect_component.has_status(condition.status_id)
			if condition.negate:
				if present:
					return false
			else:
				if not present:
					return false
		elif condition is TriggerConditionTargetStatusAtMaxStacks:
			# Passes when target currently has `status_id` at its runtime max. Compares
			# against runtime max (honors Accelerant / Intense Heat overrides). Fires
			# on first-reach-max too because on_status_applied emits post-cap; the
			# "already at max before" and "just reached max" cases are indistinguishable
			# here and both reward the intended maintenance play.
			if not is_instance_valid(target):
				return false
			var sec: StatusEffectComponent = target.status_effect_component
			var cur: int = sec.get_stacks(condition.status_id)
			if cur <= 0 or cur < sec.get_runtime_max_stacks(condition.status_id):
				return false
		elif condition is TriggerConditionHitExceedsMaxHpPercent:
			if not (hit_data is HitData):
				return false
			if not is_instance_valid(target) or not target.get("health"):
				return false
			var max_hp: float = target.health.max_hp
			if max_hp <= 0.0:
				return false
			if (hit_data.amount / max_hp) <= condition.threshold:
				return false
		elif condition is TriggerConditionTargetMatchesPriorityTier:
			# Passes when the event target matches any of the listed priority
			# tiers. Uses the same matcher as "priority_tiered_enemy" targeting
			# so talent bonus effects stay consistent with the targeting rule
			# that picked the target. Nearest-fallback targets match no tier
			# and fail this check — intended behavior.
			# `negate` inverts: pass when target matches NONE of the listed
			# tiers (e.g. Fusillade's non-elite, non-boss execute filter).
			if not is_instance_valid(target):
				return false
			var matches_tier: bool = TargetingRule.entity_matches_any_priority_tier(
					target, condition.priority_tiers)
			if condition.negate:
				if matches_tier:
					return false
			else:
				if not matches_tier:
					return false
		elif condition is TriggerConditionTargetIsSummon:
			# Passes based on whether the event target's is_summon flag matches
			# `negate`. Filters out summon deaths from ally-death listeners whose
			# effects only make sense on "real" hero targets (Undying Pact's
			# free-revive + ICD: summons can't be revived because they don't
			# persist as corpses).
			if not is_instance_valid(target):
				return false
			var tgt_is_summon: bool = bool(target.get("is_summon"))
			if condition.negate:
				if tgt_is_summon:
					return false
			else:
				if not tgt_is_summon:
					return false
		elif condition is TriggerConditionBearerHasStatus:
			# Passes based on whether the LISTENER'S BEARER (not the event
			# target) has the named status. Mirrors TriggerConditionTargetHasStatus
			# but scoped to the bearer — used for per-bearer internal cooldowns
			# on source-side listeners. First consumer: Ranger Fusillade execute
			# listener gated by bearer lacking `fusillade_execute_icd`.
			var bearer_has: bool = entity.status_effect_component.has_status(condition.status_id)
			if condition.negate:
				if bearer_has:
					return false
			else:
				if not bearer_has:
					return false
		# Future trigger conditions add match arms here
	return true


func _dispatch_heal_by_amount(effect: HealByAmountEffect, source: Node2D,
		target: Node2D, hit_data) -> void:
	## Heal target for a percentage of the event's amount. Event amount is
	## already post-pipeline (healing_bonus, healing_received, crit baked in, or
	## damage post-mitigation), so the flat percentage is exactly `percent` of
	## what landed — no double-dip. Curse inversion still respected. The emitted
	## on_heal carries `effect.attribution_tag` so follow-up listeners can filter
	## recursion.
	##
	## Accepts either Dictionary (on_heal payload) or HitData (hit events) for
	## hit_data — lets the same effect type serve heal-based and damage-based
	## redirections (e.g. Cleric Martyrdom heals the ally for a % of the
	## incoming hit).
	if not is_instance_valid(target) or not target.is_alive:
		return
	var base_amount: float = 0.0
	if hit_data is HitData:
		base_amount = hit_data.amount
	elif hit_data is Dictionary:
		base_amount = float(hit_data.get("amount", 0.0))
	else:
		return
	var heal_amount: float = base_amount * effect.percent
	if heal_amount <= 0.0:
		return
	if target.status_effect_component.has_status("curse"):
		var curse_hit: HitData = DamageCalculator.calculate_curse_damage(
				source, target, heal_amount)
		target.take_damage(curse_hit)
	elif not target.health.is_dead:
		target.health.apply_healing(heal_amount)
		EventBus.on_heal.emit(source, target, heal_amount, effect.attribution_tag)


func _dispatch_apply_cleanse_immunity(effect: ApplyCleanseImmunityEffect,
		target: Node2D, hit_data) -> void:
	## Grant `target` per-status-id immunity to the status_id carried in the
	## on_cleanse payload. Mirrors _dispatch_heal_by_amount's read-from-payload
	## pattern. Skipped cleanly when the event isn't a cleanse-shaped payload
	## or the target is gone — no-op, no listener state change.
	if not is_instance_valid(target) or not target.is_alive:
		return
	if not (hit_data is Dictionary and hit_data.has("status_id")):
		return
	var status_id: String = hit_data["status_id"]
	if status_id == "":
		return
	target.status_effect_component.add_status_id_immunity(status_id, effect.duration)


func _dispatch_redistribute_cleansed_status(effect: RedistributeCleansedStatusEffect,
		bearer: Node2D, cleanse_target: Node2D, hit_data) -> void:
	## Read the cleansed StatusEffectDefinition + stack count from the on_cleanse
	## payload, then re-apply the definition at ceil(stacks × stack_multiplier)
	## to every living enemy-of-bearer within `radius` of the cleanse target's
	## position. Bearer is threaded through as the applier so status_modifier_
	## injections keyed to the bearer's talents (Rotting Touch, Decay, Faithful
	## Rites) snapshot onto the redistributed instances.
	##
	## Early-returns when the payload lacks the required keys, the cleansed
	## definition is null, stacks resolves to zero, or the cleanse target is
	## freed. The cleanse target is included in the redistribution when within
	## radius (distance 0) — matches spec literal ("redistributed across all
	## enemies within 50px of the cleanse event").
	if not is_instance_valid(bearer) or not bearer.is_alive:
		return
	if not (hit_data is Dictionary and hit_data.has("definition") \
			and hit_data.has("stacks")):
		return
	var definition = hit_data["definition"]
	if definition == null or not (definition is StatusEffectDefinition):
		return
	var stacks_val: int = int(hit_data["stacks"])
	if stacks_val <= 0:
		return
	var transfer_stacks: int = int(ceilf(float(stacks_val) * effect.stack_multiplier))
	if transfer_stacks <= 0:
		return
	if not combat_manager or not combat_manager.get("spatial_grid"):
		return
	if not is_instance_valid(cleanse_target):
		return
	var grid: SpatialGrid = combat_manager.spatial_grid
	var enemy_faction: int = 1 - int(bearer.faction)
	var radius_sq: float = effect.radius * effect.radius
	var candidates: Array = grid.get_nearby_in_range(
			cleanse_target.position, enemy_faction, radius_sq)
	for cand in candidates:
		if not is_instance_valid(cand) or not cand.is_alive:
			continue
		cand.status_effect_component.apply_status(definition, bearer, transfer_stacks)


func _dispatch_damage_by_amount(effect: DamageByAmountEffect, event_source: Node2D,
		damage_target: Node2D, hit_data) -> void:
	## Deal raw damage to damage_target for a percentage of the event amount.
	## Parallels _dispatch_heal_by_amount: the amount is already post-pipeline,
	## so applying a flat percent gives exactly <percent>% without double-dip.
	##
	## event_source is the ORIGINAL event source (the attacker that triggered
	## the event), NOT the trigger bearer — so the redirected damage still
	## attributes to the attacker for thorns, last_hit_by, and kill credit.
	## damage_target is the entity receiving the redirected damage (the trigger
	## bearer when target_self=true — e.g. the Cleric for Martyrdom).
	if not is_instance_valid(damage_target) or not damage_target.is_alive:
		return
	var base_amount: float = 0.0
	var damage_type: String = "Physical"
	if hit_data is HitData:
		base_amount = hit_data.amount
		damage_type = hit_data.damage_type
	elif hit_data is Dictionary:
		base_amount = float(hit_data.get("amount", 0.0))
	else:
		return
	var redirect_amount: float = base_amount * effect.percent
	if redirect_amount <= 0.0:
		return
	var hit := HitData.create(redirect_amount, damage_type, event_source, damage_target, null)
	hit.original_damage_type = damage_type
	hit.attribution_tag = effect.attribution_tag
	damage_target.take_damage(hit)


# --- Signal connection management ---

func _connect_event(event: String) -> void:
	match event:
		"on_hit_dealt":
			EventBus.on_hit_dealt.connect(_on_hit_dealt)
		"on_hit_received":
			EventBus.on_hit_received.connect(_on_hit_received)
		"on_kill":
			EventBus.on_kill.connect(_on_kill)
		"on_crit":
			EventBus.on_crit.connect(_on_crit)
		"on_block":
			EventBus.on_block.connect(_on_block)
		"on_dodge":
			EventBus.on_dodge.connect(_on_dodge)
		"on_heal":
			EventBus.on_heal.connect(_on_heal)
		"on_death":
			EventBus.on_death.connect(_on_death)
		"on_status_applied":
			EventBus.on_status_applied.connect(_on_status_applied)
		"on_status_expired":
			EventBus.on_status_expired.connect(_on_status_expired)
		"on_absorb":
			EventBus.on_absorb.connect(_on_absorb)
		"on_displacement_resisted":
			EventBus.on_displacement_resisted.connect(_on_displacement_resisted)
		"on_cleanse":
			EventBus.on_cleanse.connect(_on_cleanse)
		_:
			push_warning("TriggerComponent: unsupported event type '%s'" % event)


func _disconnect_event(event: String) -> void:
	match event:
		"on_hit_dealt":
			if EventBus.on_hit_dealt.is_connected(_on_hit_dealt):
				EventBus.on_hit_dealt.disconnect(_on_hit_dealt)
		"on_hit_received":
			if EventBus.on_hit_received.is_connected(_on_hit_received):
				EventBus.on_hit_received.disconnect(_on_hit_received)
		"on_kill":
			if EventBus.on_kill.is_connected(_on_kill):
				EventBus.on_kill.disconnect(_on_kill)
		"on_crit":
			if EventBus.on_crit.is_connected(_on_crit):
				EventBus.on_crit.disconnect(_on_crit)
		"on_block":
			if EventBus.on_block.is_connected(_on_block):
				EventBus.on_block.disconnect(_on_block)
		"on_dodge":
			if EventBus.on_dodge.is_connected(_on_dodge):
				EventBus.on_dodge.disconnect(_on_dodge)
		"on_heal":
			if EventBus.on_heal.is_connected(_on_heal):
				EventBus.on_heal.disconnect(_on_heal)
		"on_death":
			if EventBus.on_death.is_connected(_on_death):
				EventBus.on_death.disconnect(_on_death)
		"on_status_applied":
			if EventBus.on_status_applied.is_connected(_on_status_applied):
				EventBus.on_status_applied.disconnect(_on_status_applied)
		"on_status_expired":
			if EventBus.on_status_expired.is_connected(_on_status_expired):
				EventBus.on_status_expired.disconnect(_on_status_expired)
		"on_absorb":
			if EventBus.on_absorb.is_connected(_on_absorb):
				EventBus.on_absorb.disconnect(_on_absorb)
		"on_displacement_resisted":
			if EventBus.on_displacement_resisted.is_connected(_on_displacement_resisted):
				EventBus.on_displacement_resisted.disconnect(_on_displacement_resisted)
		"on_cleanse":
			if EventBus.on_cleanse.is_connected(_on_cleanse):
				EventBus.on_cleanse.disconnect(_on_cleanse)
