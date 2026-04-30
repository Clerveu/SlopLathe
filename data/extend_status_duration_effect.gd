class_name ExtendStatusDurationEffect
extends Resource
## Effect sub-resource: extend the remaining duration of an active status on the target.
## Respects max_extensions on StatusEffectDefinition. No-op if status not active.

@export var status_id: String = ""      ## Which status to extend
@export var seconds: float = 0.0        ## Duration to add (seconds)
