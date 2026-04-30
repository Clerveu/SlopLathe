class_name ExecuteEffect
extends Resource
## Effect sub-resource: deal raw damage equal to the target's remaining pool
## (current_hp + shield_hp), attributed to the source. Bypasses the damage
## pipeline entirely — no DR, no block, no dodge, no crit, no resistance, no
## conversion. The hit carries `ability = null` so ability-gated listeners
## (Pin, Heavy Draw bonus Mark, Deathroll consume, etc.) don't fire on the
## execute; the on_hit_dealt / on_hit_received / on_death / on_kill signals
## still emit normally so attribution, on-kill triggers (Deathroll, Waste
## Not), and combat tracking credit the source accurately.
##
## Targets in execute range that have already died between trigger firing and
## dispatch (same-frame race) early-return — `target_alive` guard catches the
## on_crit-fires-after-lethal-crit case where the original hit killed before
## the execute listener evaluated.
##
## Shields are drained by the execute via `current_hp + shield_hp`; a shielded
## target at 10% HP with 50% max_hp worth of shield takes HP + shield in raw
## attribution, not just the HP portion. Prevents under-crediting the source
## and prevents the execute from failing on a shielded execute-range target.
##
## First consumer: Ranger Fusillade (Quickdraw capstone — AA crits against
## non-elite, non-boss targets below 25% HP execute instantly during the 8s
## window, gated by a 1s per-Ranger ICD).

@export var damage_type: String = "Physical"
@export var attribution_tag: String = ""
