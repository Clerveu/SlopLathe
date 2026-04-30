class_name SpawnBankedShotEffect
extends Resource
## Effect sub-resource: spawn an aimed projectile whose damage stamps a
## post-pipeline flat bonus read from a status's accumulated bank.
##
## Dispatched from status on_expire_effects (or any context where the named
## status is still active on the dispatch target). At dispatch time, reads
## target.status_effect_component.get_accumulated_bank(bank_status_id) and
## folds the payload into an ephemeral DealDamageEffect's flat_bonus_damage
## before spawning the projectile — so the finishing shot's base portion runs
## through the full damage pipeline (vulnerability, crit, Mark/MfD amps) while
## the banked portion lands raw.
##
## First consumer: Ranger Crown Shot (Deadeye capstone). The paint status
## banks 50% of the Ranger's Physical damage + 25% of her allies' Physical
## damage dealt to the painted target over a 2s window, then on expire this
## effect fires Str × 5.0 base + banked payload as one unified shot.
##
## If the painted target dies before the status expires, on_expire_effects
## don't fire (only natural expiry hits that path) — the payload is simply
## lost, matching the spec's "target dies → payload lost" rule without any
## special handling here.

@export var projectile: ProjectileConfig   ## Shared template. Mutated? No — we duplicate per dispatch.
@export var bank_status_id: String = ""    ## Status to read the accumulated bank from (on `target`)
@export var base_damage_effect: DealDamageEffect  ## Base shot definition (Str × 5.0 etc.). flat_bonus_damage is ignored here — overwritten per dispatch.
