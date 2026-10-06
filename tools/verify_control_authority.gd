extends SceneTree
## Negative/control-authority scenarios; no knot completion objective.
var app: AppController
var pointer := Vector2(865,651)
var failures := 0
var samples: Array[String] = ["phase,time_us,pointer_x,pointer_y,target_x,target_y,grip_x,grip_y,surface,rear"]
var phase := "lift"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var output := OS.get_cmdline_user_args()[0]
	app = load("res://scenes/main/play.tscn").instantiate()
	root.add_child(app)
	ReplayInputGuard.install(self)
	app.new_rope(6)
	app.hud.visible = false
	for i in 120: await process_frame
	_button(true)
	await process_frame
	_check(app.interaction_manager.get_selected_index() >= 0,"capture visible rope")
	for goal in [Vector2(800,630),Vector2(740,600),Vector2(690,570),Vector2(680,500),Vector2(670,420),Vector2(665,350)]: await _drag(goal,1.5)
	var sim := app.rope.get_simulation()
	var intent := app.interaction_manager._rope_interaction._surface_intent
	_check(intent.active,"sustained approach can acquire surface assistance")
	_check(not intent.rear,"front approach remains on the visible side")
	phase = "stop"
	var before := sim.get_drag_target()
	for i in 60:
		await process_frame
		_record()
	_check(sim.get_drag_target().distance_to(before) < 0.00001,"stopping cannot advance new waypoints")
	phase = "front_correction"
	var side := intent.rear
	for goal in [Vector2(660,350),Vector2(667,350),Vector2(663,350)]:
		await _drag(goal,0.15)
		_check(intent.rear == side,"small front correction does not become a rear wrap")
	phase = "escape"
	await _drag(Vector2(900,350),1)
	_check(not intent.active,"dragging off the object releases attraction without a key")
	phase = "free_forward"
	var start_target := app.camera_rig.get_camera().unproject_position(sim.get_drag_target())
	await _drag(Vector2(1000,350),0.5)
	var finish_target := app.camera_rig.get_camera().unproject_position(sim.get_drag_target())
	_check(finish_target.x > start_target.x+30,"escaped target follows continued rightward input")
	_check(finish_target.distance_to(app.interaction_manager._rope_interaction._last_screen_position) < 3,"continued free movement sheds the old magnet offset")
	phase = "free_reverse"
	await _drag(Vector2(900,350),0.5)
	_check(app.camera_rig.get_camera().unproject_position(sim.get_drag_target()).x < finish_target.x-30,"free reversal is not resisted by the old surface")
	_button(false)
	await process_frame
	_check(sim.get_drag_index() == -1 and not intent.active,"release clears all hand assistance")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("authority-released.png"))
	var file := FileAccess.open(output.path_join("control-authority.csv"),FileAccess.WRITE)
	file.store_string("\n".join(samples)+"\n")
	file.close()
	print("Control-authority failures: ",failures)
	quit(1 if failures else 0)

func _drag(goal: Vector2,duration: float) -> void:
	var start := pointer
	var began := Time.get_ticks_usec()
	while true:
		var weight := minf(float(Time.get_ticks_usec()-began)/1000000.0/duration,1)
		var point := start.lerp(goal,weight)
		var event := InputEventMouseMotion.new()
		event.device = ReplayInputGuard.DEVICE
		event.position = point*Vector2(root.size)/Vector2(1280,800)
		event.relative = (point-pointer)*Vector2(root.size)/Vector2(1280,800)
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(event)
		pointer = point
		await process_frame
		_record()
		if weight >= 1: break

func _record() -> void:
	var interaction := app.interaction_manager._rope_interaction
	var camera := app.camera_rig.get_camera()
	var sim := app.rope.get_simulation()
	var target := camera.unproject_position(sim.get_drag_target())
	var grip := camera.unproject_position(sim.get_grip_position())
	var cursor := interaction._last_screen_position
	samples.append("%s,%d,%f,%f,%f,%f,%f,%f,%s,%s" % [phase,Time.get_ticks_usec(),cursor.x,cursor.y,target.x,target.y,grip.x,grip.y,interaction._surface_intent.active,interaction._surface_intent.rear])

func _button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.device = ReplayInputGuard.DEVICE
	event.position = pointer*Vector2(root.size)/Vector2(1280,800)
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)

func _check(condition: bool,message: String) -> void:
	print("PASS " if condition else "FAIL ",message)
	if not condition: failures += 1
