class_name ConditionCorpseExists
extends Resource
## Ability condition: at least one corpse of the specified faction exists.
## Faction is relative to the ability owner ("ally" = same faction, "enemy" = opposite).

@export var faction: String = "ally"  ## "ally" or "enemy"
