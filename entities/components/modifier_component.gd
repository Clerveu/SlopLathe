class_name ModifierComponent
extends Node
## Flat list of active modifiers with cached query layer.
## Modifiers come from equipment, talents, status effects, run buffs.
## Cache invalidated on add/remove, rebuilt lazily on next query.

var _modifiers: Array[ModifierDefinition] = []
var _conversions: Array[ConversionDefinition] = []
## Echo sources registered on this entity (talent / item / status). Iterated O(N)
## at cast commit by entity._schedule_echo_replays — never per-frame, so no cache.
## Provenance lives in a parallel array because EchoSourceConfig is a shared
## Resource and must NOT be mutated per-consumer (parallels how _modifiers reads
## source_name off the Resource itself; echo configs are externally provenanced).
var _echo_sources: Array[EchoSourceConfig] = []
var _echo_source_provenance: Array[String] = []
## Status modifier injections registered on this entity (talent / item). Snapshotted
## by StatusEffectComponent.apply_status when this entity is the SOURCE applying the
## status — the snapshot is stored on the ActiveStatus and scaled per-stack alongside
## the status definition's own modifiers. Provenance lives in a parallel array per
## status_id for source-name-based removal (parallels `_echo_source_provenance`).
## First consumer: Wizard Scorched (per Burn stack +3% Fire vulnerability on bearer).
var _status_modifier_injections: Dictionary = {}      ## status_id (String) -> Array[ModifierDefinition]
var _status_modifier_injection_provenance: Dictionary = {}  ## status_id -> Array[String] (parallel to above)

## Cache: keyed by "tag:operation" → precomputed sum
var _cache: Dictionary = {}
var _cache_dirty: bool = true


# --- Modifier management ---

func add_modifier(mod: ModifierDefinition) -> void:
	_modifiers.append(mod)
	_cache_dirty = true


func remove_modifier(mod: ModifierDefinition) -> void:
	var idx := _modifiers.find(mod)
	if idx >= 0:
		_modifiers.remove_at(idx)
		_cache_dirty = true


func remove_modifiers_by_source(source: String) -> void:
	var i := _modifiers.size() - 1
	while i >= 0:
		if _modifiers[i].source_name == source:
			_modifiers.remove_at(i)
			_cache_dirty = true
		i -= 1


func add_conversion(conv: ConversionDefinition) -> void:
	_conversions.append(conv)


func remove_conversion(conv: ConversionDefinition) -> void:
	var idx := _conversions.find(conv)
	if idx >= 0:
		_conversions.remove_at(idx)


func remove_conversions_by_source(source: String) -> void:
	var i := _conversions.size() - 1
	while i >= 0:
		if _conversions[i].source_name == source:
			_conversions.remove_at(i)
		i -= 1


# --- Echo source management ---

func add_echo_source(src: EchoSourceConfig, source_name: String) -> void:
	_echo_sources.append(src)
	_echo_source_provenance.append(source_name)


func remove_echo_source(src: EchoSourceConfig) -> void:
	var idx := _echo_sources.find(src)
	if idx >= 0:
		_echo_sources.remove_at(idx)
		_echo_source_provenance.remove_at(idx)


func remove_echo_sources_by_source(source_name: String) -> void:
	var i := _echo_sources.size() - 1
	while i >= 0:
		if _echo_source_provenance[i] == source_name:
			_echo_sources.remove_at(i)
			_echo_source_provenance.remove_at(i)
		i -= 1


func get_echo_sources() -> Array[EchoSourceConfig]:
	return _echo_sources


# --- Status modifier injection management ---

func add_status_modifier_injection(status_id: String, mod: ModifierDefinition,
		source_name: String) -> void:
	## Register a modifier to inject into any future apply of `status_id` where this
	## entity is the source. The injected modifier is scaled per-stack by
	## StatusEffectComponent._sync_modifiers, same as definition modifiers.
	if not _status_modifier_injections.has(status_id):
		_status_modifier_injections[status_id] = []
		_status_modifier_injection_provenance[status_id] = []
	_status_modifier_injections[status_id].append(mod)
	_status_modifier_injection_provenance[status_id].append(source_name)


func remove_status_modifier_injections_by_source(source_name: String) -> void:
	## Remove all injection entries registered with `source_name` across every status_id.
	for status_id in _status_modifier_injections.keys():
		var provs: Array = _status_modifier_injection_provenance[status_id]
		var i := provs.size() - 1
		while i >= 0:
			if provs[i] == source_name:
				provs.remove_at(i)
				_status_modifier_injections[status_id].remove_at(i)
			i -= 1
		if _status_modifier_injections[status_id].is_empty():
			_status_modifier_injections.erase(status_id)
			_status_modifier_injection_provenance.erase(status_id)


func get_status_modifier_injections(status_id: String) -> Array:
	## Return the array of injected ModifierDefinitions for `status_id` (empty if none).
	## Caller treats as read-only — these are shared Resources, do not mutate.
	return _status_modifier_injections.get(status_id, [])


# --- Queries ---

func sum_modifiers(tag: String, operation: String) -> float:
	if _cache_dirty:
		_rebuild_cache()
	var key := tag + ":" + operation
	return _cache.get(key, 0.0)


func has_negation(tag: String) -> bool:
	## Returns true if any modifier negates the given tag (immunity).
	if _cache_dirty:
		_rebuild_cache()
	return _cache.get(tag + ":negate", 0.0) > 0.0


func get_pierce_value(tag: String) -> float:
	return sum_modifiers(tag, "pierce")


func get_first_conversion(source_type: String) -> ConversionDefinition:
	## Returns the first conversion matching source_type. Processing order = insertion order
	## (talents → equipment → status effects → run buffs).
	for conv in _conversions:
		if conv.source_type == source_type:
			return conv
	return null


func get_all_modifiers() -> Array[ModifierDefinition]:
	return _modifiers


# --- Cache ---

func _rebuild_cache() -> void:
	_cache.clear()
	for mod in _modifiers:
		var key := mod.target_tag + ":" + mod.operation
		_cache[key] = _cache.get(key, 0.0) + mod.value
	_cache_dirty = false
