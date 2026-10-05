extends TestCase


func test_escape_restores_grab_start_state() -> void:
	var app := add_to_tree(load("res://scenes/main/main.tscn").instantiate()) as AppController
	app.rope.set_process(false)
	var before := app.rope.get_simulation().capture_state()
	app.rope.begin_drag(24)
	app.rope.update_drag_target(Vector3(0.1, 1.2, 0.3))
	for step in 30:
		app.rope.advance(1.0 / 120.0)
	app.handle_action(&"cancel")
	assert_eq(app.rope.get_simulation().capture_state(), before, "cancel restores physics and removes temporary constraint")
	assert_true(not app.rope.is_held(), "cancel restores previous live state")


func test_keyboard_pause_and_view_reset_preserve_rope() -> void:
	var app := add_to_tree(load("res://scenes/main/main.tscn").instantiate()) as AppController
	app.rope.set_process(false)
	app.camera_rig.orbit(Vector2(0.2, 0.1))
	var before := app.rope.get_simulation().get_positions().duplicate()
	app.handle_action(&"pause")
	assert_true(app.rope.is_held(), "space pauses")
	app.handle_action(&"focus")
	assert_near(app.camera_rig.get_target_yaw(), deg_to_rad(app.camera_rig.config.yaw_degrees), "F resets camera")
	assert_eq(app.rope.get_simulation().get_positions(), before, "view reset preserves rope")
	app.handle_action(&"pause")
	assert_true(not app.rope.is_held(), "space resumes")


func test_mouse_hit_radius_is_tighter_than_touch() -> void:
	var app := add_to_tree(load("res://scenes/main/main.tscn").instantiate()) as AppController
	var interaction := RopeInteraction.new()
	interaction.configure(app.rope, app.camera_rig.get_camera())
	var screen := app.camera_rig.get_camera().unproject_position(app.rope.get_simulation().get_point(24))
	var offset := screen + Vector2(0, 19)
	interaction.pick_radius_pixels = 24
	assert_true(interaction.pick(offset) >= 0, "touch tolerance includes nearby rope")
	interaction.pick_radius_pixels = 12
	assert_eq(interaction.pick(offset), -1, "mouse requires closer aim")


func test_endpoint_drag_releases_only_that_anchor_and_release_keeps_it_free() -> void:
	var app := _app()
	var rope := app.rope
	var other_end := rope.get_simulation().get_point(rope.config.segment_count)
	var screen := app.camera_rig.get_camera().unproject_position(rope.get_simulation().get_point(0))
	app.interaction_manager.handle_input(_button(MOUSE_BUTTON_LEFT, screen, true))
	assert_eq(app.interaction_manager.get_selected_index(), 0, "mouse picks endpoint")
	assert_true(not rope.is_start_attached() and rope.is_end_attached(), "only selected endpoint is detached")
	assert_true(not rope.get_simulation().is_pinned(0), "selected endpoint is movable")
	rope.update_drag_target(rope.get_simulation().get_point(0) + Vector3(0, 0, 0.2))
	for step in 12:
		rope.advance(1.0 / 120.0)
	app.interaction_manager.handle_input(_button(MOUSE_BUTTON_LEFT, screen, false))
	assert_true(rope.is_held(), "release holds shape")
	assert_true(not rope.is_start_attached(), "release leaves endpoint free")
	assert_true(not rope.get_simulation().is_pinned(0), "release does not silently re-pin endpoint")
	assert_vec3_near(rope.get_simulation().get_point(rope.config.segment_count), other_end, "other anchor stays fixed")
	var held := rope.get_simulation().get_positions().duplicate()
	rope.advance(0.2)
	assert_eq(rope.get_simulation().get_positions(), held, "released shape stays exact")


func test_endpoint_cancel_and_reset_restore_attachments_and_anchor_positions() -> void:
	var app := _app()
	var rope := app.rope
	var initial := rope.capture_scene_state()
	assert_true(rope.begin_drag(0), "attached endpoint begins drag")
	rope.update_drag_target(rope.get_simulation().get_point(0) + Vector3(0.1, 0.1, 0.1))
	for step in 6:
		rope.advance(1.0 / 120.0)
	app.handle_action(&"cancel")
	assert_eq(rope.capture_scene_state(), initial, "Esc restores full pre-grab state and attachment")
	rope.begin_drag(0)
	rope.end_drag()
	rope.begin_drag(rope.config.segment_count)
	rope.end_drag()
	assert_true(not rope.is_start_attached() and not rope.is_end_attached(), "both ends may be free")
	rope.start_anchor.global_position += Vector3.ONE
	rope.end_anchor.global_position -= Vector3.ONE
	app.reset()
	assert_eq(rope.capture_scene_state(), initial, "Reset restores both attachments and initial anchor positions")


