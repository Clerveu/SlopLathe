class_name TriggerConditionTargetHasStatus
extends Resource
## Trigger condition: the event target has (or lacks) a specific status by id.
## Used for per-target internal cooldowns and status-gated triggers.
## First consumer: Cleric Angelic Intervention (filter out allies already
## covered by the 15s per-ally ICD marker `angelic_intervention_icd`).

@export var status_id: String = ""
@export var negate: bool = false  ## true = pass when target LACKS the status
