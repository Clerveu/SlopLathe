class_name EffectDispatcher
extends RefCounted
## Stateless utility. Dispatches typed effect sub-resources (DealDamageEffect,
## HealEffect, ApplyStatusEffectData, etc.) to the appropriate system.
##
## Same pattern as DamageCalculator: static methods, no instance state.
## All effect dispatch sites (entity abilities, status ticks, status procs,
## projectile impacts) delegate here instead of maintaining their own type-switch.
##
## Source validity rules are intrinsic to effect types, not call sites:
##   - Scaling effects (DealDamageEffect, HealEffect, ApplyShieldEffect) need a
##     living source for attribute lookups → skip if source dead.
##   - Non-scaling effects (ApplyStatusEffectData, CleanseEffect) use fallback_source
##     when source is dead → never skip.
##   - Scene-dependent effects (SpawnProjectilesEffect, SummonEffect) need combat_manager
##     → skip if not provided.


static func execute_effect(effect: Resource, source: Node2D, target: Node2D,
		ability: AbilityDefinition, combat_manager: Node2D,
		fallback_source: Node2D = null, attribution_tag: String = "",
		power_multiplier: float = 1.0,
		echo_source: EchoSourceConfig = null,
		contributors: Array = []) -> void:
	## Dispatch a single effect to a single target.
	##
	## source:          Who created the effect (caster, status applier, projectile firer).
	## target:          Who receives the effect.
	## ability:         The AbilityDefinition context (null for status tick/proc damage).
	## combat_manager:       Back-reference for projectile_manager/spawn_summon/displacement_system (null if unavailable).
	## fallback_source: Used for non-scaling effects when source is dead (e.g. entity itself).

	var source_alive: bool = is_instance_valid(source) and source.is_alive
	var target_alive: bool = is_instance_valid(target) and target.is_alive

	var cm_rng: RandomNumberGenerator = combat_manager.rng if combat_manager and combat_manager.get("rng") else null

	if effect is DealDamageEffect:
		if not source_alive or not target_alive:
			return
		var hit := DamageCalculator.calculate_damage(source, target, ability, effect, cm_rng, power_multiplier, echo_source, contributors)
		if hit.is_dodged:
			return
		hit.attribution_tag = attribution_tag
		target.take_damage(hit)
		# Accumulate damage for overflow heal tracking
		if hit.amount > 0.0 and source.get("_overflow_damage_accumulator") != null:
			source._overflow_damage_accumulator += hit.amount
		# Leech: heal source for a percentage of damage dealt
		# Re-check source alive — take_damage above may have killed source via thorns
		if not source.health.is_dead and hit.amount > 0.0:
			var leech: float = source.modifier_component.sum_modifiers("leech", "bonus")
			if leech > 0.0:
				var heal_amount: float = hit.amount * leech
				if source.status_effect_component.has_status("curse"):
					var curse_hit := DamageCalculator.calculate_curse_damage(
							source, source, heal_amount)
					source.take_damage(curse_hit)
				else:
					source.health.apply_healing(heal_amount)
					EventBus.on_heal.emit(source, source, heal_amount, "leech")

	elif effect is HealEffect:
		if not source_alive or not target_alive:
			return
		var heal_amount := DamageCalculator.calculate_healing(source, target, effect, cm_rng, power_multiplier)
		if heal_amount > 0.0:
			# Curse inversion: healing becomes typed damage
			if target.status_effect_component.has_status("curse"):
				var curse_hit := DamageCalculator.calculate_curse_damage(source, target, heal_amount)
				target.take_damage(curse_hit)
			elif not target.health.is_dead:
				target.health.apply_healing(heal_amount)
				EventBus.on_heal.emit(source, target, heal_amount, attribution_tag)

	elif effect is ApplyStatusEffectData:
		var actual_target: Node2D = source if effect.apply_to_self else target
		var actual_alive: bool = (is_instance_valid(actual_target) and actual_target.is_alive)
		if not actual_alive:
			return
		var src: Node2D = source if source_alive else fallback_source
		actual_target.status_effect_component.apply_status(
				effect.status, src, effect.stacks, effect.duration)

	elif effect is ApplyShieldEffect:
		if not source_alive or not target_alive:
			return
		var attr_val: float = source.modifier_component.sum_modifiers(
				effect.scaling_attribute, "add")
		var shield_amount: float = effect.base_shield * (
				1.0 + attr_val * effect.scaling_coefficient)
		shield_amount = shield_amount * power_multiplier
		if shield_amount > 0.0:
			# Use ability name if available, otherwise fall back to a generic label
			var shield_source_name: String = ability.ability_name if ability else "status_effect"
			target.health.add_shield(shield_amount, shield_source_name, source)

	elif effect is CleanseEffect:
		if not target_alive:
			return
		var src: Node2D = source if source_alive else fallback_source
		if effect.target_status_id != "":
			target.status_effect_component.force_remove_status(effect.target_status_id, src)
		else:
			target.status_effect_component.cleanse(effect.count, effect.target_type, src)

	elif effect is SpawnProjectilesEffect:
		if not combat_manager or not combat_manager.get("projectile_manager"):
			return
		# Projectiles don't need a pre-validated target — they find targets via collision.
		# Pass empty array; callers with resolved targets pass them via execute_effects().
		# echo_source threads through so the projectile's on-hit DealDamage suppresses
		# crit and stamps HitData.is_echo per the echo config.
		combat_manager.projectile_manager.spawn_projectiles(source, ability, effect, [], echo_source)

	elif effect is SummonEffect:
		if not combat_manager or not combat_manager.has_method("spawn_summon"):
			return
		combat_manager.spawn_summon(source, ability, effect)

	elif effect is ConsumeStacksEffect:
		# Default route: consume from `target` (Killshot consuming Mark on the enemy).
		# `consume_from_bearer` route: consume from `fallback_source` instead — used
		# by self-consuming statuses whose lifecycle hooks dispatch from a context
		# where the bearer is in fallback_source rather than target (e.g.
		# `_execute_on_hit_dealt_effects` passes the hit enemy as target and the
		# bearer as fallback). First bearer-route consumer: Cleric Retribution.
		var consume_target: Node2D = fallback_source if effect.consume_from_bearer else target
		if not is_instance_valid(consume_target) or not consume_target.is_alive:
			return
		var sec: StatusEffectComponent = consume_target.status_effect_component
		var consumed: int = sec.consume_stacks(effect.status_id, effect.stacks_to_consume)
		# Execute per-stack effects (source = ability caster for scaling)
		if consumed > 0 and not effect.per_stack_effects.is_empty():
			for _i in consumed:
				for sub_effect in effect.per_stack_effects:
					execute_effect(sub_effect, source, consume_target, ability, combat_manager, source, attribution_tag, power_multiplier, echo_source, contributors)

	elif effect is ResurrectEffect:
		if not combat_manager or not combat_manager.has_method("revive_entity"):
			return
		var corpse: Node2D = null
		if effect.target_dying_entity:
			# on_death listener path: the dying entity is the dispatch target and
			# hasn't been appended to corpses yet. Filter to persist_as_corpse so
			# summons (which the engine frees immediately without corpse persistence)
			# can't be pulled back through this route.
			if is_instance_valid(target) and not target.is_alive \
					and target.get("persist_as_corpse"):
				corpse = target
		else:
			corpse = combat_manager.get_nearest_corpse(source.position, source.faction)
		if corpse:
			combat_manager.revive_entity(corpse, effect.hp_percent, source)
			if effect.post_revive_status != null and corpse.is_alive:
				corpse.status_effect_component.apply_status(
						effect.post_revive_status, source, 1)

	elif effect is ApplyModifierEffectData:
		if not target_alive:
			return
		target.modifier_component.add_modifier(effect.modifier)

	elif effect is AreaDamageEffect:
		if not source_alive:
			return
		if not is_instance_valid(target):
			return
		if not combat_manager or not combat_manager.get("spatial_grid"):
			return
		var grid: SpatialGrid = combat_manager.spatial_grid
		var enemy_faction: int = 1 - int(source.faction)
		var radius_sq: float = effect.aoe_radius * effect.aoe_radius
		var aoe_targets: Array = grid.get_nearby_in_range(target.position, enemy_faction, radius_sq)
		# Build a DealDamageEffect once for the pipeline (avoids per-target allocation)
		var dmg_effect := DealDamageEffect.new()
		dmg_effect.damage_type = effect.damage_type
		dmg_effect.scaling_attribute = effect.scaling_attribute
		dmg_effect.scaling_coefficient = effect.scaling_coefficient
		dmg_effect.base_damage = effect.base_damage
		for aoe_target in aoe_targets:
			if aoe_target == target:
				continue  # Skip center entity (may be dead — the kill victim)
			if not aoe_target.is_alive:
				continue
			var hit: HitData = DamageCalculator.calculate_damage(
					source, aoe_target, ability, dmg_effect, cm_rng, power_multiplier, echo_source, contributors)
			if hit.is_dodged:
				continue
			hit.attribution_tag = attribution_tag
			aoe_target.take_damage(hit)

	elif effect is DeathAreaDamageEffect:
		# Source may be dead — only needs position and faction (both valid pre-queue_free)
		if not is_instance_valid(source):
			return
		if not combat_manager or not combat_manager.get("spatial_grid"):
			return
		var grid_d: SpatialGrid = combat_manager.spatial_grid
		var enemy_faction_d: int = 1 - int(source.faction)
		var radius_sq_d: float = effect.aoe_radius * effect.aoe_radius
		var aoe_targets_d: Array = grid_d.get_nearby_in_range(source.position, enemy_faction_d, radius_sq_d)
		for aoe_target_d in aoe_targets_d:
			if not is_instance_valid(aoe_target_d) or not aoe_target_d.is_alive:
				continue
			var hit_d: HitData = HitData.create(effect.flat_damage, effect.damage_type, source, aoe_target_d, null)
			hit_d.attribution_tag = attribution_tag
			aoe_target_d.take_damage(hit_d)

	elif effect is SetMaxStacksEffect:
		if not target_alive:
			return
		if effect.required_talent_id != "" and not target.talent_picks.has(effect.required_talent_id):
			return
		if target.status_effect_component.has_status(effect.status_id):
			target.status_effect_component.set_max_stacks(effect.status_id)
		elif effect.status:
			target.status_effect_component.apply_status(
					effect.status, target, effect.status.max_stacks)

	elif effect is GroundZoneEffect:
		if not combat_manager:
			return
		# Spawn zone at target position (impact site) — use target even if dead (position still valid)
		var zone_pos: Vector2
		if effect.center_on_source and is_instance_valid(source):
			zone_pos = source.position
		elif is_instance_valid(target):
			zone_pos = target.position
		elif is_instance_valid(source):
			zone_pos = source.position
		else:
			return
		combat_manager.spawn_ground_zone(effect, source, zone_pos)

	elif effect is RefundCooldownEffect:
		## Source-side operation — cooldowns belong to the caster. Passed-in
		## target is irrelevant. No-ops when source is gone, has no
		## AbilityComponent, or doesn't own the named ability. First consumer:
		## Ranger Waste Not (trigger dispatch passes the bearer as source).
		if not is_instance_valid(source):
			return
		var ac = source.get("ability_component")
		if ac == null:
			return
		ac.refund_cooldown(effect.ability_id, effect.seconds)

	elif effect is ExtendActiveCooldownsEffect:
		## Target-side operation — extend every currently-ticking cooldown on
		## target's AbilityComponent by the configured multiplier. Dispatched
		## from a CC-status on_apply_effect, so `target` is the bearer whose
		## cooldowns should be dragged. No-ops when target is invalid / dead
		## or lacks an AbilityComponent. First consumer: Witch Doctor
		## Inescapable's Cooldown Drag (Silence stepdown +50% cooldowns).
		if not target_alive:
			return
		var ac_ext = target.get("ability_component")
		if ac_ext == null:
			return
		ac_ext.extend_all_cooldowns(effect.multiplier)

	elif effect is GrantAbilityChargeEffect:
		## Source-side operation — charges bank on the caster's ability
		## component. Passed-in target is irrelevant. Same shape as
		## RefundCooldownEffect: no-ops when source is gone, has no
		## AbilityComponent, or doesn't own the named ability. First consumer:
		## Ranger Marked For Death (on ally-kill of a marked priority target,
		## bank 1 Crippling Shot charge, max 2).
		if not is_instance_valid(source):
			return
		var ac = source.get("ability_component")
		if ac == null:
			return
		ac.grant_ability_charge(effect.ability_id, effect.max_charges)

	elif effect is ExecuteEffect:
		## Instant-kill dispatch: deal raw damage equal to target's remaining
		## pool (current_hp + shield_hp) so shields are drained and the target
		## dies in one hit. Bypasses DamageCalculator entirely — no DR, no
		## crit, no conversion. ability=null on the HitData so AA-keyed
		## on_hit_dealt listeners (Pin, Heavy Draw bonus Mark, Deathroll's
		## consume gate) don't re-fire on the execute itself, but on_hit_dealt
		## / on_hit_received / on_death / on_kill still emit normally so kill
		## attribution, Combat Tracker credit, and on-kill triggers (Deathroll,
		## Waste Not) work as expected. First consumer: Ranger Fusillade.
		if not source_alive or not target_alive:
			return
		var raw: float = target.health.current_hp + target.health.shield_hp
		if raw <= 0.0:
			return
		var hit := HitData.create(raw, effect.damage_type, source, target, null)
		hit.attribution_tag = effect.attribution_tag
		target.take_damage(hit)

	elif effect is ExtendStatusDurationEffect:
		if not target_alive:
			return
		target.status_effect_component.extend_status_duration(effect.status_id, effect.seconds)

	elif effect is RefreshHotsEffect:
		if not target_alive:
			return
		target.status_effect_component.refresh_hots()

	elif effect is AmplifyActiveStatusEffect:
		# Self-resolving pool (same shape as SpreadStatusEffect / FactionCleanseEffect):
		# scan the full faction pool and amplify each entity's matching status in place.
		# Source liveness is checked so a dead caster can't amplify post-mortem.
		if not source_alive:
			return
		if not combat_manager or not combat_manager.get("spatial_grid"):
			return
		var grid_a: SpatialGrid = combat_manager.spatial_grid
		var scan_faction_a: int
		match effect.target_faction:
			"enemy":
				scan_faction_a = 1 - int(source.faction)
			"ally":
				scan_faction_a = int(source.faction)
			_:
				return
		var pool_a: Array = grid_a.get_all(scan_faction_a)
		for entity_a in pool_a:
			if not is_instance_valid(entity_a) or not entity_a.is_alive:
				continue
			entity_a.status_effect_component.amplify_status(
					effect.status_id, effect.duration_multiplier, effect.tick_rate_multiplier)

	elif effect is SnapshotAmplifyStatusesEffect:
		# Self-resolving pool sweep: walks every entity of `target_faction`
		# (relative to source) and snapshot-amplifies every active status matching
		# `polarity` on each. Per-instance, snapshot-only — debuffs applied AFTER
		# this dispatch are untouched. Source liveness gates the sweep so a dead
		# caster can't snapshot post-mortem (Plague Tide's window status apply
		# would also fail in that case). First consumer: Witch Doctor Plague Tide
		# (Afflictor capstone — debuffs on every enemy: caps doubled, +100% tick
		# potency, durations frozen for 10s).
		if not source_alive:
			return
		if not combat_manager or not combat_manager.get("spatial_grid"):
			return
		var grid_s: SpatialGrid = combat_manager.spatial_grid
		var scan_faction_s: int
		match effect.target_faction:
			"enemy":
				scan_faction_s = 1 - int(source.faction)
			"ally":
				scan_faction_s = int(source.faction)
			_:
				return
		var run_time_s: float = combat_manager.run_time
		var pool_s: Array = grid_s.get_all(scan_faction_s)
		for entity_s in pool_s:
			if not is_instance_valid(entity_s) or not entity_s.is_alive:
				continue
			entity_s.status_effect_component.snapshot_amplify_polarity(
					effect.polarity, effect.stack_multiplier,
					effect.tick_power_bonus, effect.freeze_duration, run_time_s)

	elif effect is RefreshStatusInRadiusEffect:
		# Self-resolving pool (same shape as SpreadStatusEffect / FactionCleanseEffect):
		# scan the grid for entities of `target_faction` (relative to source) within
		# `radius` of the passed-in `target` and refresh their `status_id` duration.
		# Untouched: stacks, modifiers, trigger listeners. Source liveness is checked
		# so a dead Wizard can't keep refreshing Burn mid-debuff. First consumer:
		# Wizard Persistent Flames — target is the Burn-afflicted enemy the Wizard
		# just hit, radius 30px pulls its neighbors from the same faction.
		if not source_alive or not target_alive:
			return
		if not combat_manager or not combat_manager.get("spatial_grid"):
			return
		var grid_r: SpatialGrid = combat_manager.spatial_grid
		var scan_faction_r: int
		match effect.target_faction:
			"enemy":
				scan_faction_r = 1 - int(source.faction)
			"ally":
				scan_faction_r = int(source.faction)
			_:
				return
		var radius_sq_r: float = effect.radius * effect.radius
		var pool_r: Array = grid_r.get_nearby_in_range(target.position, scan_faction_r, radius_sq_r)
		for entity_r in pool_r:
			if not is_instance_valid(entity_r) or not entity_r.is_alive:
				continue
			entity_r.status_effect_component.refresh_status_duration(effect.status_id)

	elif effect is DisplacementEffect:
		if not combat_manager or not combat_manager.get("displacement_system"):
			return
		combat_manager.displacement_system.execute(source, ability, effect, [target] if target else [])

	elif effect is PurgeWithRetaliationEffect:
		# Composite: per cleansed non-positive status on target, force_remove
		# (firing on_cleanse → Purifying Fire / Hallowed Ground / Retribution
		# via their own listeners), then deal typed damage from source to the
		# original applier (nearest-enemy fallback when applier is dead/freed).
		# First consumer: Cleric Divine Purge (Int × 0.4 Holy per cleansed
		# debuff, stacks on top of Purifying Fire's own per-cleanse damage).
		if not target_alive:
			return
		var src: Node2D = source if source_alive else fallback_source
		if not is_instance_valid(src) or not src.is_alive:
			return
		var sec: StatusEffectComponent = target.status_effect_component
		var ids: Array[String] = sec.get_negative_status_ids()
		if ids.is_empty():
			return
		var purge_dmg := DealDamageEffect.new()
		purge_dmg.damage_type = effect.damage_type
		purge_dmg.scaling_attribute = effect.scaling_attribute
		purge_dmg.scaling_coefficient = effect.scaling_coefficient
		purge_dmg.base_damage = effect.base_damage
		var enemy_faction_for_src: int = 1 - int(src.faction)
		for sid in ids:
			var applier: Node2D = sec.get_status_applier(sid)
			sec.force_remove_status(sid, src)
			var dmg_target: Node2D = null
			if is_instance_valid(applier) and applier.is_alive \
					and int(applier.faction) == enemy_faction_for_src:
				dmg_target = applier
			elif combat_manager and combat_manager.get("spatial_grid"):
				var grid: SpatialGrid = combat_manager.spatial_grid
				var pool: Array = grid.get_all(enemy_faction_for_src)
				var best_d: float = INF
				for e in pool:
					if not is_instance_valid(e) or not e.is_alive:
						continue
					var d: float = src.position.distance_squared_to(e.position)
					if d < best_d:
						best_d = d
						dmg_target = e
			if dmg_target:
				execute_effect(purge_dmg, src, dmg_target, ability, combat_manager,
						src, attribution_tag, power_multiplier, echo_source, contributors)

	elif effect is SpreadStatusEffect:
		# Self-propagating stacking status: scan a faction pool for bearers of
		# the designated status with enough stacks, and for each qualifying
		# bearer apply the same status to its same-faction neighbors within
		# spread_radius. Same "targetless / self-resolving pool" shape as
		# FactionCleanseEffect — the per-target iteration from execute_effects
		# is bypassed via execute_effects' match arm below.
		#
		# Source remains the effect dispatcher (passive-status bearer, e.g. the
		# Wizard) so DOT scaling continues to key off the original caster. The
		# grid may contain entities that died earlier in the same frame
		# (rebuild at frame start), so liveness is re-checked per candidate.
		#
		# First consumer: Wizard Spreading Flames (Pyromancer T1).
		if not source_alive:
			return
		if not combat_manager or not combat_manager.get("spatial_grid"):
			return
		if effect.status == null:
			return
		var grid: SpatialGrid = combat_manager.spatial_grid
		var scan_faction: int
		match effect.bearer_faction:
			"enemy":
				scan_faction = 1 - int(source.faction)
			"ally":
				scan_faction = int(source.faction)
			_:
				return
		var spread_pool: Array = grid.get_all(scan_faction)
		var spread_radius_sq: float = effect.spread_radius * effect.spread_radius
		var spread_status_id: String = effect.status.status_id
		for bearer in spread_pool:
			if not is_instance_valid(bearer) or not bearer.is_alive:
				continue
			var bearer_stacks: int = bearer.status_effect_component.get_stacks(spread_status_id)
			if bearer_stacks < effect.min_bearer_stacks:
				continue
			var neighbors: Array = grid.get_nearby_in_range(
					bearer.position, scan_faction, spread_radius_sq)
			for neighbor in neighbors:
				if neighbor == bearer:
					continue
				if not is_instance_valid(neighbor) or not neighbor.is_alive:
					continue
				if effect.require_neighbor_below_bearer:
					var n_stacks: int = neighbor.status_effect_component.get_stacks(spread_status_id)
					if n_stacks >= bearer_stacks:
						continue
				neighbor.status_effect_component.apply_status(
						effect.status, source, effect.spread_stacks)

	elif effect is TransferStatusToNeighborsEffect:
		# Death-triggered propagation: read `effect.status` stacks from target,
		# then apply the same status at int(target_stacks × stack_factor) to the
		# N nearest same-faction entities around target (excluding target). The
		# trigger bearer (source) is threaded through as the applier so the
		# talent's status_modifier_injections (Rotting Touch, Decay) snapshot
		# onto the transferred instance.
		#
		# Target-aware (not target-iterating): dispatched once with target = the
		# dying entity; walks target.faction's grid pool once for the neighbor
		# search. The target may already be `is_alive = false` by dispatch time
		# (on_death fires before queue_free, so StatusEffectComponent and
		# position are still intact); don't gate on target_alive.
		#
		# First consumer: Witch Doctor Infectious (Afflictor T1).
		if not is_instance_valid(target):
			return
		if effect.status == null:
			return
		if not combat_manager or not combat_manager.get("spatial_grid"):
			return
		var src_tsn: Node2D = source if source_alive else fallback_source
		if not is_instance_valid(src_tsn):
			return
		var bearer_stacks: int = target.status_effect_component.get_stacks(
				effect.status.status_id)
		var transfer_stacks: int = int(float(bearer_stacks) * effect.stack_factor)
		if transfer_stacks <= 0:
			return
		var grid_tsn: SpatialGrid = combat_manager.spatial_grid
		var pool_tsn: Array = grid_tsn.get_all(int(target.faction))
		# Walk the faction pool manually to filter the just-died target and any
		# same-frame dead entries the grid still references (rebuild at frame
		# start). Small N (faction-scoped), one sort per death event.
		var ranked: Array = []
		for cand in pool_tsn:
			if cand == target:
				continue
			if not is_instance_valid(cand) or not cand.is_alive:
				continue
			ranked.append(cand)
		if ranked.is_empty():
			return
		var origin_tsn: Vector2 = target.position
		ranked.sort_custom(func(a, b):
			return origin_tsn.distance_squared_to(a.position) \
					< origin_tsn.distance_squared_to(b.position))
		var apply_count: int = mini(effect.neighbor_count, ranked.size())
		for i in apply_count:
			ranked[i].status_effect_component.apply_status(
					effect.status, src_tsn, transfer_stacks)

	elif effect is ChainControlTransferEffect:
		# Puppeteer Chain Control: on CC expiry, transfer the CC to the nearest
		# uncontrolled same-faction neighbor within radius at 50% base_duration.
		# Dispatched from a tracker's on_expire_effects — target = bearer (the
		# enemy whose CC is expiring), source = WD (tracker's active.source).
		#
		# "Uncontrolled" = no CC-tagged active status on the candidate (filters
		# enemies currently rooted / stunned / feared / silenced / carrying any
		# CC-tagged tracker). Bearer is explicitly excluded — spec prohibits
		# re-applying to the originally-CC'd enemy.
		#
		# suppress_triggers = true on the apply_status call so the transferred
		# CC does NOT emit on_status_applied — downstream expire-chain listeners
		# (Iron Grip, Silence of the Grave, Chain Control itself) do NOT re-arm
		# on the receiving enemy. One transfer per original WD application;
		# chain terminates cleanly.
		#
		# Source liveness gates the transfer — a dead WD doesn't propagate its
		# control chain.
		if not source_alive:
			return
		if not is_instance_valid(target):
			return
		if effect.status == null:
			return
		if not combat_manager or not combat_manager.get("spatial_grid"):
			return
		var ccc_grid: SpatialGrid = combat_manager.spatial_grid
		var bearer_faction: int = int(target.faction)
		var ccc_radius_sq: float = effect.radius * effect.radius
		var ccc_pool: Array = ccc_grid.get_nearby_in_range(
				target.position, bearer_faction, ccc_radius_sq)
		var ccc_best: Node2D = null
		var ccc_best_dist_sq: float = INF
		for cand in ccc_pool:
			if cand == target:
				continue
			if not is_instance_valid(cand) or not cand.is_alive:
				continue
			if cand.status_effect_component.has_status_with_tag("CC"):
				continue
			var d_sq: float = target.position.distance_squared_to(cand.position)
			if d_sq < ccc_best_dist_sq:
				ccc_best_dist_sq = d_sq
				ccc_best = cand
		if ccc_best == null:
			return
		var transfer_duration: float = effect.status.base_duration * effect.duration_factor
		ccc_best.status_effect_component.apply_status(
				effect.status, source, 1, transfer_duration, false, true)

	elif effect is FactionCleanseEffect:
		# Mass cleanse: sweep every living entity of a faction (relative to
		# source) and apply CleanseEffect semantics (count + target_type).
		# Same "targetless / self-resolving pool" shape as SummonEffect and
		# AreaDamageEffect. First consumer: Divine Purge's enemy buff strip.
		if not source_alive or not combat_manager or not combat_manager.get("spatial_grid"):
			return
		var grid: SpatialGrid = combat_manager.spatial_grid
		var faction_idx: int
		match effect.faction:
			"enemy":
				faction_idx = 1 - int(source.faction)
			"ally":
				faction_idx = int(source.faction)
			_:
				return
		var pool: Array = grid.get_all(faction_idx)
		for entity in pool:
			if not is_instance_valid(entity) or not entity.is_alive:
				continue
			entity.status_effect_component.cleanse(effect.count, effect.target_type, source)

	elif effect is SpawnBankedShotEffect:
		## Fire an aimed projectile whose DealDamageEffect carries the status's
		## accumulated bank as a post-pipeline flat bonus. Dispatched from a
		## status on_expire (so the status is still in _active — see
		## StatusEffectComponent._expire_status: on_expire_effects run before
		## _active.erase). The base DealDamageEffect runs through the full
		## pipeline (vulnerability amps, crit, conversion); the banked portion
		## lands flat on top.
		##
		## Source liveness matters — scaling needs a live source for attribute
		## lookups. Target liveness also matters for projectile aim.
		if not source_alive or not target_alive:
			return
		if not combat_manager or not combat_manager.get("projectile_manager"):
			return
		if effect.projectile == null or effect.base_damage_effect == null:
			return
		var bank_amount: float = target.status_effect_component.get_accumulated_bank(
				effect.bank_status_id)
		# Clone the base DealDamageEffect and stamp the banked bonus. Cloning
		# instead of mutating the shared template so subsequent casts start at
		# flat_bonus_damage = 0.
		var dmg_clone := DealDamageEffect.new()
		dmg_clone.damage_type = effect.base_damage_effect.damage_type
		dmg_clone.scaling_attribute = effect.base_damage_effect.scaling_attribute
		dmg_clone.scaling_coefficient = effect.base_damage_effect.scaling_coefficient
		dmg_clone.base_damage = effect.base_damage_effect.base_damage
		dmg_clone.missing_hp_damage_scaling = effect.base_damage_effect.missing_hp_damage_scaling
		dmg_clone.flat_bonus_damage = bank_amount
		# Clone the ProjectileConfig so the synthesized on_hit_effects array
		# doesn't bleed between casts. Resource.duplicate() is shallow; we
		# rebuild the on_hit_effects array explicitly.
		var proj_clone: ProjectileConfig = effect.projectile.duplicate()
		proj_clone.on_hit_effects = [dmg_clone]
		# Build an ephemeral SpawnProjectilesEffect and route through the
		# projectile_manager's aimed_single path, pre-resolving the painted
		# target as targets[0] so the projectile aims at it regardless of
		# source.attack_target (which may point at a different enemy the
		# Ranger is auto-attacking).
		var eph_spawn := SpawnProjectilesEffect.new()
		eph_spawn.projectile = proj_clone
		eph_spawn.spawn_pattern = "aimed_single"
		combat_manager.projectile_manager.spawn_projectiles(source, ability, eph_spawn, [target])

	elif effect is DispatchAbilityModificationsEffect:
		# Reuse the source's registered ability_modifications (talent/item overlays)
		# on `target` without going through the ability pipeline — the trigger
		# listener becomes a "free cast" that inherits every overlay the source's
		# main ability cast would fire.
		#
		# First consumer: Cleric Angelic Intervention. The emergency heal fires
		# Healing Words' HealEffect directly, then this effect dispatches the
		# registered cleric_healing_words modifications (Overflowing Light chain,
		# Blessed Touch HoT) against the same ally. Future talents that want to
		# piggyback on an ability's overlay set reuse the same effect.
		if not is_instance_valid(source) or not source.is_alive:
			return
		if not is_instance_valid(target) or not target.is_alive:
			return
		var ac = source.get("ability_component")
		if ac == null:
			return
		var mod_effects: Array = ac.get_ability_modifications(effect.ability_id)
		if mod_effects.is_empty():
			return
		execute_effects(mod_effects, source, [target], null, combat_manager,
				fallback_source, "mod:" + effect.ability_id, power_multiplier, echo_source, contributors)


