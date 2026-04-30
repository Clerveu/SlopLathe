class_name TriggerConditionTargetHasNegativeStatus
extends Resource
## Trigger condition: the event target has at least one active negative status.
## First consumer: Cleric Absolution (Healing Words passively cleanses the heal
## target's oldest debuff — the listener fires only when there's actually a
## debuff to remove, so the per-target ICD marker isn't burned on no-op heals).
