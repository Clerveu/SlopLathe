class_name VfxEffect
extends AnimatedSprite2D
## Generic visual effect node. Plays a SpriteFrames animation, then either
## auto-frees (one-shot) or loops until stop() is called.
##
## Three-phase lifecycle (start → loop → end):
##   Set start_animation and/or end_animation on VfxLayerConfig.
##   - On create: plays start_animation first, then transitions to loop.
##   - On stop_effect(): plays end_animation, then queue_frees.
##   Either phase is optional — omit for immediate loop / immediate removal.

## If true, the animation loops until stop_effect() is called.
## If false, the animation plays once and the node queue_frees itself.
var looping: bool = false

## Optional intro/outro animation names for three-phase lifecycle.
var _start_animation: String = ""
var _end_animation: String = ""
var _loop_animation: String = ""
var _playing_end: bool = false


static func create(p_sprite_frames: SpriteFrames, p_animation: String,
		p_looping: bool = false, p_z_index: int = 0,
		p_offset: Vector2 = Vector2.ZERO,
		p_scale: Vector2 = Vector2.ONE) -> VfxEffect:
	var fx := VfxEffect.new()
	fx.sprite_frames = p_sprite_frames
	fx.looping = p_looping
	fx.z_index = p_z_index
	fx.position = p_offset
	fx.scale = p_scale
	fx.centered = true
	# Store animation name to play in _ready
	fx.set_meta("_start_anim", p_animation)
	return fx


static func create_phased(p_sprite_frames: SpriteFrames,
		p_loop_animation: String, p_start_animation: String,
		p_end_animation: String, p_z_index: int = 0,
		p_offset: Vector2 = Vector2.ZERO,
		p_scale: Vector2 = Vector2.ONE) -> VfxEffect:
	## Creates a three-phase VFX (start → loop → end).
	var fx := VfxEffect.new()
	fx.sprite_frames = p_sprite_frames
	fx.looping = true
	fx.z_index = p_z_index
	fx.position = p_offset
	fx.scale = p_scale
	fx.centered = true
	fx._loop_animation = p_loop_animation
	fx._start_animation = p_start_animation
	fx._end_animation = p_end_animation
	# Determine initial animation
	if p_start_animation != "" and p_sprite_frames.has_animation(p_start_animation):
		fx.set_meta("_start_anim", p_start_animation)
	else:
		fx.set_meta("_start_anim", p_loop_animation)
	return fx


func _ready() -> void:
	animation_finished.connect(_on_finished)
	var anim_name: String = get_meta("_start_anim", "")
	if anim_name == "" or not sprite_frames:
		push_error("VfxEffect: missing animation name or sprite_frames")
		queue_free()
		return
	if not sprite_frames.has_animation(anim_name):
		push_error("VfxEffect: animation '%s' not found in sprite_frames (available: %s)"
				% [anim_name, sprite_frames.get_animation_names()])
		queue_free()
		return
	play(anim_name)


func stop_effect() -> void:
	## Stops a looping effect. If an end animation exists, plays it first.
	if _end_animation != "" and sprite_frames and sprite_frames.has_animation(_end_animation):
		_playing_end = true
		play(_end_animation)
	else:
		stop()
		queue_free()


func _on_finished() -> void:
	if _playing_end:
		# End animation done — remove
		queue_free()
		return

	if _start_animation != "" and animation == _start_animation:
		# Start animation done — transition to loop
		if _loop_animation != "" and sprite_frames.has_animation(_loop_animation):
			play(_loop_animation)
			return

	if not looping:
		queue_free()
