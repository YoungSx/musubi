extends TestCase


func test_json_round_trip_preserves_scene_and_simulation_continuation() -> void:
	var original := _make_app()
	var restored := _make_app()
	original.mannequin.global_transform = Transform3D(Basis.from_euler(Vector3(0.05, 0.2, -0.03)).scaled(Vector3.ONE * 1.15), Vector3(0.12, 0.03, -0.21))
	original._configure_collision()
	original.camera_rig.orbit(Vector2(0.123456789, 0.07))
	original.camera_rig.pan(Vector2(0.03, 0.02))
	original.camera_rig.zoom(1.23456789012345)
	original.camera_rig._process(0.013)
	original.rope.advance(0.003)
	var before := MusubiSceneState.capture(original)
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(before, "", true, true))
	assert_true(MusubiSceneState.apply(restored, decoded), "valid JSON scene restores")
	_assert_state_equal(MusubiSceneState.capture(restored), before)
	assert_near(restored.camera_rig.get_target_distance(), original.camera_rig.get_target_distance(), "double precision camera distance", 1e-12)
	assert_true(restored.rope.get_collision() != original.rope.get_collision(), "restored collision belongs to restored scene")
	for step in 30:
		original.rope.advance(1.0 / 120.0)
		restored.rope.advance(1.0 / 120.0)
	assert_eq(restored.rope.get_simulation().capture_state(), original.rope.get_simulation().capture_state(), "continuation including rebuilt collision matches")


func test_invalid_load_leaves_every_module_unchanged() -> void:
	var app := _make_app()
	app.rope.advance(0.003)
	var before := MusubiSceneState.capture(app)
	var mutations: Array[Dictionary] = []
	var invalid := before.duplicate(true)
	invalid.camera.current.distance = -1.0
	mutations.append(invalid)
	invalid = before.duplicate(true)
	invalid.camera.target.focus = [NAN, 0, 0]
	mutations.append(invalid)
	invalid = before.duplicate(true)
	invalid.mannequin.config_path = "res://untrusted.tres"
	mutations.append(invalid)
	for basis in [[[0, 0, 0], [0, 0, 0], [0, 0, 0]], [[1, 0, 0], [0, 2, 0], [0, 0, 1]], [[1, 0, 0], [1, 1, 0], [0, 0, 1]], [[-1, 0, 0], [0, 1, 0], [0, 0, 1]]]:
		invalid = before.duplicate(true)
		invalid.mannequin.basis = basis
		mutations.append(invalid)
	invalid = before.duplicate(true)
	invalid.rope.simulation.positions = []
	mutations.append(invalid)
	invalid = before.duplicate(true)
	invalid.version = 999
	mutations.append(invalid)
	for data in mutations:
		assert_true(not MusubiSceneState.apply(app, data), "invalid scene rejected")
		assert_eq(MusubiSceneState.capture(app), before, "rejection is free of partial mutations")


func test_valid_load_clears_captured_pointer_and_invalid_load_preserves_it() -> void:
	var app := _make_app()
	var saved := MusubiSceneState.capture(app)
	var point := app.rope.get_simulation().get_point(24)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = app.camera_rig.get_camera().unproject_position(point)
	app.interaction_manager.handle_input(press)
	assert_true(app.interaction_manager.get_selected_index() >= 0, "pointer captures rope")
	assert_true(MusubiSceneState.capture(app).is_empty(), "saving an active physical gesture is refused")
	var during_drag := app.rope.get_simulation().capture_state()
	assert_true(not MusubiSceneState.apply(app, {"version": 999}), "invalid load refused during grab")
	assert_eq(app.rope.get_simulation().capture_state(), during_drag, "invalid load preserves live constraint")
	assert_true(app.interaction_manager.get_selected_index() >= 0, "invalid load preserves pointer")
	assert_true(MusubiSceneState.apply(app, saved), "valid load accepted during grab")
	assert_eq(app.interaction_manager.get_selected_index(), -1, "valid load clears captured pointer")
	assert_eq(MusubiSceneState.capture(app), saved, "valid load restores complete saved state")


func test_atomic_file_replace_and_invalid_file_read() -> void:
	var app := _make_app()
	var path := "user://scene-state-test-%s.json" % Time.get_ticks_usec()
	var saved := MusubiSceneState.capture(app)
	assert_eq(MusubiSceneState.write_file(path, saved), OK, "new scene file writes")
	assert_true(MusubiSceneState.apply(app, MusubiSceneState.read_file(path)), "file round trip restores")
	app.camera_rig.zoom(1.123456789012345)
	saved = MusubiSceneState.capture(app)
	assert_eq(MusubiSceneState.write_file(path, saved), OK, "existing scene replaced atomically")
	assert_true(MusubiSceneState.apply(app, MusubiSceneState.read_file(path)), "replacement round trip restores")
	assert_eq(MusubiSceneState.capture(app), saved, "replacement retains full precision")
	assert_eq(MusubiSceneState.write_file(path, {}), ERR_INVALID_DATA, "empty save cannot erase valid file")
	assert_true(MusubiSceneState.validate(app, MusubiSceneState.read_file(path)), "valid destination remains")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{broken json")
	file.close()
	assert_true(MusubiSceneState.read_file(path).is_empty(), "malformed JSON returns empty")
	assert_eq(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)), OK, "test scene file cleaned")
	assert_true(MusubiSceneState.read_file(path).is_empty(), "missing file returns empty")


func _make_app() -> AppController:
	var app := add_to_tree(load("res://scenes/main/main.tscn").instantiate()) as AppController
	app.process_mode = Node.PROCESS_MODE_DISABLED
	return app


func _assert_state_equal(actual: Variant, expected: Variant, path := "scene") -> void:
	if expected is Dictionary:
		for key in expected:
			_assert_state_equal(actual[key], expected[key], path + "." + key)
	elif expected is Array:
		assert_eq(actual.size(), expected.size(), path + " length")
		for index in expected.size():
			_assert_state_equal(actual[index], expected[index], path + "[%s]" % index)
	elif expected is float:
		# JSON parsing may round a double by one ULP; float32 vectors are exact.
		assert_near(actual, expected, path + " precision", 1e-12)
	else:
		assert_eq(actual, expected, path)
