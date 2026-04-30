extends Node

enum Phase { BASE, RUN }

var current_phase: Phase = Phase.BASE
var _run_scene_instance: Node2D = null

@onready var game_viewport: SubViewport = %GameViewport
@onready var ui_root: Control = %UIRoot

var _run_scene_packed: PackedScene = preload("res://scenes/run/run_scene.tscn")


func _ready() -> void:
	_enter_phase(Phase.BASE)


func start_run(zone_def: ZoneDefinition) -> void:
	_exit_current_phase()

	var run_scene := _run_scene_packed.instantiate()
	var combat_mgr: Node2D = run_scene
	combat_mgr.zone_def = zone_def
	game_viewport.add_child(run_scene)
	_run_scene_instance = run_scene

	combat_mgr.run_ended.connect(_on_run_ended)
	current_phase = Phase.RUN


func _on_run_ended(result: String) -> void:
	if result == "cleared" and is_instance_valid(_run_scene_instance):
		var zd: ZoneDefinition = _run_scene_instance.zone_def
		if zd and zd.zone_id != "" and not GameState.cleared_zones.has(zd.zone_id):
			GameState.cleared_zones.append(zd.zone_id)
	transition_to(Phase.BASE)


func transition_to(phase: Phase) -> void:
	_exit_current_phase()
	_enter_phase(phase)


func _enter_phase(phase: Phase) -> void:
	current_phase = phase


func _exit_current_phase() -> void:
	match current_phase:
		Phase.RUN:
			if is_instance_valid(_run_scene_instance):
				_run_scene_instance.queue_free()
				_run_scene_instance = null
