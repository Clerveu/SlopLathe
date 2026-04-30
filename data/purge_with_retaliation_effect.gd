class_name PurgeWithRetaliationEffect
extends Resource
## Effect sub-resource: cleanse every negative status from the target and deal
## typed damage per cleansed status to its original applier (nearest-enemy
## fallback when the applier is dead/freed). Each force_remove_status call
## emits `on_cleanse`, so any other on_cleanse listener the source has
## registered (Cleric Purifying Fire, Hallowed Ground, Retribution, Righteous
## Wrath) still fires per cleansed debuff — the damage fired from this effect
## is IN ADDITION to those, matching the Divine Purge spec ("Purifying Fire
## fires its Holy damage in addition to the Purge's per-debuff damage").
##
## Packaged as a single effect rather than a temporary listener-bearing self
## status because the "fires on every on_cleanse during a short window" trick
## is scope-fragile — any overlapping Sacred Aegis / Absolution / Consecrated
## Spirit cleanse in the same tick would double-dip the retaliation. The
## composite path isolates the sweep to the exact statuses cleansed by this
## effect, in this pass. First consumer: Cleric Divine Purge (Exorcist
## capstone — Int × 0.4 Holy per debuff cleansed from each ally).

@export var damage_type: String = "Holy"
@export var scaling_attribute: String = "Int"
@export var scaling_coefficient: float = 0.4
@export var base_damage: float = 1.0
