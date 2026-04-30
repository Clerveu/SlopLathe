class_name ApplyStatusEffectData
extends Resource
## Effect sub-resource: apply a status effect to targets.

@export var status: StatusEffectDefinition  ## The status to apply
@export var stacks: int = 1
@export var duration: float = -1.0  ## Seconds (-1 = use status default)
@export var apply_to_self: bool = false  ## When true, applies to source (caster) instead of target
