class_name StatusEffectDefinition
extends Resource
## Defines a status effect type. Applied via StatusEffectComponent at runtime.
## Modifiers are registered while active, scaled by current stacks.

@export var status_id: String = ""                      ## "Burn", "SwordGuard", etc.
@export var tags: Array[String] = []                    ## For immunity checks (Negate modifier)
@export var is_positive: bool = true                    ## Buff vs debuff (for cleanse targeting)
@export var max_stacks: int = 1                         ## Per-type cap
@export var base_duration: float = 5.0                  ## Seconds (-1 for permanent/until consumed)
@export var tick_interval: float = 0.0                  ## Periodic effect interval (0 = no ticking)
@export var tick_effects: Array[Resource] = []           ## Effects fired each tick
@export var tick_scales_with_stacks: bool = false        ## When true, tick_effects' power_multiplier is multiplied by current stacks (per-stack DOT scaling). First consumer: Wizard Burn (5 stacks × Int × 0.15/s).
@export var on_apply_effects: Array[Resource] = []       ## Effects on first application
@export var on_expire_effects: Array[Resource] = []      ## Effects when duration ends naturally
@export var on_consume_effects: Array[Resource] = []     ## Effects when consumed by another ability
@export var on_hit_received_effects: Array[Resource] = [] ## Effects when entity is hit while this status is active
@export var on_hit_received_damage_filter: Array[String] = [] ## If non-empty, on_hit_received_effects only fire for these damage types
@export var on_hit_dealt_effects: Array[Resource] = []    ## Effects when status-bearing entity deals a hit
@export var modifiers: Array[Resource] = []              ## ModifierDefinitions applied while active
@export var disables_actions: bool = false               ## True = entity cannot act or move (Stun, Freeze, etc.)
@export var disables_movement: bool = false              ## True = entity cannot move but can still act (Root)
@export var disables_abilities: bool = false             ## True = entity cannot cast abilities but can still AA and move (Silence). First consumer: Witch Doctor Silence of the Grave.
@export var grants_invulnerability: bool = false          ## True = bearer takes zero damage while active (CC still applies). Parallels disables_* counter pattern. First consumer: Witch Doctor Empowered Revive (5s post-revive buff).
@export var movement_override: String = ""               ## Movement behavior override while active (e.g. "flee_right")
@export var curse_damage_type: String = ""                 ## Non-empty = healing inversion curse (damage type when healing is inverted)
@export var prevents_death: bool = false                   ## When true, prevents lethal damage (HP set to 1 instead of death)
@export var on_death_prevented_effects: Array[Resource] = [] ## Effects fired when this status prevents death (status consumed after)
@export var duration_refresh_mode: String = "overwrite"    ## "overwrite" = always set new duration; "max" = keep longer remaining
@export var shield_on_hit_absorbed_percent: float = 0.0    ## > 0 = gain Shield equal to this % of DR-mitigated damage per hit
@export var shield_cap_percent_max_hp: float = 0.0         ## > 0 = total Shield from this effect capped at this % of max HP
@export var aura_radius: float = 0.0                      ## > 0 = this status is an aura; proximity query range in pixels
@export var aura_target_faction: String = ""               ## "enemy" or "ally" — which faction aura affects
@export var aura_tick_effects: Array[Resource] = []        ## Effects dispatched to each entity in range per tick
@export var vfx_layers: Array = []                       ## VfxLayerConfig entries for looping status VFX
@export var on_stack_vfx_layers: Array = []              ## VfxLayerConfig entries for one-shot VFX on every application/stack
@export var grants_taunt: bool = false                    ## True = enemies within taunt_radius prioritize targeting this entity
@export var taunt_radius: float = 0.0                     ## Range for taunt targeting override (pixels)
@export var thorns_percent: float = 0.0                   ## > 0 = reflect this fraction of damage received back to attacker
@export var thorns_flat_scaling_attribute: String = ""     ## Attribute for flat thorns (e.g. "Str") — computed as attr × coefficient
@export var thorns_flat_scaling_coefficient: float = 0.0   ## Scaling multiplier for flat thorns (e.g. 0.15 = Str × 0.15 per hit)
@export var targeting_count_threshold: int = 0            ## > 0 = check how many enemies target bearer; if >= this, apply targeting_count_status
@export var targeting_count_status: Resource = null        ## StatusEffectDefinition applied to self when targeting_count_threshold met
@export var trigger_listeners: Array[Resource] = []      ## TriggerListenerDefinitions registered while status is active
@export var freezes_status_ids: Array[String] = []       ## Status IDs whose duration is paused while this status is active
@export var max_extensions: int = 0                       ## > 0 = cap how many times this status can be extended (0 = unlimited)
@export var echo_source: EchoSourceConfig = null           ## Non-null = this status registers an echo source on the bearer while active (Salvation's "echo")
@export var debuff_absorber_chance: float = 0.0          ## > 0 = bearer of this status has this chance to absorb debuffs applied to allies in the same faction. Queried by StatusEffectComponent.apply_status when a non-positive status is being applied to an ally — first proc redirects the application to the absorber. Recursion-guarded via apply_status's `intercepted` parameter (only one redirect per application). First consumer: Cleric Martyr's Resolve (Exorcist T3 — 30%).
## Damage banking: notify_hit_received tallies a fraction of each incoming hit onto ActiveStatus._accumulated_bank, keyed by source relationship.
## Payload is read at dispatch time by SpawnBankedShotEffect (source.status_effect_component.get_accumulated_bank(status_id) on the bearer — hook the
## lookup on `target` for on_expire dispatches since target IS the bearer). bank_damage_filter (empty = any type) gates by hit_data.damage_type.
## First consumer: Ranger Crown Shot (Deadeye capstone — 50% of painter's Physical + 25% of painter-faction allies' Physical, resolved as flat raw
## bonus on the finishing shot).
@export var bank_damage_from_source_percent: float = 0.0    ## > 0 = bank this fraction of hits the status's SOURCE lands on the bearer
@export var bank_damage_from_source_allies_percent: float = 0.0  ## > 0 = bank this fraction of hits from entities sharing the source's faction (excluding the source itself)
@export var bank_damage_filter: Array[String] = []          ## When non-empty, only these damage types contribute to the bank ("Physical", "Fire", ...)
## Stepped-down fallback applied to the target when this status would be fully
## negated (tag-negate, polarity-negate, or per-status-id immunity) AND the
## source carries a `stepdown_pierce` modifier keyed by any of this status's
## tags. Null = no stepdown (original resists cleanly — existing behavior).
## Chains through apply_status recursively: the stepdown's own resist_stepdown
## (when set) engages if the stepdown itself is immune. Terminal stepdowns set
## resist_stepdown = null so multi-axis immunity degrades finite-depth.
## First consumer: Witch Doctor Inescapable (Puppeteer capstone — Stun → Root,
## Root → Slow, Fear → Silence, Silence → Cooldown Drag, 50% potency for aura
## and aftershock stepdowns).
@export var resist_stepdown: StatusEffectDefinition = null
