class_name TriggerConditionTargetIsSummon
extends Resource
## Trigger condition: the event target's is_summon flag matches expectation.
## Parallels TriggerConditionSourceIsSummon but keyed to the event target
## rather than the source, and generic across summon_id (summons.is_summon is
## true for every summoned entity regardless of kind).
##
## Used to gate listeners that semantically apply only to "real" heroes (or
## only to summons). First consumer: Witch Doctor Undying Pact — the
## free-auto-revive should fire on hero deaths only, not on Spirit Guardian /
## Fire Familiar / future-summon deaths, which would otherwise burn the 90s ICD
## without a successful revive (ResurrectEffect filters persist_as_corpse,
## which summons lack).

@export var negate: bool = false  ## true = pass when target is NOT a summon
