class_name CleanseEffect
extends Resource
## Effect sub-resource: remove status effects from targets.

@export var count: int = 1           ## How many statuses to remove (-1 = all)
@export var target_type: String = "negative"  ## "negative", "positive", "any"
@export var target_status_id: String = ""     ## When non-empty, remove this specific status (ignores count/target_type)
