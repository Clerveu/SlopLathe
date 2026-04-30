class_name TriggerConditionEventEntityFaction
extends Resource
## Trigger condition: checks if a specific entity in the event belongs to a faction
## relative to the entity bearing the trigger.
##
## entity_role: which event entity to check — "source" or "target"
##   (on_kill: source = killer, target = victim)
## faction: "enemy" (opposite faction from bearer) or "ally" (same faction as bearer)
##
## First consumer: Dark Pact on_kill → Soul generation (victim must be enemy).

@export var entity_role: String = "target"  ## "source" or "target"
@export var faction: String = "enemy"       ## "enemy" or "ally" (relative to trigger bearer)
