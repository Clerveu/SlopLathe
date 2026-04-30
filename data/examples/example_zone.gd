class_name ExampleZone
extends RefCounted


static func create_zone() -> ZoneDefinition:
	var zone := ZoneDefinition.new()
	zone.zone_id = "test_zone"
	zone.zone_name = "Test Zone"
	zone.tier = 1
	zone.duration = 60.0

	zone.enemy_roster = [
		{enemy_id = "skeleton_archer", weight = 1.0},
	]

	zone.spawn_interval_base = 4.0
	zone.spawn_interval_decay = 0.02
	zone.spawn_interval_floor = 1.5
	zone.initial_spawn_delay = 3.0

	zone.ground_y_range = Vector2(112.0, 148.0)

	# Wave 1: a group at 5 seconds
	var wave1 := WaveDefinition.new()
	wave1.trigger_type = "time"
	wave1.trigger_value = 5.0
	wave1.entries = [
		{enemy_id = "skeleton_archer", count = 3},
	]

	# Wave 2: a larger group at 20 seconds
	var wave2 := WaveDefinition.new()
	wave2.trigger_type = "time"
	wave2.trigger_value = 20.0
	wave2.entries = [
		{enemy_id = "skeleton_archer", count = 5},
	]

	zone.waves = [wave1, wave2]

	return zone
