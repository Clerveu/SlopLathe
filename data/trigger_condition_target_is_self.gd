class_name TriggerConditionTargetIsSelf
extends Resource
## Trigger condition: the target of the event is the entity bearing the trigger.
## Used by Bloodrage — only hits received by THIS entity build Rage.
##
## negate = true inverts the check: the target must NOT be self. Used by
## Cleric Martyrdom to exclude hits landing on the Cleric herself (she
## shouldn't redirect her own damage to herself).

@export var negate: bool = false
