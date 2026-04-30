class_name GrantAbilityChargeEffect
extends Resource
## Effect sub-resource: grant the EFFECT SOURCE a stored charge of the named
## ability, capped at `max_charges`. A charge lets the owner fire the ability
## while its normal gates (cooldown, Focus gate, any ConditionStackCount, any
## resource cost) would block it. Charges are consumed when the ability would
## NOT have fired normally, so natural-ready casts do not drain the bank.
##
## Operates on source, not target — charges belong to the caster's ability
## component. Mirrors RefundCooldownEffect's source-side shape. For trigger
## listeners the bearer IS the effect source, so callers don't need
## target_self to redirect.
##
## No-ops when source is invalid, has no AbilityComponent, or doesn't own an
## ability with the given id. Re-grants at cap are silent no-ops (no spillover).
##
## First consumer: Ranger Marked For Death (Deadeye T3 — ally kills on Marked
## priority targets bank a free Crippling Shot charge, max 2).

@export var ability_id: String = ""
@export var max_charges: int = 1
