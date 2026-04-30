class_name ConditionStackCount
extends Resource
## Ability condition: requires stacks of a specific status effect within a range.
## min_stacks: minimum stacks required (condition fails if stacks < min_stacks).
## max_stacks: maximum stacks allowed (condition fails if stacks > max_stacks). -1 = no upper bound.
## target: "self" (check on caster), "target" (check on ability target), or "any_enemy" (check all enemies in spatial grid).

@export var status_id: String = ""
@export var min_stacks: int = 1
@export var max_stacks: int = -1  ## -1 = no upper bound. 0 = "only when status absent"
@export var target: String = "self"  ## "self" or "target"
