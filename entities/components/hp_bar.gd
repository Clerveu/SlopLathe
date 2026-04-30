extends Node2D
## HP bar drawn above an entity. Uses _draw() for pixel-perfect rendering in SubViewport.

const BAR_WIDTH: float = 16.0
const BAR_HEIGHT: float = 2.0
const BG_COLOR := Color(0.15, 0.1, 0.1, 0.8)
const COLOR_GREEN := Color(0.2, 0.8, 0.2)
const COLOR_YELLOW := Color(0.9, 0.8, 0.1)
const COLOR_RED := Color(0.85, 0.15, 0.15)

var hp_ratio: float = 1.0


func _ready() -> void:
	z_index = 2


func update_bar(current: float, max_val: float) -> void:
	if max_val <= 0.0:
		hp_ratio = 0.0
	else:
		hp_ratio = clampf(current / max_val, 0.0, 1.0)
	visible = hp_ratio > 0.0 and hp_ratio < 1.0
	queue_redraw()


func _draw() -> void:
	# Background
	draw_rect(Rect2(0, 0, BAR_WIDTH, BAR_HEIGHT), BG_COLOR)
	# Fill
	if hp_ratio > 0.0:
		var color: Color
		if hp_ratio > 0.5:
			color = COLOR_GREEN
		elif hp_ratio > 0.25:
			color = COLOR_YELLOW
		else:
			color = COLOR_RED
		draw_rect(Rect2(0, 0, BAR_WIDTH * hp_ratio, BAR_HEIGHT), color)
