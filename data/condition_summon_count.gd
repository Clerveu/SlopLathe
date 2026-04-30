class_name ConditionSummonCount
extends Resource
## Ability condition: source has a count of living summons of `summon_id` within
## [min_count, max_count]. Mirrors ConditionStackCount's min/max shape.
##
## min_count = 0  → no minimum (default).
## max_count = -1 → no maximum (default).
##
## Spirit Guardian / Fire Familiar use max_count = 0 to gate "only cast when no
## living summon exists" (replacement-on-death timing; pairs with
## SummonEffect.reset_cooldown_on_death). Future "cap N" abilities use
## max_count = N - 1. Future "requires at least one summon alive" abilities use
## min_count = 1.

@export var summon_id: String = ""
@export var min_count: int = 0
@export var max_count: int = -1  ## -1 = no upper bound. 0 = "only when no summon of this id"
