class_name TriggerConditionApplierIsSelf
extends Resource
## Trigger condition: the original applier of the event's status is the entity
## bearing the trigger. Reads from event payload Dictionary's "applier" key
## (on_cleanse carries applier). Used to filter cleanse events to only those
## removing statuses the bearer originally applied.
##
## Fails on events without an applier key (non-cleanse events). Treats null
## applier as not-self (covers the freed-applier case).
##
## negate = true inverts the check: the applier must NOT be self. First consumer:
## Witch Doctor Backfire Hex (on_cleanse listener filters to cleansed debuffs
## the WD originally applied, redistributing them at 2× stacks to enemies near
## the cleanse event).

@export var negate: bool = false