static func execute_effects(effects: Array, source: Node2D, targets: Array,
		ability: AbilityDefinition, combat_manager: Node2D,
		fallback_source: Node2D = null, attribution_tag: String = "",
		power_multiplier: float = 1.0,
		echo_source: EchoSourceConfig = null,
		contributors: Array = []) -> void:
	## Convenience: dispatch an array of effects to an array of targets.
	## Targetless effects (SpawnProjectilesEffect, SummonEffect, DisplacementEffect)
	## execute once with the full targets array.
	## Targeted effects execute once per target.
	for effect in effects:
		if effect is SpawnProjectilesEffect:
			# Projectiles may need pre-resolved targets (at_targets pattern)
			if combat_manager and combat_manager.get("projectile_manager"):
				combat_manager.projectile_manager.spawn_projectiles(source, ability, effect, targets, echo_source)
		elif effect is SummonEffect:
			execute_effect(effect, source, null, ability, combat_manager, fallback_source, attribution_tag, power_multiplier, echo_source, contributors)
		elif effect is FactionCleanseEffect:
			execute_effect(effect, source, null, ability, combat_manager, fallback_source, attribution_tag, power_multiplier, echo_source, contributors)
		elif effect is SpreadStatusEffect:
			execute_effect(effect, source, null, ability, combat_manager, fallback_source, attribution_tag, power_multiplier, echo_source, contributors)
		elif effect is AmplifyActiveStatusEffect:
			execute_effect(effect, source, null, ability, combat_manager, fallback_source, attribution_tag, power_multiplier, echo_source, contributors)
		elif effect is SnapshotAmplifyStatusesEffect:
			execute_effect(effect, source, null, ability, combat_manager, fallback_source, attribution_tag, power_multiplier, echo_source, contributors)
		elif effect is ResurrectEffect:
			execute_effect(effect, source, null, ability, combat_manager, fallback_source, attribution_tag, power_multiplier, echo_source, contributors)
		elif effect is DeathAreaDamageEffect:
			execute_effect(effect, source, null, ability, combat_manager, fallback_source, attribution_tag, power_multiplier, echo_source, contributors)
		elif effect is GroundZoneEffect:
			var zone_target: Node2D = targets[0] if not targets.is_empty() and is_instance_valid(targets[0]) else null
			execute_effect(effect, source, zone_target, ability, combat_manager, fallback_source, attribution_tag, power_multiplier, echo_source, contributors)
		elif effect is DisplacementEffect:
			if combat_manager and combat_manager.get("displacement_system"):
				if effect.mass:
					for target in targets:
						if is_instance_valid(target) and target.is_alive:
							combat_manager.displacement_system.execute(source, ability, effect, [target])
				else:
					combat_manager.displacement_system.execute(source, ability, effect, targets)
		elif effect is OverflowChainEffect:
			_execute_overflow_chain(effect, source, targets, ability, combat_manager)
		elif effect is HealChainEffect:
			_schedule_heal_chain(effect, source, targets, ability, combat_manager, attribution_tag)
		elif effect is ApplyStatusEffectData and effect.apply_to_self:
			execute_effect(effect, source, source, ability, combat_manager, fallback_source, attribution_tag, power_multiplier, echo_source, contributors)
		else:
			for target in targets:
				if is_instance_valid(target) and target.is_alive:
					execute_effect(effect, source, target, ability, combat_manager, fallback_source, attribution_tag, power_multiplier, echo_source, contributors)


