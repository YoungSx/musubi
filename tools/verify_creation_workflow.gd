extends SceneTree
## End-to-end authoring via dispatched mouse/wheel events. No particle writes.
var app: AppController
var failures := 0
var pointer := Vector2.ZERO

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(1)
		return
	app = load("res://scenes/main/main.tscn").instantiate() as AppController
	root.add_child(app)
	await _frames(30)
	# Exercise the menu's selection handler; all rope motion below uses raw input.
	app.hud.get_node("%RopeButton").get_popup().id_pressed.emit(2)
	await _frames(90)
	_check(is_equal_approx(app.rope.config.length, 3.0), "new long rope via menu")
	var camera := app.camera_rig.get_camera()
	pointer = camera.unproject_position(app.rope.get_simulation().get_point(0))
	_button(true)
	await _frames(1)
	_check(app.interaction_manager.get_selected_index() == 0, "mouse captures endpoint A")
	if failures:
		quit(1)
		return
	var initial := app.rope.get_simulation().get_point(0)
	for frame in 240:
		var theta := 1.35 + TAU * maxf(float(frame - 29) / 210.0, 0.0)
		var target := Vector3(0.36 * sin(theta), 1.2, 0.36 * cos(theta))
		if frame < 30:
			target = initial.lerp(target, float(frame + 1) / 30.0)
		_move_to(target)
		await _frames(2)
	await _frames(45)
	_button(false)
	await _frames(2)
	_check(app.rope.is_held(), "release holds creation")
	var points := app.rope.get_simulation().get_positions()
	var turn := 0.0
	var farthest_back := 0.0
	for i in points.size() - 1:
		turn += wrapf(atan2(points[i + 1].x, points[i + 1].z) - atan2(points[i].x, points[i].z), -PI, PI)
		farthest_back = minf(farthest_back, points[i].z)
	print("Creation winding radians=", turn, " back z=", farthest_back, " stretch=", app.rope.get_simulation().get_max_segment_stretch())
	# The loose loop settles around the legs under gravity, whose back surface
	# is nearer the center than the torso. Check winding as well as back passage.
	_check(absf(turn) > 4.0 and farthest_back < -0.05, "input-created rope passes around mannequin")
	_check(app.rope.get_simulation().get_max_segment_stretch() < 0.08, "wrap keeps bounded rope length")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[0].path_join("creation-wrap.png"))
	var path := args[0].path_join("input-created-wrap.musubi")
	_check(app.save_creation(path) == OK, "input-created structure saves")
	app.new_rope(1.4)
	_check(app.load_creation(path), "saved long creation loads over short rope")
	_check(app.rope.get_simulation().get_positions() == points, "saved geometry restored exactly")
	print("Creation workflow failures: ", failures)
	quit(1 if failures else 0)


func _move_to(target: Vector3) -> void:
	var camera := app.camera_rig.get_camera()
	var depth := camera.global_basis.z.dot(camera.global_position - target)
	var current := app.interaction_manager._rope_interaction.get_drag_depth()
	var steps := log(current / depth) / log(GestureTracker.WHEEL_ZOOM_STEP)
	if absf(steps) > 0.00001:
		var wheel := InputEventMouseButton.new()
		wheel.position = root.get_final_transform() * pointer
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP if steps > 0 else MOUSE_BUTTON_WHEEL_DOWN
		wheel.factor = absf(steps)
		wheel.pressed = true
		Input.parse_input_event(wheel)
	var position := camera.unproject_position(target)
	var motion := InputEventMouseMotion.new()
	motion.position = root.get_final_transform() * position
	motion.relative = root.get_final_transform().basis_xform(position - pointer)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(motion)
	pointer = position


func _button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = root.get_final_transform() * pointer
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _check(condition: bool, message: String) -> void:
	print("PASS " if condition else "FAIL ", message)
	if not condition:
		failures += 1
