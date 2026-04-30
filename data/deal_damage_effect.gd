class_name DealDamageEffect
extends Resource
## Effect sub-resource: deal damage to targets.

@export var damage_type: String = "Physical"    ## "Physical", "Lightning", "Holy", etc.
@export var scaling_attribute: String = "Str"   ## "Str", "Int", etc.
@export var scaling_coefficient: float = 1.0
@export var base_damage: float = 0.0
@export var missing_hp_damage_scaling: float = 0.0  ## Multiplier applied at DamageCalculator Step 1.5 — raw *= 1.0 + missing_hp_fraction * scaling. 0.0 = disabled (default). 2.0 = +2% damage per 1% missing HP (×2.0 at 50% HP, ×2.8 at 10% HP). Per-hit dynamic — reads target.health at dispatch time, so consecutive hits within the same cast see the prior hit's HP loss. First consumer: Ranger Executioner (Deadeye T3).
@export var flat_bonus_damage: float = 0.0  ## Post-pipeline raw bonus added to final damage after crit. Bypasses resist/vuln/crit/block on the bonus portion — consumers are expected to pass an already-processed number. 0.0 = disabled. Callers that need a per-cast bonus (e.g. banked damage from a status) build an ephemeral DealDamageEffect with this set at dispatch time. First consumer: SpawnBankedShotEffect (Ranger Crown Shot).
