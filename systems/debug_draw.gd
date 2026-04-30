class_name DebugDraw
extends Node2D
## Debug visualization for targeting areas and ability hitboxes.
## Child of combat_manager. Toggle globally with `enabled`, or per-ability
## by adding ability_id strings to `ability_filter`.
##
## Usage:
##   debug_draw.enabled = true                          # master switch
##   debug_draw.ability_filter = ["wizard_fire_torrent"] # only show these (empty = show all)

var enabled: bool = false
var ability_filter: Array[String] = []  ## Empty = show all abilities when enabled

var _active_shapes: Array = []

const SHAPE_DURATION := 1.0
const FILL_ALPHA := 0.15
const OUTLINE_ALPHA := 0.6
const OUTLINE_WIDTH := 1.0


func _ready() -> void:
	z_index = 100
	EventBus.on_ability_used.connect(_on_ability_used)


func _on_ability_used(entity: Node2D, ability: AbilityDefinition) -> void:
	if not enabled or not ability.targeting:
		return
	if not ability_filter.is_empty() and not ability_filter.has(ability.ability_id):
		return
	# Draw hit_targeting (wider effect area) first so trigger area draws on top
	if ability.hit_targeting and ability.hit_targeting.max_range > 0.0:
		_active_shapes.append({
			"type": ability.hit_targeting.type,
			"position": entity.position,
			"max_range": ability.hit_targeting.max_range,
			"height": ability.hit_targeting.height,
			"facing_right": not entity.sprite.flip_h,
			"timer": SHAPE_DURATION,
			"is_hit_area": true,
		})
	var rule: TargetingRule = ability.targeting
	if rule.max_range <= 0.0 and rule.type != "frontal_rectangle":
		return
	_active_shapes.append({
		"type": rule.type,
		"position": entity.position,
		"max_range": rule.max_range,
		"height": rule.height,
		"facing_right": not entity.sprite.flip_h,
		"timer": SHAPE_DURATION,
		"is_hit_area": false,
	})
	queue_redraw()


func draw_impact_aoe(pos: Vector2, radius: float, ability_id: String = "") -> void:
	## Draw AOE impact circle at a world position. Called by ProjectileManager on splash impact.
	if not enabled:
		return
	if not ability_filter.is_empty() and not ability_id.is_empty() and not ability_filter.has(ability_id):
		return
	_active_shapes.append({
		"type": "impact_aoe",
		"position": pos,
		"max_range": radius,
		"timer": SHAPE_DURATION,
	})
	queue_redraw()


func _process(delta: float) -> void:
	if _active_shapes.is_empty():
		return
	for i in range(_active_shapes.size() - 1, -1, -1):
		_active_shapes[i].timer -= delta
		if _active_shapes[i].timer <= 0.0:
			_active_shapes.remove_at(i)
	queue_redraw()


func _draw() -> void:
	if not enabled or _active_shapes.is_empty():
		return
	for shape in _active_shapes:
		var alpha_mult: float = clampf(shape.timer / SHAPE_DURATION, 0.0, 1.0)
		var fill: Color
		var outline: Color
		if shape.get("is_hit_area", false):
			# Hit targeting (wider effect area) — blue
			fill = Color(0.2, 0.4, 1.0, FILL_ALPHA * alpha_mult)
			outline = Color(0.2, 0.4, 1.0, OUTLINE_ALPHA * alpha_mult)
		else:
			# Trigger targeting — red
			fill = Color(1.0, 0.2, 0.2, FILL_ALPHA * alpha_mult)
			outline = Color(1.0, 0.2, 0.2, OUTLINE_ALPHA * alpha_mult)
		match shape.type:
			"frontal_rectangle":
				_draw_frontal_rect(shape, fill, outline)
			"impact_aoe":
				var aoe_fill := Color(1.0, 0.5, 0.0, FILL_ALPHA * alpha_mult)
				var aoe_outline := Color(1.0, 0.5, 0.0, OUTLINE_ALPHA * alpha_mult)
				_draw_circle_range(shape, aoe_fill, aoe_outline)
			"self_centered_burst":
				_draw_circle_range(shape, fill, outline)
			"nearest_enemies":
				if shape.max_range > 0.0:
					_draw_circle_range(shape, fill, outline)
			_:
				if shape.max_range > 0.0:
					_draw_circle_range(shape, fill, outline)


func _draw_frontal_rect(shape: Dictionary, fill: Color, outline: Color) -> void:
	var pos: Vector2 = shape.position
	var half_h: float = shape.height / 2.0
	var rect: Rect2
	if shape.facing_right:
		rect = Rect2(pos.x, pos.y - half_h, shape.max_range, shape.height)
	else:
		rect = Rect2(pos.x - shape.max_range, pos.y - half_h, shape.max_range, shape.height)
	draw_rect(rect, fill)
	draw_rect(rect, outline, false, OUTLINE_WIDTH)


func _draw_circle_range(shape: Dictionary, fill: Color, outline: Color) -> void:
	var pos: Vector2 = shape.position
	draw_circle(pos, shape.max_range, fill)
	draw_arc(pos, shape.max_range, 0.0, TAU, 32, outline, OUTLINE_WIDTH)
