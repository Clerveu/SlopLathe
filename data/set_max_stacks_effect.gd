class_name SetMaxStacksEffect
extends Resource
## Effect sub-resource: set a status to max stacks.
## If the status is already active, sets stacks to max and refreshes duration.
## If not active but status definition is provided, applies it at max stacks.
## When required_talent_id is set, only fires if the target entity has that talent.

@export var status_id: String = ""                       ## Which status to max out
@export var status: StatusEffectDefinition = null        ## Definition to apply if status not active (null = skip if absent)
@export var required_talent_id: String = ""              ## Only fire if entity has this talent ("" = always fire)
