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
