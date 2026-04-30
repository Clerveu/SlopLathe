class_name OverflowChainEffect
extends Resource
## Effect sub-resource: overkill damage chains to nearby unhit enemies.
## After base ability effects resolve, iterates dead targets, finds nearest
## unhit enemy within range, deals overkill as raw damage, chains if that
## also overkills. Heals source for a percentage of total damage dealt
## (base ability + overflow).

@export var max_chains: int = 2           ## Max additional targets from overflow (beyond base)
@export var heal_percent: float = 0.0     ## Heal source for this % of total damage dealt (0 = no heal)
@export var damage_type: String = "Physical"  ## Damage type for overflow HitData
@export var max_range: float = 45.0       ## Range from source to find overflow targets
