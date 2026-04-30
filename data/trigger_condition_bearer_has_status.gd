class_name TriggerConditionBearerHasStatus
extends Resource
## Trigger condition: the listener's BEARER (the entity hosting the listener)
## has or lacks a specific status by id. Parallels TriggerConditionTargetHasStatus,
## which checks the event target — this checks the bearer, regardless of
## who the event source/target are.
##
## Used for per-bearer internal cooldowns on source-side listeners: apply
## an ICD marker status to the bearer inside the listener's effects array,
## then gate the listener with this condition (negate=true) so subsequent
## firings within the ICD window are skipped without touching the target
## side of the event.
##
## First consumer: Ranger Fusillade (execute listener gated by bearer lacking
## `fusillade_execute_icd` — 1s per-Ranger execute cadence limiter).

@export var status_id: String = ""
@export var negate: bool = false  ## true = pass when BEARER LACKS the status
