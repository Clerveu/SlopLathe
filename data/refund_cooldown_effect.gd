class_name RefundCooldownEffect
extends Resource
## Effect sub-resource: subtract `seconds` from the EFFECT SOURCE's
## cooldown_remaining on the named ability. Clamped at 0 (cannot drive the
## cooldown below ready). No-op when the source is invalid, has no
## AbilityComponent, or doesn't own an ability with the given id.
##
## Operates on source, not target — cooldowns belong to the caster. The
## passed-in target is irrelevant at dispatch time. For trigger listeners the
## bearer IS the effect source, so the refund targets the bearer naturally —
## callers don't set target_self to redirect.
##
## Composes cleanly with existing CDR primitives: subtraction is applied to
## the live cooldown_remaining (already post-CDR from start_cooldown), so
## flat refunds are independent of percent CDR and don't interact with the
## flat_reduce path (which applies to base cooldown at start_cooldown time).
##
## Empty ability_id is the "all slots" mode — refunds every skill slot on
## the source's ability_component. Used when a talent refunds "all
## cooldowns" in bulk (Fusillade's on-crit CD refund during the 8s window).
## The AA timer lives on BehaviorComponent and is deliberately out of reach
## — "all abilities" means all skill slots, not the AA cadence.
##
## First consumer (single-ability): Ranger Waste Not (Deadeye T2 — on-kill
## of a priority target refunds 6s of Crippling Shot's cooldown).
## First consumer (all-slots): Ranger Fusillade (Quickdraw capstone —
## crits during the 8s window refund 1s across every skill slot).

@export var ability_id: String = ""
@export var seconds: float = 0.0
