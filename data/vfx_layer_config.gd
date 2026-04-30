class_name VfxLayerConfig
extends Resource
## Configures one layer of a visual effect. Ability VFX and status VFX
## are defined as arrays of these — multi-layer effects (front/back) use
## multiple entries. The VFX handler reads these at runtime via VfxEffect.create().

@export var sprite_frames: SpriteFrames
@export var animation: String = ""
@export var z_index: int = 0
@export var offset: Vector2 = Vector2.ZERO
@export var scale: Vector2 = Vector2.ONE

## Optional intro animation played before looping. On finished, transitions to
## the main loop animation. Leave empty for immediate loop (backward compatible).
@export var start_animation: String = ""

## Optional outro animation played when the effect is stopped (status expires/cleansed).
## On finished, the node queue_frees. Leave empty for immediate removal.
@export var end_animation: String = ""
