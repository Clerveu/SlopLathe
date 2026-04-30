extends Node

var unit_definitions: Dictionary = {}
var enemy_definitions: Dictionary = {}


func get_unit_def(unit_id: String) -> UnitDefinition:
	return unit_definitions.get(unit_id)


func get_enemy_def(enemy_id: String) -> EnemyDefinition:
	return enemy_definitions.get(enemy_id)


func register_unit(unit_id: String, def: UnitDefinition) -> void:
	unit_definitions[unit_id] = def


func register_enemy(enemy_id: String, def: EnemyDefinition) -> void:
	enemy_definitions[enemy_id] = def
