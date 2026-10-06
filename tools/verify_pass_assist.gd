extends SceneTree
## Controlled integration fixture beside the full mannequin. The aperture is
## fixed for isolation; this is not proof a player can make a knot from scratch.
var app: AppController
var failures := 0
var aperture := {}
var previous_actual := Vector3.ZERO
var crossed_inside := false

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(1)
		return
	app = load("res://scenes/main/play.tscn").instantiate()
	root.add_child(app)
	ReplayInputGuard.install(self)
	app.rope.set_process(false)
	var center := Vector3(0.55, 1.1, 0)
	var points := RopeLayout.resample(PassFixture.points(center), 96)
	var config := RopeConfig.new()
	config.segment_count = 96
	config.length = RopeLayout.polyline_length(points)
	config.gravity = Vector3.ZERO
	config.drag_compliance = 0.00004
	config.damping = 6.0
	config.substeps = 8
	config.solver_iterations = 4
	var simulation := RopeSimulation.new(config, points)
	var apertures := RopePassCandidates.new().find(points, config.radius, 0, null)
	_check(not apertures.is_empty(), "fixture has a real initial aperture")
	if apertures.is_empty():
		quit(1)
		return
	var mouth: Vector3i = apertures[0].id
	simulation.pin(mouth.x + 1, points[mouth.x + 1])
	simulation.pin(mouth.y, points[mouth.y])
	# Relax the sampled polygon before fixing it: corner samples must not pin
	# incompatible segment lengths. Two mouth supports keep this controlled
	# aperture from opening while the remaining geometry relaxes.
	for warmup in 240:
		simulation.step(config.get_time_step())
	points = simulation.get_positions().duplicate()
	# Fix the ring and far tail only. The incoming strand remains physically free.
	var ring_start := 0
	var best := INF
	for i in points.size():
		var distance := points[i].distance_to(center + Vector3(0.14, 0, 0))
		if distance < best:
			best = distance
			ring_start = i
	for i in range(ring_start, points.size()):
		simulation.pin(i, points[i])
	simulation.stop_motion()
	aperture = RopePassCandidates.new().find(points, config.radius, 0, null)[0]
	previous_actual = points[0]
	print("Fixture initial stretch=", simulation.get_max_segment_stretch())
	var snapshot := app.rope.capture_scene_state()
	snapshot.simulation = simulation.capture_state()
	snapshot.start_attached = false
	snapshot.end_attached = true
	snapshot.end_anchor = [points[-1].x, points[-1].y, points[-1].z]
	_check(app.rope.restore_scene_state(snapshot), "fixture loads through validated scene state")
	var view := app.camera_rig.capture_state()
	for key in ["current", "target"]:
		view[key].yaw = atan2(0.6, 0.8)
		view[key].pitch = 0.0
		view[key].distance = 3.1
		view[key].focus = [0.25, 1.1, 0]
	app.camera_rig.restore_state(view)
	await process_frame
	var origin := app.camera_rig.get_camera().unproject_position(points[0])
	_mouse(origin, true)
	await process_frame
	_check(app.interaction_manager.get_selected_index() == 0, "mouse grabs fixture endpoint")
	var active_seen := false
	var worst_stretch := 0.0
	for frame in 140:
		_motion(origin + Vector2(float(frame + 1) * 0.45, 0))
		await process_frame
		app.rope.advance(1.0 / 60.0)
		_record_crossing()
		app.rope._refresh_mesh()
		active_seen = active_seen or app.interaction_manager._rope_interaction.get_pass_state() != RopePassAssist.State.FREE
		worst_stretch = maxf(worst_stretch, app.rope.get_simulation().get_max_segment_stretch())
		if frame == 45:
			var stopped := app.rope.get_simulation().get_drag_target()
			for idle in 12:
				await process_frame
				app.rope.advance(1.0 / 60.0)
				_record_crossing()
			_check(app.rope.get_simulation().get_drag_target() == stopped, "idle pointer does not advance assisted target")
	for frame in 60:
		app.rope.advance(1.0 / 60.0)
		_record_crossing()
		await process_frame
	app.rope._refresh_mesh()
	var actual := app.rope.get_simulation().get_point(0)
	print("Pass fixture endpoint=", actual, " active seen=", active_seen, " worst stretch=", worst_stretch)
	_check(active_seen, "clear direction activates corridor guidance")
	_check(actual.z < -0.04, "physical endpoint reaches the exit side")
	_check(crossed_inside, "physical trajectory crosses inside the aperture with rope-radius clearance")
	_check(worst_stretch < 0.08, "guided simulation keeps bounded length")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(args[0].path_join("pass-assisted.png"))
	_mouse(origin + Vector2(63, 0), false)
	await process_frame
	_check(app.interaction_manager._rope_interaction.get_pass_state() == RopePassAssist.State.FREE, "release clears transient guidance")
	print("Pass integration failures: ", failures)
	quit(1 if failures else 0)


func _mouse(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.device = ReplayInputGuard.DEVICE
	event.position = root.get_final_transform() * position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)


func _record_crossing() -> void:
	var current := app.rope.get_simulation().get_point(0)
	crossed_inside = crossed_inside or RopePassCandidates.crosses_aperture(previous_actual, current, aperture, app.rope.config.radius)
	previous_actual = current


func _motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.device = ReplayInputGuard.DEVICE
	event.position = root.get_final_transform() * position
	event.relative = root.get_final_transform().basis_xform(Vector2(0.45, 0))
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)


func _check(condition: bool, message: String) -> void:
	print("PASS " if condition else "FAIL ", message)
	if not condition:
		failures += 1
