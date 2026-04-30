class_name CombatTracker
extends RefCounted
## Centralized combat data accumulator. Listens to EventBus, records per-entity
## stats with full source attribution. Created by combat_manager, read by UI.

class EntityStats:
	var entity_id: String
	var entity_name: String
	var faction: int  # 0 = hero, 1 = enemy
	var is_summon: bool
	var summoner_id: int  # instance_id of summoner (0 if not a summon)

	# --- Offensive ---
	var damage_dealt: float = 0.0
	var damage_dealt_by_ability: Dictionary = {}    # ability_id → float
	var damage_dealt_by_type: Dictionary = {}       # damage_type → float
	var damage_dealt_by_source: Dictionary = {}     # attribution_tag → float
	var healing_done: float = 0.0
	var healing_done_by_source: Dictionary = {}     # attribution_tag → float
	var shielding_done: float = 0.0                 # Total damage absorbed by shields this entity cast
	var shielding_done_by_target: Dictionary = {}   # shielded entity_name → float
	var kills: int = 0
	var crits_dealt: int = 0
	var ability_uses: Dictionary = {}               # ability_id → int
	var summon_damage_dealt: float = 0.0            # damage dealt by owned summons
	var summon_damage_by_summon: Dictionary = {}     # summon instance_id → float
	var summon_kills: int = 0                        # kills by owned summons

	# --- Defensive ---
	var damage_taken: float = 0.0
	var damage_taken_by_type: Dictionary = {}       # damage_type → float
	var damage_taken_by_source: Dictionary = {}     # attacker entity_name → float
	var damage_taken_by_ability: Dictionary = {}    # ability_id → float
	var healing_received: float = 0.0
	var healing_received_by_source: Dictionary = {} # healer entity_name → float
	var damage_blocked: float = 0.0
	var dodges: int = 0
	var damage_dr_mitigated: float = 0.0
	var damage_absorbed: float = 0.0
	var crits_received: int = 0
	var deaths: int = 0
	var killing_blow: Dictionary = {}               # {killer_id, damage_type, amount}

	# --- Trigger/talent tracking ---
	var trigger_fires: Dictionary = {}              # source_id → int

	# --- Status tracking ---
	var status_uptime: Dictionary = {}              # status_id → {total_time, apply_count, current_start}
	var status_stacks_sum: Dictionary = {}          # status_id → cumulative stacks-over-time

	# --- Progression (heroes only; null character_data means excluded from XP tally) ---
	var xp_earned: int = 0
	var character_data: CharacterData = null


var _stats: Dictionary = {}  # entity instance_id → EntityStats
var combat_manager: Node2D = null  # For run_time access


func register_entity(entity: Node2D, char_data: CharacterData = null) -> void:
	var eid: int = entity.get_instance_id()
	if _stats.has(eid):
		return
	var stats := EntityStats.new()
	stats.entity_id = entity.entity_id
	# Display name: class name for heroes, enemy_id for enemies
	if entity.unit_def:
		stats.entity_name = entity.unit_def.unit_id
	else:
		stats.entity_name = entity.entity_id
	stats.faction = int(entity.faction)
	stats.is_summon = entity.is_summon
	if entity.is_summon and is_instance_valid(entity.summoner):
		stats.summoner_id = entity.summoner.get_instance_id()
	stats.character_data = char_data
	_stats[eid] = stats


func connect_signals() -> void:
	EventBus.on_hit_dealt.connect(_on_hit_dealt)
	EventBus.on_hit_received.connect(_on_hit_received)
	EventBus.on_heal.connect(_on_heal)
	EventBus.on_block.connect(_on_block)
	EventBus.on_dodge.connect(_on_dodge)
	EventBus.on_absorb.connect(_on_absorb)
	EventBus.on_kill.connect(_on_kill)
	EventBus.on_death.connect(_on_death)
	EventBus.on_ability_used.connect(_on_ability_used)
	EventBus.on_trigger_fired.connect(_on_trigger_fired)
	EventBus.on_status_applied.connect(_on_status_applied)
	EventBus.on_status_expired.connect(_on_status_expired)
	EventBus.on_status_consumed.connect(_on_status_consumed)
	EventBus.on_cleanse.connect(_on_cleanse)
	EventBus.on_reflect.connect(_on_reflect)


