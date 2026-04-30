class_name RedistributeCleansedStatusEffect
extends Resource
## Effect sub-resource: dispatched from on_cleanse trigger listeners to re-apply
## the cleansed status, at a multiple of its cleanse-time stack count, to all
## enemies-of-bearer within a radius of the cleanse event's target position.
##
## Reads definition + stacks from the on_cleanse payload Dictionary (the payload
## is built by TriggerComponent._on_cleanse with the cleansed ActiveStatus's
## snapshot captured before removal — see StatusEffectComponent.cleanse and
## force_remove_status). No-ops when the payload lacks the keys (effect
## dispatched outside an on_cleanse context) or when the cleansed definition is
## null (defensive).
##
## "Enemies" = opposite faction to the trigger bearer (the talent owner), not
## opposite faction to the cleanse target. Handles the friendly-fire case where
## a WD debuff somehow lives on an ally — the redistribution still targets
## enemies of the WD.
##
## First consumer: Witch Doctor Backfire Hex (Afflictor T2) — cleansed WD
## debuff re-applies at 2× stacks (clamped to max_stacks) to every enemy within
## 50px of the cleanse target.

@export var stack_multiplier: float = 2.0  ## Applied stacks = ceil(cleansed_stacks × multiplier), clamped to status max_stacks
@export var radius: float = 50.0           ## Redistribution radius (pixels) around the cleanse target's position