static func _schedule_heal_chain(effect: HealChainEffect, source: Node2D,
		targets: Array, ability: AbilityDefinition, combat_manager: Node2D,
		attribution_tag: String) -> void:
	## Queue a deferred heal chain into combat_manager. Hop targets are pre-resolved
	## iteratively at schedule time (each hop's origin = the previous target's
	## schedule-time position) so the chain particle bolt for hop 0 can fire
	## immediately — the bolt's travel_time equals chain_delay, so it arrives at
	## the hop 0 target as the hop 0 heal lands.
	##
	## Subsequent chain bolts (hop N origin = hop N-1 target) are fired inside
	## combat_manager._tick_heal_chains when hop N-1 resolves, again one chain_delay
	## ahead of hop N's heal. Dead source at dispatch = no chain.
	if not combat_manager or effect.hops.is_empty():
		return
	if not is_instance_valid(source) or not source.is_alive:
		return
	var pending: Array = combat_manager.get("_pending_heal_chains")
	if pending == null:
		return
	var tag: String = effect.attribution_tag if effect.attribution_tag != "" else attribution_tag
	var faction: int = int(source.faction)
	var range_sq: float = effect.max_range * effect.max_range
	for primary in targets:
		if not is_instance_valid(primary):
			continue
		# Pre-resolve the full hop sequence from this primary target.
		var hit_set: Dictionary = {}
		hit_set[primary] = true
		var resolved: Array = []
		var prev_pos: Vector2 = primary.position
		for _i in effect.hops.size():
			var next_target: Node2D = combat_manager._find_heal_chain_target(
					prev_pos, faction, range_sq, hit_set)
			if next_target == null:
				break
			hit_set[next_target] = true
			resolved.append(next_target)
			prev_pos = next_target.position
		if resolved.is_empty():
			continue  # Nothing to splash to — skip this primary
		# Fire the hop 0 chain bolt immediately: travels from primary → resolved[0]
		# over one chain_delay, arriving as the hop 0 heal lands.
		if effect.chain_preset and combat_manager.particle_manager:
			combat_manager.particle_manager.claim_line(
					effect.chain_preset,
					primary.position,
					resolved[0].position,
					combat_manager,
					effect.chain_delay,
					1)
		var entry: Dictionary = {
			source = source,
			ability = ability,
			hops = effect.hops,
			hop_index = 0,
			chain_delay = effect.chain_delay,
			attribution_tag = tag,
			target_vfx_layers = effect.target_vfx_layers,
			chain_preset = effect.chain_preset,
			resolved = resolved,
			next_fire_time = combat_manager.run_time + effect.chain_delay,
		}
		pending.append(entry)


