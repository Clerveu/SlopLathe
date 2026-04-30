class_name FactionCleanseEffect
extends Resource
## Effect sub-resource: apply a cleanse sweep to every living entity of a
## faction (relative to the effect source). Mirrors CleanseEffect's shape —
## `count` and `target_type` are forwarded to StatusEffectComponent.cleanse
## on each affected entity — but the pool comes from the spatial grid rather
## than the ability's primary targeting. Same "targetless global dispatch"
## pattern as SummonEffect / GroundZoneEffect / AreaDamageEffect.
##
## Fires per-entity on_cleanse emissions — any listener watching for cleanse
## side-effects (Purifying Fire, Retribution, Righteous Wrath) fires naturally
## for each removal, same as any other cleanse path.
##
## First consumer: Cleric Divine Purge (Exorcist capstone — strip 1 positive
## status from every enemy on the field). Any future "mass purify" / "mass
## dispel" / "strip all enemy buffs in zone" mechanic reuses the same effect.

@export var faction: String = "enemy"           ## "enemy" or "ally" (relative to source's faction)
@export var count: int = 1                       ## -1 = all matching statuses per entity
@export var target_type: String = "positive"    ## "positive", "negative", "any"
