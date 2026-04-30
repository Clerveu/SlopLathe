class_name ProjectileConfig
extends Resource
## Configures how a single projectile behaves. Pure data.
## Motion type, speed, hit detection, on-hit effects, and visuals.

# --- Motion ---
@export var motion_type: String = "directional"  ## "directional", "aimed", "homing"
@export var speed: float = 80.0                  ## Pixels/sec
@export var max_range: float = 0.0               ## Max travel distance (0 = screen bounds)
@export var arc_height: float = 0.0              ## Parabolic arc peak height in pixels (0 = straight line)
@export var no_flight_collision: bool = false     ## Skip hit detection during arc flight (damage only on landing)

# --- Visual ---
@export var sprite_frames: SpriteFrames
@export var use_directional_anims: bool = true   ## true → pick anim from direction ("n","ne","e"...)
@export var animation: String = ""               ## Single anim name if not directional
@export var visual_scale: Vector2 = Vector2.ONE

# --- Hit Detection ---
@export var hit_radius: float = 8.0              ## Distance at which a target is "hit"

# --- On-Hit Behavior ---
@export var pierce_count: int = 0                ## 0 = destroy on first hit, -1 = infinite
@export var on_hit_effects: Array = [] ## DealDamageEffect, ApplyStatusEffectData, etc.

# --- Impact VFX (optional) ---
@export var impact_sprite_frames: SpriteFrames   ## One-shot VfxEffect on hit (null = none)
@export var impact_animation: String = ""
@export var impact_visual_scale: Vector2 = Vector2.ONE  ## Scale applied to the impact VfxEffect node (mirrors visual_scale on the projectile sprite)

# --- Impact AOE (splash damage) ---
@export var impact_aoe_radius: float = 0.0       ## Splash radius around impact (0 = no splash)
@export var impact_aoe_effects: Array = []        ## Effects on splash targets (excluding primary hit target)
