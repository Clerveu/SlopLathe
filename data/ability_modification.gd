class_name AbilityModification
extends Resource
## Declares effects to add to an existing ability's execution.
## The one net-new primitive for the talent system.
##
## When the target ability fires, these additional effects execute through the
## same EffectDispatcher pipeline as the ability's base effects, on the same targets.

@export var target_ability_id: String = ""           ## Which ability to modify
@export var additional_effects: Array[Resource] = [] ## Effect sub-resources to include
@export var on_displacement_arrival: bool = false    ## When true, effects fire at displacement arrival instead of hit frame
@export var cooldown_flat_reduction: float = 0.0     ## Flat seconds subtracted from ability's base cooldown (e.g. 2.0 = 2s CDR)
@export var replacement_ability: AbilityDefinition = null  ## When non-null, the existing ability with target_ability_id is wholly replaced. Used for talents that fundamentally transform a base ability (Wizard Kindle: Fire Bolt → Burn applicator; future Heavy Ordnance, Concentrated Blast). Replacement should keep the same ability_id so attribution and downstream references stay coherent.
@export var projectile_variants_overlay: Array[ProjectileVariant] = []  ## When non-empty, overlays per-projectile variants onto the current ability's aimed_single SpawnProjectilesEffect at cast time. Reads whatever SpawnProjectilesEffect is live after any prior replacement_ability modification has already applied — do NOT use with replacement_ability on the same modification entry (use a separate AbilityModification). Concatenated with the effect's own projectile_variants list. First consumer: Wizard Barrage.
@export var targeting_override: TargetingRule = null  ## When non-null, replaces the target ability's TargetingRule at resolve time (BehaviorComponent consults AbilityComponent.get_effective_targeting). The original AbilityDefinition is untouched — the override lives on the entity's AbilityComponent so different entities with the same class can have different talent-driven targeting. First consumer: Ranger Hunter's Priority (redirects all Ranger abilities to priority-tiered targeting).
@export var projectile_arc_height: float = -1.0  ## When >= 0, patches ProjectileConfig.arc_height on every SpawnProjectilesEffect inside the live ability (including nested choreography phase effects). Applied after all replacement_ability substitutions across all talents — composes with other talents' replacements (Heavy Draw's heavy Steady Shot still arcs under Hunter's Priority). Patch runs on a per-entity duplicate of the AbilityDefinition so shared Resources aren't mutated.
@export var projectile_no_flight_collision: bool = false  ## When true, patches ProjectileConfig.no_flight_collision on every SpawnProjectilesEffect inside the live ability. Paired with projectile_arc_height for lob-over-intervening-enemies behavior — existing Firestorm precedent (no_flight_collision + arc_height). Independent of projectile_arc_height so either can be applied alone. First consumer: Ranger Hunter's Priority (longbow-sniper arcing).
