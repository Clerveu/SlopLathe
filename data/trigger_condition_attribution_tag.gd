class_name TriggerConditionAttributionTag
extends Resource
## Trigger condition: the event's attribution_tag matches a specific tag.
## Works against HitData.attribution_tag (on_hit_dealt / on_hit_received / on_crit)
## and Dictionary payloads carrying "attribution_tag" (on_heal).
## When `negate` is true, the condition passes only if the tag does NOT match —
## used to filter out recursive self-dispatched events (e.g. Spirit Link's own
## bonus heals emitting on_heal → re-triggering the Spirit Link listener).
## First consumer: Righteous Wrath (filter on_hit_dealt to "word_of_pain" DoT ticks).
## Second consumer: Spirit Link (filter on_heal to non-recursive heals).

@export var tag: String = ""
@export var negate: bool = false