func disconnect_signals() -> void:
	if EventBus.on_hit_dealt.is_connected(_on_hit_dealt):
		EventBus.on_hit_dealt.disconnect(_on_hit_dealt)
	if EventBus.on_hit_received.is_connected(_on_hit_received):
		EventBus.on_hit_received.disconnect(_on_hit_received)
	if EventBus.on_heal.is_connected(_on_heal):
		EventBus.on_heal.disconnect(_on_heal)
	if EventBus.on_block.is_connected(_on_block):
		EventBus.on_block.disconnect(_on_block)
	if EventBus.on_dodge.is_connected(_on_dodge):
		EventBus.on_dodge.disconnect(_on_dodge)
	if EventBus.on_absorb.is_connected(_on_absorb):
		EventBus.on_absorb.disconnect(_on_absorb)
	if EventBus.on_kill.is_connected(_on_kill):
		EventBus.on_kill.disconnect(_on_kill)
	if EventBus.on_death.is_connected(_on_death):
		EventBus.on_death.disconnect(_on_death)
	if EventBus.on_ability_used.is_connected(_on_ability_used):
		EventBus.on_ability_used.disconnect(_on_ability_used)
	if EventBus.on_trigger_fired.is_connected(_on_trigger_fired):
		EventBus.on_trigger_fired.disconnect(_on_trigger_fired)
	if EventBus.on_status_applied.is_connected(_on_status_applied):
		EventBus.on_status_applied.disconnect(_on_status_applied)
	if EventBus.on_status_expired.is_connected(_on_status_expired):
		EventBus.on_status_expired.disconnect(_on_status_expired)
	if EventBus.on_status_consumed.is_connected(_on_status_consumed):
		EventBus.on_status_consumed.disconnect(_on_status_consumed)
	if EventBus.on_cleanse.is_connected(_on_cleanse):
		EventBus.on_cleanse.disconnect(_on_cleanse)
	if EventBus.on_reflect.is_connected(_on_reflect):
		EventBus.on_reflect.disconnect(_on_reflect)


# --- Query API ---

func get_hero_stats() -> Array:
	## Returns EntityStats for all registered heroes (including summons), sorted by damage dealt.
	var result: Array = []
	for eid in _stats:
		var s: EntityStats = _stats[eid]
		if s.faction == 0:
			result.append(s)
	result.sort_custom(func(a, b): return a.damage_dealt > b.damage_dealt)
	return result


func get_entity_stats(instance_id: int) -> EntityStats:
	return _stats.get(instance_id, null)


func get_total_party_damage() -> float:
	## Sum of hero-faction damage dealt (excludes summon double-count).
	var total: float = 0.0
	for eid in _stats:
		var s: EntityStats = _stats[eid]
		if s.faction == 0 and not s.is_summon:
			total += s.damage_dealt + s.summon_damage_dealt
	return total


func get_total_party_healing() -> float:
	var total: float = 0.0
	for eid in _stats:
		var s: EntityStats = _stats[eid]
		if s.faction == 0:
			total += s.healing_done
	return total


func get_run_duration() -> float:
	return combat_manager.run_time if combat_manager else 0.0


# --- EventBus handlers ---

func _on_hit_dealt(source: Variant, _target: Variant, hit_data: Variant) -> void:
	if not is_instance_valid(source):
		return
	var sid: int = source.get_instance_id()
	var s: EntityStats = _stats.get(sid)
	if not s:
		return

	var amount: float = hit_data.amount if hit_data is HitData else hit_data.get("amount", 0.0)
	if amount <= 0.0:
		return

	s.damage_dealt += amount

	# Per-ability attribution
	if hit_data is HitData and hit_data.ability:
		var aid: String = hit_data.ability.ability_id
		s.damage_dealt_by_ability[aid] = s.damage_dealt_by_ability.get(aid, 0.0) + amount

	# Per-type attribution
	var dtype: String = hit_data.damage_type if hit_data is HitData else "Physical"
	s.damage_dealt_by_type[dtype] = s.damage_dealt_by_type.get(dtype, 0.0) + amount

	# Per-source attribution (attribution_tag)
	if hit_data is HitData and hit_data.attribution_tag != "":
		var tag: String = hit_data.attribution_tag
		s.damage_dealt_by_source[tag] = s.damage_dealt_by_source.get(tag, 0.0) + amount

	# Crit tracking
	if hit_data is HitData and hit_data.is_crit:
		s.crits_dealt += 1

	# Block/DR mitigation tracking (from the hit itself — attacker perspective)
	if hit_data is HitData:
		if hit_data.block_mitigated > 0.0:
			var tid: int = _target.get_instance_id() if is_instance_valid(_target) else 0
			var ts: EntityStats = _stats.get(tid)
			if ts:
				ts.damage_blocked += hit_data.block_mitigated
		if hit_data.dr_mitigated > 0.0:
			var tid: int = _target.get_instance_id() if is_instance_valid(_target) else 0
			var ts: EntityStats = _stats.get(tid)
			if ts:
				ts.damage_dr_mitigated += hit_data.dr_mitigated

	# Summon roll-up: credit summoner
	if s.is_summon and s.summoner_id > 0:
		var owner_s: EntityStats = _stats.get(s.summoner_id)
		if owner_s:
			owner_s.summon_damage_dealt += amount
			owner_s.summon_damage_by_summon[sid] = owner_s.summon_damage_by_summon.get(sid, 0.0) + amount