static func _execute_overflow_chain(effect: OverflowChainEffect, source: Node2D,
		targets: Array, ability: AbilityDefinition, combat_manager: Node2D) -> void:
	## Process overkill overflow: dead targets' overkill carries to nearest unhit enemy.
	## After chaining, heals source for heal_percent of total damage dealt (base + overflow).
	if not is_instance_valid(source) or not source.is_alive:
		return
	var grid: SpatialGrid = source.get("spatial_grid")
	if not grid:
		return

	var enemy_faction: int = 1 if int(source.faction) == 0 else 0
	var range_sq: float = effect.max_range * effect.max_range

	# Track which entities have received overflow damage (prevent double-overflow)
	var hit_set: Dictionary = {}

	# Collect overflow from dead base targets
	var overflow_queue: Array = []  # [{overkill: float, from_pos: Vector2}]
	for t in targets:
		if not is_instance_valid(t):
			continue
		if not t.health.is_dead:
			continue
		var overkill: float = t.health.last_overkill
		if overkill > 0.0:
			overflow_queue.append({overkill = overkill, from_pos = t.position})

	# Chain overflow to new targets
	var chains_used: int = 0
	var overflow_damage_dealt: float = 0.0
	while not overflow_queue.is_empty() and chains_used < effect.max_chains:
		var entry: Dictionary = overflow_queue.pop_front()
		var overkill: float = entry.overkill

		# Find nearest unhit enemy within range of the killed target (overkill radiates outward)
		var from_pos: Vector2 = entry.from_pos
		var best: Node2D = null
		var best_dist_sq: float = INF
		var pool: Array = grid.get_all(enemy_faction)
		for e in pool:
			if hit_set.has(e):
				continue
			if not e.is_alive:
				continue
			var d_sq: float = from_pos.distance_squared_to(e.position)
			if d_sq <= range_sq and d_sq < best_dist_sq:
				best_dist_sq = d_sq
				best = e

		if not best:
			break

		hit_set[best] = true
		chains_used += 1

		# Deal overkill as raw damage (already pipeline-processed, no double-dip)
		var hit: HitData = HitData.create(overkill, effect.damage_type, source, best, null)
		hit.attribution_tag = "overflow"
		best.take_damage(hit)
		overflow_damage_dealt += overkill

		# Accumulate on source for tracking
		if source.get("_overflow_damage_accumulator") != null:
			source._overflow_damage_accumulator += overkill

		# If this killed the target with overkill, queue another chain
		if best.health.is_dead and best.health.last_overkill > 0.0:
			overflow_queue.append({overkill = best.health.last_overkill, from_pos = best.position})

	# Heal source for heal_percent of total damage dealt (base + overflow)
	if effect.heal_percent > 0.0 and is_instance_valid(source) and not source.health.is_dead:
		var total_damage: float = source._overflow_damage_accumulator if source.get("_overflow_damage_accumulator") != null else overflow_damage_dealt
		var heal_amount: float = total_damage * effect.heal_percent
		if heal_amount > 0.0:
			# Curse-aware (same pattern as Leech)
			if source.status_effect_component.has_status("curse"):
				var curse_hit: HitData = DamageCalculator.calculate_curse_damage(
						source, source, heal_amount)
				source.take_damage(curse_hit)
			else:
				source.health.apply_healing(heal_amount)
				EventBus.on_heal.emit(source, source, heal_amount, "overflow")
