class_name TriggerConditionSourceIsSelf
extends Resource
## Trigger condition: the source of the event is the entity bearing the trigger.
## Used by Steady Aim — only the Ranger's own hits build Focus.
##
## negate = true inverts the check: the source must NOT be self. Mirrors the
## shape of TriggerConditionTargetIsSelf's negate. First negate consumer:
## Ranger Marked For Death (on_kill listener filters out the Ranger's own
## kills so only ally-kills grant the Crippling Shot charge).

@export var negate: bool = false
