class_name TriggerConditionSourceIsSummon
extends Resource
## Trigger condition: the event source is one of the bearer's active summons
## with the given summon_id. Lets a hero's listener filter events triggered by
## its own summons (separately from its own actions and other allies' actions).
##
## First consumer: Cleric Consecrated Spirit (Exorcist T2) — fires only when
## one of the Cleric's spirit_guardian summons deals a hit, ignoring the
## Cleric's own hits and every other entity in the scene.

@export var summon_id: String = ""
