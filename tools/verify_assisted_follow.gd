extends SceneTree
## Rendered acceptance: real touch events against the play scene in portrait.
var app: AppController
var output := ""
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	output = OS.get_cmdline_user_args()[0]
	root.gui_embed_subwindows = true
	app = load("res://scenes/main/play.tscn").instantiate()
	root.add_child(app)
	ReplayInputGuard.install(self)
	root.min_size = Vector2i.ZERO
	root.size = Vector2i(390, 844)
	root.content_scale_factor = 1.0
	root.content_scale_size = Vector2i(390, 844)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	await _frames(8)
	_check(app.camera_rig.mode == CameraRig.Mode.ASSISTED, "new scene defaults to assisted follow")
	var sim := app.rope.get_simulation()
	var start := app.camera_rig.get_camera().unproject_position(sim.get_point(0))
	_touch(start, true)
	await _frames(1)
	_check(sim.get_drag_index(0) >= 0, "visible endpoint acquired through touch input")
	if failures: quit(1); return
	var initial_focus := app.camera_rig.get_target_focus()
	var initial_yaw := app.camera_rig.get_target_yaw()
	await _capture("follow-start")
	var destination := Vector2(374, start.y - 40)
	for frame in 180:
		_drag(start.lerp(destination, float(frame + 1) / 180.0))
		await process_frame
	_check(app.camera_rig.get_target_focus().distance_to(initial_focus) > 0.02 or absf(app.camera_rig.get_target_yaw() - initial_yaw) > 0.02, "camera assists extended screen-edge drag")
	await _capture("follow-edge")
	var target := sim.get_drag_target(0)
	await _frames(60)
	_drag(destination)
	await _frames(1)
	_check(sim.get_drag_target(0).distance_to(target) < 0.0001, "automatic camera motion does not move stationary hand target")
	var settled := app.camera_rig.get_target_transform()
	await _frames(45)
	_check(app.camera_rig.get_target_transform().is_equal_approx(settled), "idle hand does not drive endless camera correction")
	app.hud._play_menu_selected(7)
	_check(sim.get_grip_count() == 1, "switching camera mode retains grip")
	var free_pose := app.camera_rig.get_target_transform()
	for frame in 30:
		_drag(destination + Vector2(-float(frame + 1), -float(frame + 1)))
		await process_frame
	_check(app.camera_rig.get_target_transform().is_equal_approx(free_pose), "free mode preserves camera during rope drag")
	_touch(destination, false)
	await _frames(1)
	_check(sim.get_grip_count() == 0, "release dispatched before opening menu")
	app.hud._play_menu_selected(6)
	var popup: PopupMenu = app.hud.get_node("%PlayMenu").get_popup()
	popup.popup(Rect2i(40, 80, 310, 370))
	await _frames(4)
	await _capture("follow-menu")
	popup.hide()
	var save_path := output.path_join("follow-mode.musubi")
	var save_error := app.save_creation(save_path)
	_check(save_error == OK, "assisted scene saves: " + error_string(save_error))
	app.camera_rig.set_mode(CameraRig.Mode.FREE)
	_check(app.load_creation(save_path) and app.camera_rig.mode == CameraRig.Mode.ASSISTED, "file load restores saved camera mode")
	print("Assisted follow failures: ", failures)
	quit(1 if failures else 0)


func _touch(position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.device = ReplayInputGuard.DEVICE
	event.index = 0
	event.position = position
	event.pressed = pressed
	Input.parse_input_event(event)


func _drag(position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.device = ReplayInputGuard.DEVICE
	event.index = 0
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
