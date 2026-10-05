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
		motion.position = position + Vector2(-55, -65) * float(step + 1) / 30.0
		motion.relative = Vector2(-55, -65) / 30.0
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
	print("Rendered interaction smoke: %d failures" % failures)
	quit(1 if failures else 0)


func _button(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
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
