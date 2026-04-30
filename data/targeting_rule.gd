class_name TargetingRule
extends Resource
## Defines how an ability selects its targets.

@export var type: String = "nearest_enemy"  ## "nearest_enemy", "nearest_enemies", "furthest_enemy",
                                            ## "lowest_hp_ally", "self", "all_enemies_in_range",
                                            ## "self_centered_burst", "all_allies",
                                            ## "priority_tiered_enemy", etc.
@export var max_range: float = 0.0         ## Max distance (0 = unlimited / melee)
@export var max_targets: int = 1           ## How many targets (1 for single-target, N for AOE)
@export var height: float = 0.0            ## Rectangle height for frontal_rectangle targeting (0 = unused)
@export var min_nearby: int = 0            ## Min OTHER enemies within nearby_radius of target (0 = no cluster filter)
@export var nearby_radius: float = 0.0     ## Radius for cluster check around resolved target
@export var target_status_id: String = ""  ## Status ID for stack-based targeting (lowest_stacks_enemy)
@export var max_x_ratio: float = 0.0      ## Max x-position as viewport ratio (0 = no filter, 0.33 = left third only)
@export var priority_tiers: Array[String] = []  ## Ordered tier list for "priority_tiered_enemy" targeting.
                                                 ## Each tier is checked in order; first tier with any matching
                                                 ## candidates wins. Supported tiers: "healer", "caster", "ranged",
                                                 ## "elite", "boss". When no tier matches, targeting falls back
                                                 ## to nearest_enemy. First consumer: Ranger Hunter's Priority.


## --- Priority-tier classification helpers ---
## Static so any system (BehaviorComponent targeting, trigger condition evaluation,
## ability modification registration) can classify an entity against a tier string
## using the same matcher. Tier strings are the vocabulary; new tiers add match arms
## here and on whatever Resource carries the classification flags (EnemyDefinition
## today, entity runtime fields at apply time).

static func entity_matches_priority_tier(entity: Node2D, tier: String) -> bool:
	## Returns true if `entity` satisfies the classification for `tier`.
	## Relies on runtime fields populated from EnemyDefinition in setup_from_enemy_def
	## (priority_role, is_elite, is_boss) and the entity's combat_role enum (RANGED == 1).
	if not is_instance_valid(entity):
		return false
	match tier:
		"healer":
			return String(entity.get("priority_role")) == "healer"
		"caster":
			return String(entity.get("priority_role")) == "caster"
		"ranged":
			return int(entity.get("combat_role")) == 1  # Entity.CombatRole.RANGED
		"elite":
			return bool(entity.get("is_elite"))
		"boss":
			return bool(entity.get("is_boss"))
	return false


static func entity_matches_any_priority_tier(entity: Node2D, tiers: Array) -> bool:
	## Returns true if `entity` matches any tier in `tiers`. Used by
	## TriggerConditionTargetMatchesPriorityTier to gate bonus effects (e.g. Hunter's
	## Priority's +1 Mark on priority-target AA hits) — the tier list deliberately
	## excludes the implicit "nearest" fallback, so fallback targets return false.
	for tier in tiers:
		if entity_matches_priority_tier(entity, tier):
			return true
	return false
