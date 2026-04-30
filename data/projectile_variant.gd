class_name ProjectileVariant
extends Resource
## One projectile instance in a multi-projectile spawn (aimed_single + variants).
## All multipliers default to 1.0 so a variant carrying only an offset is legal.
##
## Consumed by SpawnProjectilesEffect.projectile_variants (static authorship) and
## AbilityModification.projectile_variants_overlay (talent overlay). Both paths
## concatenate onto the same per-cast variant list.

@export var offset_delta: Vector2 = Vector2.ZERO       ## Source-local pixels, added to SpawnProjectilesEffect.spawn_offset for this projectile's origin. Use for same-direction fans from different spawn points.
@export var angle_offset_degrees: float = 0.0          ## Degrees rotated off the shared aim direction for this projectile. Positive = clockwise in screen space. Use for spread-fire fans where projectiles share a spawn point but fly at different angles.
@export var damage_multiplier: float = 1.0             ## Scales every damage-producing effect this projectile dispatches (on_hit + impact_aoe); threaded through as EffectDispatcher.power_multiplier
@export var splash_radius_multiplier: float = 1.0      ## Scales ProjectileConfig.impact_aoe_radius for this projectile instance only
@export var visual_scale_multiplier: float = 1.0       ## Multiplies both projectile visual_scale and impact_visual_scale for this instance only