func _on_hit_received(source: Variant, target: Variant, hit_data: Variant) -> void:
	if not is_instance_valid(target):
		return
	var tid: int = target.get_instance_id()
	var s: EntityStats = _stats.get(tid)
	if not s:
		return

	var amount: float = hit_data.amount if hit_data is HitData else hit_data.get("amount", 0.0)
	if amount <= 0.0:
		return

	s.damage_taken += amount

	var dtype: String = hit_data.damage_type if hit_data is HitData else "Physical"
	s.damage_taken_by_type[dtype] = s.damage_taken_by_type.get(dtype, 0.0) + amount

	# Per-source attribution (who hit me)
	if is_instance_valid(source):
		var src_name: String = source.entity_id if source.get("entity_id") else "unknown"
		s.damage_taken_by_source[src_name] = s.damage_taken_by_source.get(src_name, 0.0) + amount

	# Per-ability attribution (what ability hit me)
	if hit_data is HitData and hit_data.ability:
		var aid: String = hit_data.ability.ability_id
		s.damage_taken_by_ability[aid] = s.damage_taken_by_ability.get(aid, 0.0) + amount

	if hit_data is HitData and hit_data.is_crit:
		s.crits_received += 1


func _on_heal(source: Variant, target: Variant, amount: float,
		attribution_tag: String = "") -> void:
	# Healing done (source)
	if is_instance_valid(source):
		var sid: int = source.get_instance_id()
		var s: EntityStats = _stats.get(sid)
		if s:
			s.healing_done += amount
			if attribution_tag != "":
				s.healing_done_by_source[attribution_tag] = s.healing_done_by_source.get(attribution_tag, 0.0) + amount
	# Healing received (target)
	if is_instance_valid(target):
		var tid: int = target.get_instance_id()
		var s: EntityStats = _stats.get(tid)
		if s:
			s.healing_received += amount
			# Per-source attribution (who healed me)
			if is_instance_valid(source):
				var src_name: String = source.entity_id if source.get("entity_id") else "unknown"
				s.healing_received_by_source[src_name] = s.healing_received_by_source.get(src_name, 0.0) + amount


func _on_block(_source: Variant, target: Variant, _hit_data: Variant,
		mitigated: float) -> void:
	# Block mitigation is already tracked via _on_hit_dealt (hit_data.block_mitigated).
	# This handler exists for dodge-like block events where the hit doesn't land.
	pass


func _on_dodge(_source: Variant, target: Variant, _hit_data: Variant) -> void:
	if not is_instance_valid(target):
		return
	var tid: int = target.get_instance_id()
	var s: EntityStats = _stats.get(tid)
	if s:
		s.dodges += 1


func _on_absorb(entity: Variant, _hit_data: Variant, absorbed: float,
		drain_sources: Array = []) -> void:
	if not is_instance_valid(entity):
		return
	var eid: int = entity.get_instance_id()
	var s: EntityStats = _stats.get(eid)
	if s:
		s.damage_absorbed += absorbed
	# Credit each shield source's caster for their share of the absorption
	var target_name: String = entity.entity_id if entity.get("entity_id") else "unknown"
	for drain in drain_sources:
		var src: Node2D = drain.get("source_entity")
		if not is_instance_valid(src):
			continue
		var src_id: int = src.get_instance_id()
		var src_s: EntityStats = _stats.get(src_id)
		if src_s:
			src_s.shielding_done += drain.amount
			src_s.shielding_done_by_target[target_name] = src_s.shielding_done_by_target.get(target_name, 0.0) + drain.amount


