class_name SpreadStatusEffect
extends Resource
## Effect sub-resource: scan a faction for bearers of a stacking status with
## enough stacks, and spread the status to each bearer's nearby same-faction
## neighbors. Same "targetless / self-resolving pool" shape as FactionCleanseEffect
## and SummonEffect — the effect resolves its own pool from the spatial grid and
## ignores the ability's per-target iteration.
##
## Dispatched with `source` = the entity whose tick/ability fires the spread
## (typically a passive-status bearer, e.g. the Wizard). That source is then
## threaded as the applier for the spread stacks, so DOT scaling continues to
## key off the original caster's attributes.
##
## First consumer: Wizard Spreading Flames (Pyromancer T1 — bearers with 5+
## Burn stacks spread 1 stack every 2s to same-faction neighbors within 25px
## with fewer stacks). Any future "self-propagating stacking debuff" mechanic
## — poison clouds, plague spread, cold spread — reuses the same effect.

@export var status: StatusEffectDefinition       ## Status to scan for AND apply (same id)
@export var bearer_faction: String = "enemy"      ## "enemy" or "ally" relative to effect source's faction — which pool to scan
@export var min_bearer_stacks: int = 1            ## Bearers need at least this many stacks to spread
@export var spread_stacks: int = 1                ## Stacks applied to each qualifying neighbor
@export var spread_radius: float = 25.0           ## Radius around each bearer for neighbor search (pixels)
@export var require_neighbor_below_bearer: bool = true  ## When true, neighbors must have fewer stacks than the bearer to be eligible
