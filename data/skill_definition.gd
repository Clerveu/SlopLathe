class_name SkillDefinition
extends Resource
## A skill slot entry — wraps an AbilityDefinition with unlock level info.

@export var skill_name: String = ""
@export var unlock_level: int = 1          ## 1, 3, 5, 7, 9, or 10 (capstone)
@export var is_ultimate: bool = false      ## True for 6th slot capstone skill
@export var ability: AbilityDefinition
