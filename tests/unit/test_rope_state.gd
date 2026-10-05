extends TestCase


func test_json_round_trip_preserves_active_drag_and_continuation() -> void:
	var original := _simulation()
	original.begin_drag(12)
	original.update_drag_target(Vector3(0.2, 1.2, 0.1))
	for step in 30:
		original.step(1.0 / 120.0)
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(original.capture_state(), "", true, true))
	var restored := RopeSimulation.restore_state(decoded)
	assert_true(restored != null, "valid JSON restores")
	if restored == null:
		return
	var before := original.capture_state()
	var after := restored.capture_state()
	for key in before:
		if key == "last_substep":
			assert_near(after[key], before[key], "speed time base preserved", 1e-12)
		elif key == "config":
			for parameter in before.config:
				if before.config[parameter] is float:
					assert_near(after.config[parameter], before.config[parameter], "parameter " + parameter, 1e-12)
				else:
					assert_true(after.config[parameter] == before.config[parameter], "parameter " + parameter)
		else:
			assert_true(after[key] == before[key], "snapshot " + key)
	for step in 120:
		original.step(1.0 / 120.0)
		restored.step(1.0 / 120.0)
	assert_eq(restored.get_positions(), original.get_positions(), "continued simulation matches exactly")


func test_snapshot_data_is_detached() -> void:
	var original := _simulation()
	var snapshot := original.capture_state()
	snapshot.positions[0][0] = 42.0
	snapshot.config.length = 2.0
	assert_near(original.get_point(0).x, 0.5, "snapshot cannot mutate simulation")
	assert_near(original.capture_state().config.length, 1.4, "snapshot config is detached")


func test_malformed_states_are_rejected() -> void:
	var valid := _simulation().capture_state()
	var mutations: Array[Dictionary] = [
		{"version": 999}, {"positions": []}, {"inverse_mass": []},
		{"drag_index": 10000}, {"drag_index": 0}, {"drag_index": 1.5},
		{"drag_target": [NAN, 0, 0]}, {"last_substep": -1},
	]
	for mutation in mutations:
		var data := valid.duplicate(true)
		data.merge(mutation, true)
		assert_true(RopeSimulation.restore_state(data) == null, "reject %s" % mutation)
	for value in [0, 257, 2.5, "48"]:
		var data := valid.duplicate(true)
		data.config.segment_count = value
		assert_true(RopeSimulation.restore_state(data) == null, "reject invalid count")
	var data := valid.duplicate(true)
	data.inverse_mass[1] = -1
	assert_true(RopeSimulation.restore_state(data) == null, "reject negative mass")


func _simulation() -> RopeSimulation:
	var config := RopeConfig.new()
	var points := RopeLayout.hanging(Vector3(0.5, 1.4, 0), Vector3(-0.5, 1.4, 0), config.length, config.segment_count)
	var simulation := RopeSimulation.new(config, points)
	simulation.pin(0, points[0])
	simulation.pin(config.segment_count, points[config.segment_count])
	return simulation