func _on_kill(killer: Variant, victim: Variant) -> void:
	if is_instance_valid(killer):
		var kid: int = killer.get_instance_id()
		var s: EntityStats = _stats.get(kid)
		if s:
			s.kills += 1
			# Summon kill roll-up
			if s.is_summon and s.summoner_id > 0:
				var owner_s: EntityStats = _stats.get(s.summoner_id)
				if owner_s:
					owner_s.summon_kills += 1

	# XP distribution: every living non-summon hero gets the victim's xp_value.
	# Hero-faction deaths (enemy_def == null) never flow XP — prevents friendly-fire
	# kills or hero-as-corpse scenarios from granting progression.
	if not is_instance_valid(victim) or victim.enemy_def == null:
		return
	var xp_value: int = victim.enemy_def.xp_value
	if not combat_manager:
		return
	for hero in combat_manager.heroes:
		if not is_instance_valid(hero) or not hero.is_alive or hero.is_summon:
			continue
		var hs: EntityStats = _stats.get(hero.get_instance_id())
		if hs:
			hs.xp_earned += xp_value


func _on_death(entity: Variant) -> void:
	if not is_instance_valid(entity):
		return
	var eid: int = entity.get_instance_id()
	var s: EntityStats = _stats.get(eid)
	if s:
		s.deaths += 1
		# Record killing blow
		if is_instance_valid(entity.last_hit_by):
			s.killing_blow = {
				killer_id = entity.last_hit_by.entity_id,
				damage_type = "",
				amount = 0.0,
			}


func _on_ability_used(source: Variant, ability: AbilityDefinition) -> void:
	if not is_instance_valid(source):
		return
	var sid: int = source.get_instance_id()
	var s: EntityStats = _stats.get(sid)
	if s and ability:
		var aid: String = ability.ability_id
		s.ability_uses[aid] = s.ability_uses.get(aid, 0) + 1


func _on_trigger_fired(entity: Variant, source_id: String,
		_event_type: String) -> void:
	if not is_instance_valid(entity):
		return
	var eid: int = entity.get_instance_id()
	var s: EntityStats = _stats.get(eid)
	if s:
		s.trigger_fires[source_id] = s.trigger_fires.get(source_id, 0) + 1


func _on_status_applied(_source: Variant, target: Variant, status_id: String,
		stacks: int) -> void:
	if not is_instance_valid(target):
		return
	var tid: int = target.get_instance_id()
	var s: EntityStats = _stats.get(tid)
	if not s:
		return

	var run_t: float = combat_manager.run_time if combat_manager else 0.0

	if not s.status_uptime.has(status_id):
		s.status_uptime[status_id] = {total_time = 0.0, apply_count = 0, current_start = run_t}
	var info: Dictionary = s.status_uptime[status_id]
	if info.current_start < 0.0:
		info.current_start = run_t  # Re-applied after expiry
	info.apply_count += 1

	# Accumulate stacks for weighted average
	s.status_stacks_sum[status_id] = s.status_stacks_sum.get(status_id, 0.0) + stacks


func _close_status_uptime(entity: Variant, status_id: String) -> void:
	## Close an uptime window for a status (expired, consumed, or cleansed).
	if not is_instance_valid(entity):
		return
	var eid: int = entity.get_instance_id()
	var s: EntityStats = _stats.get(eid)
	if not s:
		return
	if not s.status_uptime.has(status_id):
		return
	var info: Dictionary = s.status_uptime[status_id]
	if info.current_start >= 0.0:
		var run_t: float = combat_manager.run_time if combat_manager else 0.0
		info.total_time += run_t - info.current_start
		info.current_start = -1.0  # Mark as inactive


func _on_status_expired(entity: Variant, status_id: String) -> void:
	_close_status_uptime(entity, status_id)


func _on_status_consumed(entity: Variant, status_id: String,
		_stacks: int) -> void:
	_close_status_uptime(entity, status_id)


func _on_cleanse(_source: Variant, target: Variant, status_id: String,
		_applier: Variant, _stacks: int, _definition: Variant) -> void:
	_close_status_uptime(target, status_id)


func _on_reflect(_source: Variant, _target: Variant, _hit_data: Variant) -> void:
	## Thorns damage is already tracked via on_hit_dealt (reflect_hit goes through
	## take_damage which emits on_hit_dealt). attribution_tag = "thorns" handles
	## source attribution. This handler reserved for future reflect-specific metrics.
	pass
