extends SceneTree
## Screen-space attempt at repeated torso lacing. No prebuilt net, depth input,
## camera motion, hidden-coordinate steering or simulation position writes.
var app: AppController
var pointer := Vector2(865,651)
var peak_stretch := 0.0
var least_clearance := INF
var rear_distance := 0.0
var _previous := Vector3.ZERO
var _rear_before := false
var _output := ""
var _duration_scale := 1.0
var pass_frames := 0
var phase := "lift"
var samples: Array[String] = ["phase,time_us,pointer_x,pointer_y,target_x,target_y,actual_x,actual_y,actual_z,active,rear,rim,exit_seen,via_pending,pass_state,hand_gap,goal_gap,route_x,route_y,route_z,requested_x,requested_y,requested_z"]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_output = OS.get_cmdline_user_args()[0]
	if OS.get_cmdline_user_args().size() > 1: _duration_scale = float(OS.get_cmdline_user_args()[1])
	app = load("res://scenes/main/play.tscn").instantiate()
	root.add_child(app)
	ReplayInputGuard.install(self)
	app.new_rope(6.0)
	app.hud.visible = false
	for i in 120: await process_frame
	var view := app.camera_rig.capture_state()
	await _capture("lattice-start")
	_button(true)
	await process_frame
	if app.interaction_manager.get_selected_index() < 0:
		printerr("FAIL endpoint pickup")
		quit(1)
		return
	_previous = app.rope.get_simulation().get_grip_position()
	for goal in [Vector2(800,630),Vector2(740,600),Vector2(690,570),Vector2(680,500),Vector2(670,420),Vector2(660,300)]:
		await _drag(goal,1.5)
	await _capture("lattice-lifted")
	# Alternate sweeps across the silhouette, then diagonals at successive heights.
	var step := 0
	for goal in [Vector2(595,300),Vector2(560,300),Vector2(595,300),Vector2(690,300),Vector2(730,300),Vector2(690,315),Vector2(600,345),Vector2(555,345),Vector2(600,345),Vector2(690,345),Vector2(730,345),Vector2(690,360),Vector2(600,395),Vector2(555,395),Vector2(600,395),Vector2(690,395),Vector2(730,395),Vector2(665,375),Vector2(600,330),Vector2(670,290)]:
		phase = "stroke_%d" % (step+1)
		await _drag(goal,1.5)
		step += 1
		print("Lacing step=",step," actual=",app.rope.get_simulation().get_grip_position()," rear intent=",app.interaction_manager._rope_interaction._surface_intent.rear," peak stretch=",peak_stretch)
		if step%5 == 0: await _capture("lattice-step-%d" % step)
	_button(false)
	await create_timer(3).timeout
	await _capture("lattice-released")
	var retained := 0.0
	var points := app.rope.get_simulation().get_positions()
	for i in points.size()-1:
		if minf(points[i].y,points[i+1].y) > 0.8: retained += points[i].distance_to(points[i+1])
	var report := {"scope":"mouse-driven full-mannequin lacing attempt; visual topology review required",
		"gesture_duration_scale":_duration_scale,"spatial_pass_active_frames":pass_frames,
		"peak_segment_error":peak_stretch,"grip_body_clearance":least_clearance,
		"actual_rear_travel":rear_distance,"rope_above_waist_after_release":retained,
		"camera_unchanged":app.camera_rig.capture_state()==view,
		"complete_pattern":"not certified by motion or height metrics; inspect crossings and cells"}
	var file := FileAccess.open(_output.path_join("lattice-input-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	file = FileAccess.open(_output.path_join("lattice-input-trace.csv"),FileAccess.WRITE)
	file.store_string("\n".join(samples)+"\n")
	file.close()
	MusubiSceneState.write_file(_output.path_join("lattice-attempt.musubi"),MusubiSceneState.capture(app))
	print(JSON.stringify(report))
	# Inspection after measurement only: compare the same state from the rear.
	app.process_mode = Node.PROCESS_MODE_DISABLED
	app.camera_rig.turn_around()
	app.camera_rig._process(10)
	await _capture("lattice-inspection-back")
	quit()

func _button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.device = ReplayInputGuard.DEVICE
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = pointer*Vector2(root.size)/Vector2(1280,800)
	Input.parse_input_event(event)

func _drag(goal: Vector2,duration: float) -> void:
	duration *= _duration_scale
	var start := pointer
	var began := Time.get_ticks_usec()
	while true:
		var weight := minf(float(Time.get_ticks_usec()-began)/1000000.0/duration,1)
		var next := start.lerp(goal,weight)
		var event := InputEventMouseMotion.new()
		event.device = ReplayInputGuard.DEVICE
		event.position = next*Vector2(root.size)/Vector2(1280,800)
		event.relative = (next-pointer)*Vector2(root.size)/Vector2(1280,800)
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(event)
		pointer = next
		await process_frame
		var sim := app.rope.get_simulation()
		if app.interaction_manager._rope_interaction.get_pass_state() != RopePassAssist.State.FREE: pass_frames += 1
		var actual := sim.get_grip_position()
		var interaction := app.interaction_manager._rope_interaction
		var intent := interaction._surface_intent
		var screen_target := app.camera_rig.get_camera().unproject_position(sim.get_drag_target())
		samples.append("%s,%d,%f,%f,%f,%f,%f,%f,%f,%s,%s,%s,%s,%s,%d,%f,%f,%f,%f,%f,%f,%f,%f" % [phase,Time.get_ticks_usec(),pointer.x,pointer.y,screen_target.x,screen_target.y,actual.x,actual.y,actual.z,intent.active,intent.rear,intent._rim,intent._rim_exit_seen,intent._via_pending,interaction.get_pass_state(),actual.distance_to(sim.get_drag_target()),actual.distance_to(intent.requested_goal),intent._target.x,intent._target.y,intent._target.z,intent.requested_goal.x,intent.requested_goal.y,intent.requested_goal.z])
		peak_stretch = maxf(peak_stretch,sim.get_max_segment_stretch())
		least_clearance = minf(least_clearance,app.rope.get_collision().get_body_clearance(actual))
		var in_rear := actual.y > 0.8 and actual.y < 1.45 and actual.z < -0.06 and absf(actual.x) < 0.22
		if in_rear and _rear_before: rear_distance += actual.distance_to(_previous)
		_rear_before = in_rear
		_previous = actual
		if weight >= 1: break

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_output.path_join(label+".png"))
