class_name ParticleVfxLayerConfig
extends Resource
## Placement wrapper for a ParticleFxPreset. Lives as a sibling of VfxLayerConfig
## inside any `vfx_layers` / `target_vfx_layers` / `on_stack_vfx_layers` array —
## VfxManager branches on type. The preset is the shared visual definition;
## this config only carries per-use placement metadata.

@export var preset: ParticleFxPreset
@export var offset: Vector2 = Vector2.ZERO
@export var z_index: int = 0
@export var follow_entity: bool = true
