extends SceneTree
## Floor scenario with full mannequin; no camera/height controls in the replay.
var app: AppController
var pointer := Vector2.ZERO
var failures := 0
var left_down := false
var motion_scale := 1.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(1)
		return
	if args.size() > 1: motion_scale = clampf(float(args[1]), 0.5, 2.0)
	app = load("res://scenes/main/play.tscn").instantiate()
	root.add_child(app)
	ReplayInputGuard.install(self)
	app.hud.get_node("%PlayMenu").get_popup().id_pressed.emit(5)
	app.hud.visible = false # Core gestures must work without any UI.
	await _frames(180)
	await _capture(args[0], "ground-ready")
	_check(app.mannequin.config.parts.size() >= 10, "full mannequin remains in ground play")
	_check(app.rope.initial_layout == Rope.InitialLayout.FLOOR, "normal rope starts on the floor")
	pointer = Vector2(794, 439)
	_button(MOUSE_BUTTON_LEFT, true)
	await _frames(1)
	_check(app.interaction_manager.get_selected_index() >= 0, "left button picks the visible end")
	for destination in [Vector2(785, 500), Vector2(720, 555), Vector2(615, 570), Vector2(515, 580), Vector2(495, 565)]:
		await _drag_to(destination, 70)
	await _frames(30)
	await _capture(args[0], "ground-loop-held")
	_button(MOUSE_BUTTON_LEFT, false)
	await _frames(60)
	await _capture(args[0], "ground-loop-released")
	print("Ground loop crossings=", _crossings(), " stretch=", app.rope.get_simulation().get_max_segment_stretch())
	print("Observed loops=", GroundLoopTopology.new().observe(app.rope.get_simulation().get_positions(), app.rope.config.radius, 0).size())
	_check(_crossings() >= 1, "left drag creates an actual over/under crossing")
	var camera_before := app.camera_rig.capture_state()
	pointer = Vector2(499, 565)
	_button(MOUSE_BUTTON_LEFT, true)
	await _frames(1)
	_check(app.interaction_manager.get_selected_index() >= 0, "re-grab the end without selecting a hole")
	for destination in [Vector2(465, 610), Vector2(525, 663), Vector2(610, 663), Vector2(615, 603)]:
		await _drag_to(destination, 90)
		print("Intent phase=", app.interaction_manager._rope_interaction._ground_intent.phase, " confidence=", app.interaction_manager._rope_interaction._ground_intent.confidence, " support=", app.rope.has_support(), " crossings=", _crossings())
	await _frames(30)
	await _capture(args[0], "ground-pass-held")
	print("Confirmed passes=", app.interaction_manager._rope_interaction._ground_intent.confirmed_passes)
	_check(app.interaction_manager._rope_interaction._ground_intent.confirmed_passes >= 1, "actual endpoint passes below the lifted strand")
	_button(MOUSE_BUTTON_LEFT, false)
	await _frames(60)
	await _capture(args[0], "ground-pass-set")
	_check(app.camera_rig.capture_state() == camera_before, "camera remains fixed throughout the gesture")
	pointer = Vector2(615, 603)
	_button(MOUSE_BUTTON_LEFT, true)
	await _frames(1)
	_check(app.interaction_manager.get_selected_index() >= 0, "grab passed end for Pull")
	for destination in [Vector2(640, 590), Vector2(665, 550), Vector2(750, 525)]:
		await _drag_to(destination, 90)
	await _frames(30)
	await _capture(args[0], "ground-pull-held")
	print("After Pull crossings=", _crossings(), " stretch=", app.rope.get_simulation().get_max_segment_stretch())
	_button(MOUSE_BUTTON_LEFT, false)
	await _frames(120)
	await _capture(args[0], "ground-knot-set")
	print("After Set crossings=", _crossings())
	_check(_crossings() == 3, "three separated crossings survive Pull and Set")
	_check(app.rope.get_simulation().get_max_segment_stretch() < 0.05, "settled knot stays within five percent segment stretch")
	_check(not app.rope.has_support(), "release removes internal support")
	_check(app.camera_rig.capture_state() == camera_before, "Pull and Set keep the camera fixed")
	var order := _crossing_order()
	print("Crossing order: ", order)
	_check(order == [-1, 2, -3, 1, -2, 3], "fixture retains alternating crossing order after settling")
	print("Ground replay failures: ", failures)
	quit(1 if failures else 0)

func _frames(count: int) -> void:
	for i in count: await process_frame

func _button(button: MouseButton, pressed: bool) -> void:
	if button == MOUSE_BUTTON_LEFT: left_down = pressed
	var event := InputEventMouseButton.new()
	event.device = ReplayInputGuard.DEVICE
	event.position = pointer * Vector2(root.size) / Vector2(1280, 800)
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)

func _drag_to(destination: Vector2, frames: int) -> void:
	frames = maxi(1, roundi(frames * motion_scale))
	var start := pointer
	for frame in frames:
		var position := start.lerp(destination, float(frame + 1) / frames)
		var event := InputEventMouseMotion.new()
		event.device = ReplayInputGuard.DEVICE
		event.position = position * Vector2(root.size) / Vector2(1280, 800)
		event.relative = (position - pointer) * Vector2(root.size) / Vector2(1280, 800)
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if left_down else 0
		Input.parse_input_event(event)
		pointer = position
		await process_frame

func _crossings() -> int:
	return _crossing_order().size() / 2


func _crossing_order() -> Array[int]:
	var points := app.rope.get_simulation().get_positions()
	var count := 0
	var encounters: Array[Vector2] = []
	for i in points.size() - 1:
		for j in range(i + 3, points.size() - 1):
			var a := Vector2(points[i].x, points[i].z)
			var b := Vector2(points[i + 1].x, points[i + 1].z)
			var c := Vector2(points[j].x, points[j].z)
			var d := Vector2(points[j + 1].x, points[j + 1].z)
			var intersection: Variant = Geometry2D.segment_intersects_segment(a, b, c, d)
			if intersection == null: continue
			var t := clampf(((intersection as Vector2) - a).dot(b - a) / maxf(a.distance_squared_to(b), 1e-10), 0, 1)
			var u := clampf(((intersection as Vector2) - c).dot(d - c) / maxf(c.distance_squared_to(d), 1e-10), 0, 1)
			if absf(lerpf(points[i].y, points[i + 1].y, t) - lerpf(points[j].y, points[j + 1].y, u)) > app.rope.config.radius * 1.5:
				count += 1
				var over := 1 if lerpf(points[i].y, points[i + 1].y, t) > lerpf(points[j].y, points[j + 1].y, u) else -1
				encounters.append(Vector2(i + t, count * over))
				encounters.append(Vector2(j + u, -count * over))
	encounters.sort_custom(func(a: Vector2, b: Vector2): return a.x < b.x)
	var order: Array[int] = []
	for encounter in encounters: order.append(int(encounter.y))
	return order

func _capture(output: String, label: String) -> void:
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "capture " + label)

func _check(condition: bool, message: String) -> void:
	print("PASS " if condition else "FAIL ", message)
	if not condition: failures += 1
