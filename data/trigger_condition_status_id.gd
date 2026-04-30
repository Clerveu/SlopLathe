class_name TriggerConditionStatusId
extends Resource
## Trigger condition: the status involved in the event matches the expected status_id.
## Requires event data to include {"status_id": String} (on_status_applied, on_status_expired).
## First consumer: Heavy Impact (on_status_applied where status is "stun").
##
## negate = true inverts the check: the event's status_id must NOT match. Mirrors
## the shape of TriggerConditionSourceIsSelf's negate. First negate consumer:
## Witch Doctor Plague Carrier (on_status_applied listener filters out its own
## Curse applications so each Corrode/Root/Stun/Fear application rolls once —
## the proc'd Curse doesn't re-trigger another roll).

@export var status_id: String = ""  ## Required status_id to match
@export var negate: bool = false
