class_name TriggerConditionHitIsEcho
extends Resource
## Trigger condition: the event's HitData.is_echo matches expectation.
## Reads HitData from hit-shaped events (on_hit_dealt / on_hit_received / on_crit).
## When `negate` is true, the condition passes only if the hit is NOT an echo —
## used by listeners that should skip on echo-replayed hits ("no free proc
## velocity" principle). First consumer: Ranger Heavy Draw / Hunter's Priority
## bonus Mark stack listeners, so echo replays (Ranger Echo Shot) don't deposit
## Mark stacks via the AA-gated bonus listeners.
## Non-hit events (on_heal, on_status_*, on_cleanse, on_kill) fail the condition —
## there's no HitData to inspect. Listeners on those events should not attach this.

@export var negate: bool = false
