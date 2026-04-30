class_name TriggerConditionHitExceedsMaxHpPercent
extends Resource
## Trigger condition: the event's hit amount exceeds a fraction of the event
## target's max HP. Evaluated against HitData payloads (on_hit_received,
## on_hit_dealt, on_crit). Fails if the event has no HitData.
## First consumer: Cleric Martyrdom (only intercept spike hits > 25% max HP).

@export var threshold: float = 0.25  ## Fraction of target max HP (0.0–1.0)
