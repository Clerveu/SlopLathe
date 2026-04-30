class_name TriggerConditionTargetHotCount
extends Resource
## Trigger condition: the event target has at least `min_count` active HoT statuses.
## "HoT" = positive status with "Heal" tag and tick_interval > 0.
## First consumer: Cleric Deepening Faith (refresh HoTs when target has 2+).

@export var min_count: int = 2