func test_wheel_changes_drag_depth_without_zooming_camera() -> void:
	var app := _app()
	var camera := app.camera_rig.get_camera()
	var screen := camera.unproject_position(app.rope.get_simulation().get_point(0))
	app.interaction_manager.handle_input(_button(MOUSE_BUTTON_LEFT, screen, true))
	var distance := app.camera_rig.get_target_distance()
	var target := app.rope.get_simulation().get_drag_target()
	app.interaction_manager.handle_input(_button(MOUSE_BUTTON_WHEEL_UP, screen, true))
	var moved := app.rope.get_simulation().get_drag_target()
	assert_true((moved - target).dot(camera.global_basis.z) > 0.01, "wheel-up pulls drag plane toward viewer")
	assert_near(app.camera_rig.get_target_distance(), distance, "camera does not zoom during drag")
	for tick in 100:
		app.interaction_manager.handle_input(_button(MOUSE_BUTTON_WHEEL_DOWN, screen, true))
	moved = app.rope.get_simulation().get_drag_target()
	assert_true(moved.is_finite(), "extreme depth remains finite")
	assert_true(moved.distance_to(app.rope.end_anchor.global_position) <= app.rope.config.length + 0.0001, "depth target respects remaining anchor reach")
	app.interaction_manager.handle_input(_button(MOUSE_BUTTON_LEFT, screen, false))
	app.interaction_manager.handle_input(_button(MOUSE_BUTTON_WHEEL_UP, screen, true))
	assert_true(app.camera_rig.get_target_distance() < distance, "wheel resumes camera zoom after release")


func test_scene_snapshot_roundtrip_preserves_free_end_and_rejects_active_capture() -> void:
	var app := _app()
	var rope := app.rope
	rope.begin_drag(0)
	assert_true(rope.capture_scene_state().is_empty(), "cannot save transient pointer capture")
	rope.end_drag()
	rope.start_anchor.global_position += Vector3(0.1, 0.2, 0.3)
	var snapshot := rope.capture_scene_state()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	assert_true(rope.validate_scene_state(parsed), "JSON scene snapshot validates")
	rope.reset()
	assert_true(rope.restore_scene_state(parsed), "scene snapshot restores")
	assert_true(not rope.is_start_attached() and rope.is_end_attached(), "restored attachment flags")
	assert_true(rope.is_held(), "restored held mode")
	assert_eq(rope.get_simulation().get_drag_index(), -1, "restore has no temporary drag")
	assert_true(rope.get_collision() != null, "restore preserves collision")
	assert_eq(rope.capture_scene_state(), snapshot, "full scene state round-trips")


func test_invalid_scene_snapshot_never_mutates_live_rope() -> void:
	var rope := _app().rope
	var before := rope.capture_scene_state()
	var bad_mass := before.duplicate(true)
	bad_mass.simulation.inverse_mass[0] = 1.0
	var bad_flag := before.duplicate(true)
	bad_flag.start_attached = false
	var bad_position := before.duplicate(true)
	bad_position.start_anchor[0] = NAN
	var bad_accumulator := before.duplicate(true)
	bad_accumulator.accumulator = -0.1
	var bad_config := before.duplicate(true)
	bad_config.simulation.config.radius *= 2.0
	for malformed in [bad_mass, bad_flag, bad_position, bad_accumulator, bad_config]:
		assert_true(not rope.validate_scene_state(malformed), "malformed snapshot rejected")
		assert_true(not rope.restore_scene_state(malformed), "invalid restore rejected")
		assert_eq(rope.capture_scene_state(), before, "invalid restore leaves live state untouched")


func _app() -> AppController:
	var app := add_to_tree(load("res://scenes/main/main.tscn").instantiate()) as AppController
	app.rope.set_process(false)
	return app


func _button(button: MouseButton, position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = position
	event.pressed = pressed
	return event
