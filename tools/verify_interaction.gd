extends SceneTree
## Rendered input smoke: use with a graphics driver, not --headless.
## godot --path . -s res://tools/verify_interaction.gd -- <output-directory>

var app: AppController
var output: String
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or not DirAccess.dir_exists_absolute(args[0]):
		printerr("Provide an existing screenshot output directory.")
		quit(1)
		return
	output = args[0]
	app = load("res://scenes/main/main.tscn").instantiate() as AppController
	root.add_child(app)
	await _frames(90)
	var camera := app.camera_rig.get_camera()
	var position := camera.unproject_position(app.rope.get_simulation().get_point(16))
	_button(position, true)
	await _frames(1)
	_check(app.interaction_manager.get_selected_index() >= 0, "real input selects visible rope")
	if failures > 0:
		quit(1)
		return
	var yaw := app.camera_rig.get_target_yaw()
	var index := app.interaction_manager.get_selected_index()
	var before := app.rope.get_simulation().get_point(index)
	for step in 30:
		var motion := InputEventMouseMotion.new()
		motion.position = root.get_final_transform() * (position + Vector2(-55, -65) * float(step + 1) / 30.0)
		motion.relative = root.get_final_transform().basis_xform(Vector2(-55, -65) / 30.0)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(motion)
		await _frames(2)
	await _frames(60)
	_check(app.rope.get_simulation().get_point(index).distance_to(before) > 0.01, "rendered rope responds to drag")
	_check(is_equal_approx(yaw, app.camera_rig.get_target_yaw()), "rope drag does not orbit")
	await _capture("dragging")
	var reset := app.hud.get_node("%ResetButton") as Button
	var reset_position := reset.get_global_rect().get_center()
	# Captured release over a UI control must still end the rope constraint.
	_button(reset_position, false)
	await _frames(1)
	_check(app.rope.is_held(), "release over UI holds shape")
	var held := app.rope.get_simulation().get_positions().duplicate()
	await _frames(45)
	_check(app.rope.get_simulation().get_positions() == held, "released shape remains exact")
	await _capture("held")
	_button(reset_position, true)
	_button(reset_position, false)
	await _frames(45)
	_check(not app.rope.is_held(), "real Reset button resumes simulation")
	_check(app.rope.get_simulation().get_drag_index() == -1, "Reset clears selection")
	await _capture("reset")
	var debug_button := app.hud.get_node("%DebugButton") as Button
	var debug_position := debug_button.get_global_rect().get_center()
	_button(debug_position, true)
	_button(debug_position, false)
	await _frames(20)
	_check(app.rope_debug.is_debug_enabled(), "real Debug button shows diagnostics")
	await _capture("debug")
	_key(KEY_SPACE)
	await _frames(1)
	_check(app.rope.is_held(), "Space pauses")
	_key(KEY_SPACE)
	await _frames(1)
	_check(not app.rope.is_held(), "Space resumes")
	app.camera_rig.orbit(Vector2(0.1, 0.1))
	_key(KEY_F)
	await _frames(1)
	_check(is_equal_approx(app.camera_rig.get_target_yaw(), deg_to_rad(app.camera_rig.config.yaw_degrees)), "F restores view")
	_key(KEY_F9)
	await _frames(1)
	var report_path: String = app.get_node("PerformanceCapture").last_report_path
	_check(not report_path.is_empty() and FileAccess.file_exists(report_path), "F9 writes performance report")
	if not report_path.is_empty():
		var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(report_path))
		_check(report.summary.sample_count > 0 and report.summary.frame_ms_p95 > 0, "report contains measured frame timings")
	app.reset()
	await _frames(30)
	position = camera.unproject_position(app.rope.get_simulation().get_point(0))
	_button(position, true)
	await _frames(1)
	_check(app.interaction_manager.get_selected_index() == 0, "real input selects anchored endpoint")
	_check(not app.rope.is_start_attached(), "grabbing endpoint detaches it")
	var camera_distance := app.camera_rig.get_target_distance()
	var target_before := app.rope.get_simulation().get_drag_target()
	var wheel := InputEventMouseButton.new()
	wheel.position = root.get_final_transform() * position
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	Input.parse_input_event(wheel)
	await _frames(15)
	_check(app.rope.get_simulation().get_drag_target().distance_to(target_before) > 0.01, "wheel changes endpoint depth")
	_check(is_equal_approx(camera_distance, app.camera_rig.get_target_distance()), "depth wheel preserves camera distance")
	await _capture("endpoint")
	_key(KEY_ESCAPE)
	await _frames(1)
	_check(app.rope.is_start_attached() and app.rope.is_end_attached(), "Esc restores endpoint attachments")
	_button(position, false)
	await _verify_creation_dialogs()
	print("Rendered interaction smoke: %d failures" % failures)
	quit(1 if failures else 0)


func _verify_creation_dialogs() -> void:
	app.rope.set_held(true)
	await _frames(45)
	var saved := MusubiSceneState.capture(app)
	var path := output.path_join("smoke-%d.musubi" % Time.get_ticks_usec())
	var save_button := app.hud.get_node("%SaveButton") as Button
	_button(save_button.get_global_rect().get_center(), true)
	_button(save_button.get_global_rect().get_center(), false)
	await _frames(2)
	var dialog := app.hud._file_dialog
	_check(dialog != null and dialog.visible and dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE, "Save button opens save dialog")
	await _capture("save-dialog")
	# File selection is dispatched through the dialog signal; filesystem behavior
	# and exact scene restoration are checked below, without automating OS dialogs.
	dialog.file_selected.emit(path)
	dialog.hide()
	_check(FileAccess.file_exists(path), "save dialog selection writes creation")
	app.reset()
	await _frames(10)
	var open_button := app.hud.get_node("%LoadButton") as Button
	_button(open_button.get_global_rect().get_center(), true)
	_button(open_button.get_global_rect().get_center(), false)
	await _frames(2)
	_check(dialog.visible and dialog.file_mode == FileDialog.FILE_MODE_OPEN_FILE, "Open button opens load dialog")
	dialog.file_selected.emit(path)
	dialog.hide()
	_check(_states_match(MusubiSceneState.capture(app), saved), "load dialog selection restores complete scene")
	await _capture("loaded")
	_check(DirAccess.remove_absolute(path) == OK, "temporary smoke creation removed")


func _states_match(actual: Variant, expected: Variant) -> bool:
	if expected is Dictionary:
		if not actual is Dictionary or actual.size() != expected.size():
			return false
		for key in expected:
			if not actual.has(key) or not _states_match(actual[key], expected[key]):
				return false
		return true
	if expected is Array:
		if not actual is Array or actual.size() != expected.size():
			return false
		for index in expected.size():
			if not _states_match(actual[index], expected[index]):
				return false
		return true
	if expected is float:
		return (actual is float or actual is int) and absf(actual - expected) < 1e-12
	return actual == expected


func _button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	# Input.parse_input_event takes window pixels, including native DPI scaling.
	event.position = root.get_final_transform() * position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)


func _frames(count: int) -> void:
	for frame in count:
		await process_frame


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output.path_join("interaction-" + label + ".png")) == OK, "save " + label)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS ", message)
	else:
		failures += 1
		printerr("FAIL ", message)
