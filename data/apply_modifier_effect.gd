class_name ApplyModifierEffectData
extends Resource
## Effect sub-resource: apply a modifier to targets.

@export var modifier: ModifierDefinition
@export var duration: float = -1.0  ## Seconds (-1 = permanent until source removed)
