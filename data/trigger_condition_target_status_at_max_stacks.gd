class_name TriggerConditionTargetStatusAtMaxStacks
extends Resource
## Trigger condition: the event target currently has `status_id` at its runtime
## maximum stacks. Honors source-driven runtime overrides — compares against
## ActiveStatus.get_max_stacks(), not StatusEffectDefinition.max_stacks — so the
## check stays correct when the bearer's talents (Accelerant, Intense Heat)
## raise the effective cap. First consumer: Wizard Persistent Flames (refresh
## nearby Burns when the Wizard applies Burn to a max-stacked target).

@export var status_id: String = ""
