class_name ConditionTakingDamage
extends Resource
## Condition: entity has taken damage within a time window.
## Optional tag filter: only count hits from abilities with that tag (e.g. "Melee").

@export var window: float = 3.0  ## Seconds — condition is true if hit within this window
@export var required_tag: String = ""  ## If set, only hits from abilities with this tag count
