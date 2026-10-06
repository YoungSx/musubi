extends TestCase


func test_length_presets_and_cross_configuration_scene_restore() -> void:
	var app := _app()
	for length_m in [1.4, 2.2, 3.0, 6.0]:
		assert_true(app.new_rope(length_m), "preset accepted")
		assert_near(app.rope.config.length, length_m, "correct rest length")
		assert_true(app.rope.config.get_rest_length() <= 0.033, "particle density preserved")
		app.rope.set_held(true)
		var saved := MusubiSceneState.capture(app)
		app.new_rope(1.4)
		assert_true(MusubiSceneState.apply(app, JSON.parse_string(JSON.stringify(saved, "", true, true))), "different configuration restores")
		assert_near(app.rope.config.length, length_m, "renderer/scheduler config matches loaded simulation")
		assert_eq(app.rope.get_simulation().get_point_count(), app.rope.config.segment_count + 1, "topology restored")
		app.reset()
		assert_near(app.rope.config.length, length_m, "reset preserves selected rope length")
	var before := MusubiSceneState.capture(app)
	assert_true(not app.new_rope(100), "unknown preset rejected")
	assert_eq(MusubiSceneState.capture(app), before, "invalid request is inert")


func test_fix_release_endpoints_and_import_work_bound() -> void:
	var app := _app()
	app.handle_action(&"attachment_a")
	assert_true(not app.rope.is_start_attached() and app.rope.is_held(), "release holds current shape")
	var point := app.rope.get_simulation().get_point(0)
	app.handle_action(&"attachment_a")
	assert_true(app.rope.is_start_attached(), "fix endpoint")
	assert_eq(app.rope.start_anchor.global_position, point, "fix happens at current position")
	var saved := MusubiSceneState.capture(app)
	var invalid := saved.duplicate(true)
	invalid.rope.simulation.config.substeps = 32
	invalid.rope.simulation.config.solver_iterations = 64
	assert_true(not MusubiSceneState.apply(app, invalid), "expensive untrusted configuration refused")
	assert_eq(MusubiSceneState.capture(app), saved, "rejected import preserves scene")

func test_long_shoulder_rope_places_slack_above_floor() -> void:
	var config := RopeConfig.for_length(6.0)
	var points := RopeLayout.shoulder_drape(config.length,config.segment_count)
	assert_eq(points.size(),193,"long rope preserves spatial sampling")
	for point in points:
		assert_true(point.y >= config.radius,"long tails are laid on the floor rather than spawned below it")
	assert_near(RopeLayout.polyline_length(points),6.0,"initial rope conserves length",0.04)

func test_long_floor_rope_fits_before_interaction() -> void:
	var app := _app()
	app.handle_action(&"ground")
	app.new_rope(6.0)
	var camera := app.camera_rig.get_camera()
	var frame := camera.get_viewport().get_visible_rect().grow(-16)
	for point in app.rope.get_simulation().get_positions():
		assert_true(frame.has_point(camera.unproject_position(point)),"long rope starts inside the fixed view")
	assert_true(frame.has_point(camera.unproject_position(Vector3(0,1.75,0))),"full mannequin remains framed")


func _app() -> AppController:
	var app := add_to_tree(load("res://scenes/main/main.tscn").instantiate()) as AppController
	app.process_mode = Node.PROCESS_MODE_DISABLED
	return app
