extends SceneTree
## Portrait replay through Godot input dispatch. No direct solver steering.
var app: AppController
var failures := 0
var output := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	output = OS.get_cmdline_user_args()[0]
	app = load("res://scenes/main/play.tscn").instantiate()
	root.add_child(app)
	ReplayInputGuard.install(self)
	root.min_size = Vector2i.ZERO
	root.size = Vector2i(390, 844)
	root.content_scale_factor = 1.0
	root.content_scale_size = Vector2i(390, 844)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	await _frames(5)
	app.rope.set_process(false)
	var probe := RopeInteraction.new()
	probe.configure(app.rope, app.camera_rig.get_camera())
	var points: Array[Vector2] = []
	for point in app.rope.get_simulation().get_positions():
		var screen := app.camera_rig.get_camera().unproject_position(point)
		if not Rect2(20, 90, 350, 670).has_point(screen) or probe.pick(screen) < 0: continue
		if points.is_empty() or screen.distance_to(points[0]) > 65:
			points.append(screen)
		if points.size() == 2: break
	_check(points.size() == 2, "two separated visible rope points in portrait")
	if failures: quit(1); return
	_touch(0, points[0], true)
	_touch(5, points[1], true)
	await _frames(1)
	var sim := app.rope.get_simulation()
	_check(sim.get_grip_count() == 2, "real input dispatch acquires two grips")
	app.rope.set_process(true)
	for frame in 25:
		var amount := float(frame + 1) / 25.0
		_drag(0, points[0] + Vector2(-18, -25) * amount)
		_drag(5, points[1] + Vector2(18, -25) * amount)
		await _frames(1)
	await _capture("two-grips")
	_check(app.rope_debug._extra_grip_markers.size() == 1, "both grab markers rendered")
	var target_a := sim.get_drag_target(0)
	var target_b := sim.get_drag_target(5)
	var yaw := app.camera_rig.get_target_yaw()
	var focus := app.camera_rig.get_target_focus()
	_touch(2, Vector2(30, 790), true)
	_touch(3, Vector2(170, 790), true)
	_drag(2, Vector2(60, 780))
	_drag(3, Vector2(200, 780))
	await _frames(15)
	_check(app.camera_rig.get_target_yaw() != yaw, "two free fingers orbit beside two grips")
	_check(app.camera_rig.get_target_focus().is_equal_approx(focus), "orbit never pans")
	_drag(0, points[0] + Vector2(-18, -25))
	_drag(5, points[1] + Vector2(18, -25))
	_check(sim.get_drag_target(0).is_equal_approx(target_a) and sim.get_drag_target(5).is_equal_approx(target_b), "stationary grips survive camera smoothing without target jumps")
	_touch(4, Vector2(300, 790), true)
	yaw = app.camera_rig.get_target_yaw()
	_drag(4, Vector2(315, 770))
	await _frames(15)
	_check(app.camera_rig.get_target_yaw() == yaw, "third free finger changes orbit to pan")
	_check(not app.camera_rig.get_target_focus().is_equal_approx(focus), "three free fingers pan")
	await _capture("camera-with-grips")
	for id in [2, 3, 4]: _touch(id, Vector2.ZERO, false)
	_touch(0, Vector2(195, 22), false)
	await _frames(1)
	_check(sim.get_grip_count() == 1 and not app.rope.is_held(), "release over UI keeps other hand active")
	_touch(5, Vector2.ZERO, false)
	await _frames(1)
	_check(sim.get_grip_count() == 0 and not app.rope.is_held(), "play continues after last release")
	app.handle_action(&"ground")
	await _frames(3)
	yaw = app.camera_rig.get_target_yaw()
	_touch(0, Vector2(30, 790), true)
	_touch(1, Vector2(170, 790), true)
	_drag(1, Vector2(210, 790))
	await _frames(8)
	_check(app.camera_rig.get_target_yaw() != yaw, "floor session also permits touch orbit")
	app.interaction_manager.reset()
	await _capture("ground-orbit")
	print("Multitouch replay failures: ", failures)
	quit(1 if failures else 0)


func _touch(id: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.device = ReplayInputGuard.DEVICE
	event.index = id
	event.position = position
	event.pressed = pressed
	Input.parse_input_event(event)


func _drag(id: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.device = ReplayInputGuard.DEVICE
	event.index = id
	event.position = position
	Input.parse_input_event(event)


func _frames(count: int) -> void:
	for i in count: await process_frame


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "capture " + label)


func _check(condition: bool, message: String) -> void:
	print("PASS " if condition else "FAIL ", message)
	if not condition: failures += 1
