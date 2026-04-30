class_name SpawnProjectilesEffect
extends Resource
## Effect sub-resource: spawn projectiles that deliver effects on contact.
## Lives in an ability's effects array alongside DealDamageEffect, ApplyStatusEffectData, etc.

@export var projectile: ProjectileConfig         ## What each projectile is
@export var spawn_pattern: String = "radial"     ## "radial", "at_targets", "aimed_single", "fountain"
@export var count: int = 8                       ## For radial patterns (ignored by aimed_single)
@export var spawn_offset: Vector2 = Vector2.ZERO ## Offset from entity center

# --- Fountain pattern parameters ---
@export var fountain_radius: float = 75.0        ## Max landing distance from source (center-weighted gaussian)
@export var fountain_arc_min: float = 80.0       ## Min arc peak height
@export var fountain_arc_max: float = 110.0      ## Max arc peak height

# --- Per-projectile variants (aimed_single pattern only) ---
## When non-empty and spawn_pattern == "aimed_single", emits one projectile per variant
## using the aim direction resolved once from the base spawn_offset. Each variant can
## override per-instance damage, splash radius, visual scale, and spawn offset delta.
## Concatenated with any AbilityModification.projectile_variants_overlay registered
## on the source's AbilityComponent for this ability_id. Empty = single-projectile
## path (current behavior). Ignored by radial / at_targets / fountain patterns.
@export var projectile_variants: Array[ProjectileVariant] = []
