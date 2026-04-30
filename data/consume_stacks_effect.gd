class_name ConsumeStacksEffect
extends Resource
## Effect sub-resource: consume stacks of a status.
## Executes per_stack_effects once per stack consumed (for scaling burst damage).
## Triggers the status's on_consume_effects hook and fires EventBus.on_status_consumed.
##
## Default routing is "consume from `target`" (Killshot consumes Mark on the enemy
## it just hit). Set `consume_from_bearer = true` to route the consume to the
## `fallback_source` of the dispatch context instead — in status lifecycle hooks
## (`on_hit_dealt_effects`, `aura_tick_effects`, etc.) the fallback_source is the
## entity *bearing* the status, so this lets a status consume itself when its own
## lifecycle hook fires. First bearer-route consumer: Cleric Retribution
## (retribution_empowered fires its bonus damage on the cleansed ally's next hit,
## then consumes itself in the same on_hit_dealt pass).

@export var status_id: String = ""
@export var stacks_to_consume: int = -1  ## -1 = all, positive = consume up to N
@export var per_stack_effects: Array = []  ## Effects to execute per stack consumed
@export var consume_from_bearer: bool = false  ## When true, consume from `fallback_source` instead of `target` — used by self-consuming statuses inside their own lifecycle hooks
