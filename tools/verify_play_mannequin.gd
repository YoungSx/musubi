extends SceneTree
## Screen-space replay against the full mannequin. No world-coordinate steering,
## depth wheel, pause, endpoint menu or prebuilt knot is used.
var app: AppController
var pointer := Vector2(680, 474)
var failures := 0

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(1)
		return
	app = load("res://scenes/main/play.tscn").instantiate()
	root.add_child(app)
	# Preserve the original free-camera mouse replay; assisted mode has its own replay.
	app.camera_rig.set_mode(CameraRig.Mode.FREE)
	ReplayInputGuard.install(self)
	await _frames(180)
	_check(app.mannequin.config.parts.size() >= 10, "full articulated mannequin is the play obstacle")
	_button(true)
	await _frames(1)
	_check(app.interaction_manager.get_selected_index() >= 0, "screen-only gesture grabs a visible rope end")
	if failures:
		quit(1)
		return
	for destination in [Vector2(750, 440), Vector2(780, 340), Vector2(735, 295), Vector2(640, 335)]:
		var start := pointer
		for frame in 45:
			_motion(start.lerp(destination, float(frame + 1) / 45.0))
			await _frames(2)
	await _frames(30)
	var sim := app.rope.get_simulation()
	var clearance := INF
	for point in sim.get_positions():
		clearance = minf(clearance, app.rope.get_collision().get_clearance(point))
	print("Mannequin grip clearance=", clearance, " stretch=", sim.get_max_segment_stretch())
	_check(clearance >= app.rope.config.radius * 0.9, "drag respects mannequin collision")
	_check(sim.get_max_segment_stretch() < 0.08, "drag keeps bounded length")
	_check(not app.rope_debug._target_marker.visible, "debug target hidden during play")
	await _capture(args[0], "play-human-grabbed")
	var target_before := sim.get_drag_target()
	var inspect := InputEventMouseButton.new()
	inspect.device = ReplayInputGuard.DEVICE
	inspect.button_index = MOUSE_BUTTON_MIDDLE
	inspect.position = pointer * Vector2(root.size) / Vector2(1280, 800)
	inspect.pressed = true
	Input.parse_input_event(inspect)
	_motion(pointer + Vector2(60, 20))
	await _frames(20)
	_check(app.interaction_manager.get_selected_index() >= 0, "middle-drag inspection keeps the grip")
	inspect = inspect.duplicate()
	inspect.pressed = false
	inspect.position = pointer * Vector2(root.size) / Vector2(1280, 800)
	Input.parse_input_event(inspect)
	await _frames(10)
	_motion(pointer)
	await _frames(1)
	_check(sim.get_drag_target().distance_to(target_before) < 0.0001, "camera inspection does not shift the hand target")
	_button(false)
	await _frames(1)
	var before := sim.get_positions().duplicate()
	_check(not app.rope.is_held() and sim.get_drag_index() == -1, "release removes grip without freezing")
	await _frames(90)
	_check(sim.get_positions() != before, "rope continues settling on the mannequin")
	await _capture(args[0], "play-human-released")
	print("Unfocused replay timings (not foreground FPS acceptance): ", app.get_node("PerformanceCapture").recorder.summary())
	var path := args[0].path_join("play-human.musubi")
	_check(app.save_creation(path) == OK, "natural play state saves")
	app.reset()
	_check(app.load_creation(path), "play state restores")
	_check(app.play_mode and not app.rope.hold_on_release, "restored play keeps natural release")
	print("Play mannequin failures: ", failures)
	quit(1 if failures else 0)


func _motion(position: Vector2) -> void:
	var scale := Vector2(root.size) / Vector2(1280, 800)
	var event := InputEventMouseMotion.new()
	event.device = ReplayInputGuard.DEVICE
	event.position = position * scale
	event.relative = (position - pointer) * scale
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)
	pointer = position


func _button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.device = ReplayInputGuard.DEVICE
	event.position = pointer * Vector2(root.size) / Vector2(1280, 800)
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _capture(output: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "capture " + label)


func _check(condition: bool, message: String) -> void:
	print("PASS " if condition else "FAIL ", message)
	if not condition:
		failures += 1
