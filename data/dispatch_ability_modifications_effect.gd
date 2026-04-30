class_name DispatchAbilityModificationsEffect
extends Resource
## Effect sub-resource: execute the registered ability_modifications of a
## specified ability on the target, using the current source's context. Lets
## a trigger listener reuse existing talent overlays (chains, HoTs, VFX) on a
## "free cast" without going through the ability pipeline (no cooldown, no
## animation, no priority checks).
##
## First consumer: Cleric Angelic Intervention — the emergency free Healing
## Words fires Overflowing Light's chain and Blessed Touch's HoT via this
## effect by dispatching `cleric_healing_words` modifications on the rescued
## ally. Future talents that want "on X, also fire ability Y's modifications"
## reuse the same effect without new code.

@export var ability_id: String = ""
