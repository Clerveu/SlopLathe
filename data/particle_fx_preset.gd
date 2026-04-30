class_name ParticleFxPreset
extends Resource
## Shared visual definition for a pooled CPUParticles2D emitter. Authored once,
## referenced by many ParticleVfxLayerConfig instances across abilities and statuses.
## ParticleManager._apply_preset() maps these fields to CPUParticles2D API.

@export var preset_id: String = ""                    ## For debug attribution
@export var texture: Texture2D                         ## Particle sprite (usually 2x2 pixel.png)
@export var amount: int = 8                            ## Max simultaneous particles
@export var lifetime: float = 0.5                      ## Seconds per particle
@export var one_shot: bool = false                     ## true = burst-and-finish
@export var explosiveness: float = 0.0                 ## 0 = steady, 1 = all at once
@export var emission_shape: int = 0                    ## CPUParticles2D.EMISSION_SHAPE_*
@export var emission_box_extents: Vector3 = Vector3.ZERO
@export var emission_sphere_radius: float = 0.0
@export var direction: Vector3 = Vector3(0, -1, 0)
@export var spread: float = 45.0                       ## Degrees
@export var initial_velocity_min: float = 0.0
@export var initial_velocity_max: float = 0.0
@export var gravity: Vector3 = Vector3.ZERO
@export var angular_velocity_min: float = 0.0
@export var angular_velocity_max: float = 0.0
@export var scale_amount_min: float = 1.0
@export var scale_amount_max: float = 1.0
@export var color_ramp: Gradient
@export var fixed_fps: int = 10                       ## 0 = engine fps. Project default 10 for chunky pixel-art motion — override per-preset if needed
@export var fract_delta: bool = false                 ## true = interpolate between fixed_fps steps, false = hard stepped snap (project default)
