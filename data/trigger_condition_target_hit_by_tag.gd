class_name TriggerConditionTargetHitByTag
extends Resource
## Trigger condition: the event target was recently hit by an ability with a specific tag.
## Checks target._last_hit_time_by_tag[tag] against combat_manager.run_time within a window.
## Works on dead entities (tag timestamp set BEFORE death processing in entity.take_damage).
## First consumer: Thunder Harvest (on_kill where victim was hit by "ThunderBlade" within 3s).

@export var tag: String = ""       ## Required ability tag on the hit that marked the target
@export var window: float = 3.0   ## Maximum seconds since the hit (inclusive)
