extends TestCase


func test_drag_is_one_transaction_and_cancel_adds_none() -> void:
	var app := _app()
	var before := app.rope.capture_scene_state()
	app.rope.begin_drag(0)
	app.rope.update_drag_target(app.rope.get_simulation().get_point(0) + Vector3(0.05, 0.03, 0.06))
	for step in 20:
		app.rope.advance(1.0 / 120.0)
	app.rope.end_drag()
	var after := app.rope.capture_scene_state()
	assert_eq(app.history.get_entry_count(), 1, "all drag frames form one edit")
	app.handle_action(&"undo")
	assert_eq(app.rope.capture_scene_state(), before, "undo restores geometry, velocities and attachment")
	app.handle_action(&"redo")
	assert_eq(app.rope.capture_scene_state(), after, "redo restores exact released state")
	app.rope.begin_drag(20)
	app.rope.cancel_drag()
	assert_eq(app.history.get_entry_count(), 1, "cancel does not add history")


func test_new_length_and_attachments_undo_redo_and_branch() -> void:
	var app := _app()
	app.new_rope(3.0)
	app.handle_action(&"attachment_a")
	var after := app.rope.capture_scene_state()
	app.handle_action(&"undo")
	assert_true(app.rope.is_start_attached(), "undo release fixes endpoint")
	app.handle_action(&"undo")
	assert_near(app.rope.config.length, 1.4, "undo new rope restores original topology")
	app.handle_action(&"redo")
	app.handle_action(&"redo")
	assert_eq(app.rope.capture_scene_state(), after, "redo reconstructs longer free rope")
	app.handle_action(&"undo")
	app.new_rope(2.2)
	assert_true(not app.history.can_redo(), "new edit discards abandoned redo branch")


func test_history_bound_and_load_clears_history() -> void:
	var app := _app()
	for i in 40:
		app.handle_action(&"attachment_a")
	assert_eq(app.history.get_entry_count(), RopeHistory.MAX_ENTRIES, "old edits trimmed")
	assert_true(app.history.get_encoded_bytes() <= RopeHistory.MAX_BYTES, "encoded snapshot budget bounded")
	var path := "user://history-test-%d.musubi" % Time.get_ticks_usec()
	assert_eq(app.save_creation(path), OK, "save succeeds")
	assert_true(app.load_creation(path), "load succeeds")
	assert_true(not app.history.can_undo() and not app.history.can_redo(), "loading establishes a fresh history boundary")
	DirAccess.remove_absolute(path)


func test_shortcuts_map_undo_and_redo() -> void:
	var key := InputEventKey.new()
	key.ctrl_pressed = true
	key.keycode = KEY_Z
	assert_eq(DesktopShortcuts.action_for_key(key), &"undo", "Ctrl Z")
	key.shift_pressed = true
	assert_eq(DesktopShortcuts.action_for_key(key), &"redo", "Ctrl Shift Z")
	key.shift_pressed = false
	key.keycode = KEY_Y
	assert_eq(DesktopShortcuts.action_for_key(key), &"redo", "Ctrl Y")


func _app() -> AppController:
	var app := add_to_tree(load("res://scenes/main/main.tscn").instantiate()) as AppController
	app.process_mode = Node.PROCESS_MODE_DISABLED
	return app
