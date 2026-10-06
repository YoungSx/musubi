extends SceneTree
## Controlled integration fixture beside the full mannequin. The aperture is
## fixed for isolation; this is not proof a player can make a knot from scratch.
var app: AppController
var failures := 0
var aperture := {}
var previous_actual := Vector3.ZERO
var crossed_inside := false
var torso_fixture := false
var reverse_crossed_inside := false
var scenario := "forward"
var last_pointer := Vector2.ZERO
var forward_sign := 1.0
var body_clear_throughout := true
var report_path := ""

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(1)
		return
	torso_fixture = "--torso" in args
	for name in ["bypass","withdraw","reverse","regrab"]:
		if ("--"+name) in args: scenario = name
	report_path = args[0].path_join("pass-"+("torso" if torso_fixture else "side")+"-"+scenario+".json")
	_write_report({"status":"running","scenario":scenario})
	app = load("res://scenes/main/play.tscn").instantiate()
	root.add_child(app)
	ReplayInputGuard.install(self)
	app.rope.set_process(false)
	var center := Vector3(0.55, 1.1, 0)
	var path := PassFixture.points(center)
	if torso_fixture:
		center = Vector3(0,1.22,0)
		path = PassFixture.points(Vector3.ZERO,0.2)
		# Elliptical ring fits between torso and arms; a circular ring's fixed
		# side points would otherwise intersect the upper arms.
		for i in path.size(): path[i] = Vector3(path[i].x*0.85,1.22+path[i].z,path[i].y*1.1)
		for i in 25:
			var angle := (TAU-0.1)*float(i)/24
			path[i+4] = Vector3(cos(angle)*0.17,1.22,sin(angle)*0.22)
		path[0] = Vector3(0,1.32,0.17)
	var points := RopeLayout.resample(path, 96)
	var config := RopeConfig.new()
	config.segment_count = 96
	config.length = RopeLayout.polyline_length(points)
	config.gravity = Vector3.ZERO
	config.drag_compliance = 0.00004
	config.damping = 6.0
	config.substeps = 8
	config.solver_iterations = 4
	var simulation := RopeSimulation.new(config, points)
	if torso_fixture: simulation.set_collision(app.rope.get_collision())
	var apertures := RopePassCandidates.new().find(points, config.radius, 0, null)
	_check(not apertures.is_empty(), "fixture has a real initial aperture")
	if apertures.is_empty():
		quit(1)
		return
	var mouth: Vector3i = apertures[0].id
	if torso_fixture:
		# This diagnostic measures passing through a known gap, not forming or
		# retaining a ring. Preserve the prescribed ring during tail relaxation.
		for i in points.size():
			if absf(points[i].y-center.y) < 0.000001: simulation.pin(i,points[i])
		simulation.pin(points.size()-1,points[-1])
	else:
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
		var distance := points[i].distance_to(center + Vector3(0.17 if torso_fixture else 0.14, 0, 0))
		if distance < best:
			best = distance
			ring_start = i
	for i in range(ring_start, points.size()):
		simulation.pin(i, points[i])
	simulation.stop_motion()
	var fixture_clear := true
	for i in points.size()-1:
		fixture_clear = fixture_clear and app.rope.get_collision().is_body_segment_clear(points[i],points[i+1],config.radius-0.00005)
	_check(fixture_clear,"entire relaxed fixture clears the mannequin, including pinned segments")
	if not fixture_clear:
		quit(1)
		return
	var provider := RopePassCandidates.new()
	var available := provider.find(points,config.radius,0,app.rope.get_collision() if torso_fixture else null)
	_check(not available.is_empty(),"relaxed fixture retains a physically clear corridor")
	if available.is_empty():
		quit(1)
		return
	available.sort_custom(func(a: Dictionary,b: Dictionary): return a.center.distance_squared_to(points[0]) < b.center.distance_squared_to(points[0]))
	aperture = available[0]
	forward_sign = -signf((points[0]-aperture.center).dot(aperture.normal))
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
		view[key].yaw = 0.0 if torso_fixture else atan2(0.6, 0.8)
		view[key].pitch = 0.0
		view[key].distance = 3.1
		view[key].focus = [0,1.22,0] if torso_fixture else [0.25, 1.1, 0]
	app.camera_rig.restore_state(view)
	await process_frame
	var initial_camera := app.camera_rig.get_camera().global_transform
	var origin := app.camera_rig.get_camera().unproject_position(points[0])
	last_pointer = origin
	_mouse(origin, true)
	await process_frame
	_check(app.interaction_manager.get_selected_index() == 0, "mouse grabs fixture endpoint")
	var active_seen := false
	var worst_stretch := 0.0
	var motion := Vector2(0,0.45) if torso_fixture else Vector2(0.45,0)
	if scenario == "bypass": motion = Vector2(0.45,0) if torso_fixture else Vector2(0,0.45)
	var frames := 30 if scenario == "withdraw" else 140
	for frame in frames:
		_motion(origin + motion*float(frame+1))
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
	if scenario == "bypass":
		_check(not active_seen,"sideways intent does not acquire a passage")
		_check(not crossed_inside,"sideways intent does not produce a pass")
	elif scenario == "withdraw":
		_check(active_seen,"pre-crossing approach acquires guidance before withdrawal")
		_check(not crossed_inside,"approach stops before crossing")
	else:
		_check(active_seen, "clear direction activates corridor guidance")
		_check(actual.y < 1.18 if torso_fixture else actual.z < -0.04, "physical endpoint reaches the exit side")
		_check(crossed_inside, "physical trajectory crosses inside the aperture with rope-radius clearance")
	if scenario in ["reverse","withdraw","regrab"]:
		var return_origin := origin+motion*frames
		if scenario == "regrab":
			_mouse(return_origin,false)
			await process_frame
			_check(app.rope.get_simulation().get_drag_index() == -1,"release removes the grip before regrabbing")
			return_origin = app.camera_rig.get_camera().unproject_position(app.rope.get_simulation().get_point(0))
			_mouse(return_origin,true)
			await process_frame
			_check(app.interaction_manager.get_selected_index() == 0,"regrab the visible end without moving the camera")
		for frame in frames:
			_motion(return_origin-motion*(frame+1))
			await process_frame
			app.rope.advance(1.0/60)
			_record_crossing()
			app.rope._refresh_mesh()
			worst_stretch = maxf(worst_stretch,app.rope.get_simulation().get_max_segment_stretch())
		actual = app.rope.get_simulation().get_point(0)
		_check(actual.y > 1.28 if torso_fixture else actual.z > 0.04,"reverse input returns the actual tip to the entrance side")
		_check(not crossed_inside if scenario == "withdraw" else reverse_crossed_inside,"withdrawal avoids crossing, or reverse crosses back through the real aperture")
	_check(worst_stretch < 0.08, "guided simulation keeps bounded length")
	_check(body_clear_throughout,"all simulated rope segments retain body clearance")
	_check(app.camera_rig.get_camera().global_transform.is_equal_approx(initial_camera),"camera stays fixed throughout the scenario")
	await RenderingServer.frame_post_draw
	var label := ("torso" if torso_fixture else "side")+"-"+scenario
	root.get_texture().get_image().save_png(args[0].path_join("pass-"+label+".png"))
	_mouse(last_pointer, false)
	await process_frame
	_check(app.interaction_manager._rope_interaction.get_pass_state() == RopePassAssist.State.FREE, "release clears transient guidance")
	print("Pass integration failures: ", failures)
	_write_report({"status":"passed" if failures == 0 else "failed","scope":"controlled fixed aperture; not player-created loop or net", "fixture_revision":2,"scenario":scenario,"torso":torso_fixture,"active_seen":active_seen,"forward_crossing":crossed_inside,"reverse_crossing":reverse_crossed_inside,"peak_segment_error":worst_stretch,"body_clear_throughout":body_clear_throughout,"body_tolerance_m":0.0005,"failures":failures})
	quit(1 if failures else 0)


func _mouse(position: Vector2, pressed: bool) -> void:
	last_pointer = position
	var event := InputEventMouseButton.new()
	event.device = ReplayInputGuard.DEVICE
	event.position = root.get_final_transform() * position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)


func _record_crossing() -> void:
	var points := app.rope.get_simulation().get_positions()
	for i in points.size()-1:
		if not app.rope.get_collision().is_body_segment_clear(points[i],points[i+1],app.rope.config.radius-0.0005): body_clear_throughout = false
	var current := app.rope.get_simulation().get_point(0)
	if RopePassCandidates.crosses_aperture(previous_actual, current, aperture, app.rope.config.radius):
		if (current-previous_actual).dot(aperture.normal)*forward_sign > 0:
			crossed_inside = true
		else:
			reverse_crossed_inside = true
	previous_actual = current

func _write_report(report: Dictionary) -> void:
	var file := FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()


func _motion(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.device = ReplayInputGuard.DEVICE
	event.position = root.get_final_transform() * position
	event.relative = root.get_final_transform().basis_xform(position-last_pointer)
	last_pointer = position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)


func _check(condition: bool, message: String) -> void:
	print("PASS " if condition else "FAIL ", message)
	if not condition:
		failures += 1
