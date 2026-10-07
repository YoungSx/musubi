extends TestCase


func test_fractional_grip_has_no_snap_and_distributes_motion() -> void:
	var config := RopeConfig.new()
	config.segment_count = 4
	config.length = 1.0
	config.gravity = Vector3.ZERO
	config.self_collision_enabled = false
	var points := RopeLayout.straight(Vector3.ZERO, Vector3.RIGHT, 1.0, 4)
	var sim := RopeSimulation.new(config, points)
	assert_true(sim.begin_grip(0.375), "grip between particles")
	assert_vec3_near(sim.get_grip_position(), Vector3(0.375, 0, 0), "actual contact position")
	assert_eq(sim.get_positions(), points, "grabbing does not move geometry")
	sim.update_drag_target(Vector3(0.375, 0.1, 0))
	for step in 30:
		sim.step(config.get_time_step())
	assert_true(sim.get_point(1).y > 0.01 and sim.get_point(2).y > 0.01, "both neighboring particles respond")
	var restored := RopeSimulation.restore_state(JSON.parse_string(JSON.stringify(sim.capture_state(), "", true, true)))
	assert_true(restored != null, "fractional grip restores")
	assert_vec3_near(restored.get_grip_position(), sim.get_grip_position(), "grip material coordinate retained")
	for step in 30:
		sim.step(config.get_time_step())
		restored.step(config.get_time_step())
	assert_eq(sim.get_positions(), restored.get_positions(), "continued grip is deterministic")


func test_natural_release_keeps_physics_and_snapshot_continuation() -> void:
	var rope := add_to_tree(load("res://scenes/rope/rope.tscn").instantiate()) as Rope
	rope.hold_on_release = false
	rope.begin_grip(0.5)
	rope.update_drag_target(rope.get_simulation().get_grip_position() + Vector3.UP * 0.15)
	for step in 30:
		rope.advance(1.0 / 120.0)
	rope.end_drag()
	assert_true(not rope.is_held(), "natural release does not pause the world")
	var before := rope.get_simulation().get_positions().duplicate()
	var restored := RopeSimulation.restore_state(JSON.parse_string(JSON.stringify(rope.get_simulation().capture_state(), "", true, true)))
	for step in 30:
		rope.advance(1.0 / 120.0)
		restored.step(1.0 / 120.0)
	assert_true(rope.get_simulation().get_positions() != before, "gravity and motion continue after release")
	assert_eq(rope.get_simulation().get_positions(), restored.get_positions(), "release stabilization survives snapshots")


func test_play_scene_has_free_rope_and_minimal_default_ui() -> void:
	var app := add_to_tree(load("res://scenes/main/play.tscn").instantiate()) as AppController
	assert_true(app.play_mode, "play experience selected")
	assert_true(app.mannequin.config.parts.size() >= 10, "play retains the full mannequin")
	assert_true(not app.rope.is_start_attached() and not app.rope.is_end_attached(), "no invisible air attachments")
	assert_true(not app.rope.hold_on_release, "natural release is default")
	assert_true(not app.hud.get_node("SafeArea/Layout/Actions").visible, "tool row hidden")
	assert_true(not app.hud.get_node("SafeArea/Layout/RopeControls").visible, "rope editing controls hidden")
	assert_true(app.hud.get_node("%PlayMenu").visible, "one secondary menu remains")
	var saved := MusubiSceneState.capture(app)
	var workbench := add_to_tree(load("res://scenes/main/main.tscn").instantiate()) as AppController
	var old_scene := MusubiSceneState.capture(workbench)
	assert_true(MusubiSceneState.apply(app, old_scene), "existing workbench creations remain loadable")
	assert_true(not app.play_mode, "old scene retains workbench semantics")
	assert_true(MusubiSceneState.apply(app, saved), "play creation restores")
	assert_true(app.play_mode and not app.rope.hold_on_release, "play semantics restored")


func test_grip_validation_and_version_two_migration() -> void:
	var config := RopeConfig.new()
	var sim := RopeSimulation.new(config, RopeLayout.straight(Vector3.ZERO, Vector3.RIGHT, config.length, config.segment_count))
	var state := sim.capture_state()
	state.version = 2
	state.erase("drag_fraction")
	state.erase("release_u")
	state.erase("release_remaining")
	assert_true(RopeSimulation.restore_state(state) != null, "v2 states still load")
	for value in [-0.1, 1.0, NAN, "0.5"]:
		var invalid := sim.capture_state()
		invalid.drag_fraction = value
		assert_true(RopeSimulation.restore_state(invalid) == null, "malformed grip rejected")


func test_inspection_preserves_grip_and_camera_does_not_move_target() -> void:
	var app := add_to_tree(load("res://scenes/main/play.tscn").instantiate()) as AppController
	app.process_mode = Node.PROCESS_MODE_DISABLED
	var position := app.camera_rig.get_camera().unproject_position(app.rope.get_simulation().get_point(0))
	app.interaction_manager.handle_input(_touch(0, position, true))
	var selected := app.interaction_manager.get_selected_index()
	assert_true(selected >= 0, "primary touch grabs rope")
	var target := app.rope.get_simulation().get_drag_target(0)
	var yaw := app.camera_rig.get_target_yaw()
	app.interaction_manager.handle_input(_touch(1, Vector2(20, 20), true))
	app.interaction_manager.handle_input(_touch(2, Vector2(120, 20), true))
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = Vector2(50, 40)
	app.interaction_manager.handle_input(drag)
	app.camera_rig._process(0.1)
	assert_eq(app.interaction_manager.get_selected_index(), selected, "inspection does not release rope")
	assert_true(app.camera_rig.get_target_yaw() != yaw, "two free fingers inspect while a third grips")
	app.interaction_manager.handle_input(_touch(1, drag.position, false))
	app.interaction_manager.handle_input(_touch(2, Vector2(120, 20), false))
	app.camera_rig._process(0.1)
	drag.index = 0
	drag.position = position
	app.interaction_manager.handle_input(drag)
	assert_vec3_near(app.rope.get_simulation().get_drag_target(0), target, "stationary hand remains stationary after camera motion")
	app.interaction_manager.handle_input(_touch(0, position, false))
	assert_eq(app.interaction_manager.get_selected_index(), -1, "releasing primary ends grip")
	assert_true(not app.rope.is_held(), "inspection release does not pause physics")


func _touch(index: int, position: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	return event
