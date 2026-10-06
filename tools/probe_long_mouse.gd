extends SceneTree
## Ordinary input feasibility attempt, kept separate from geometric fixtures.
var app: AppController
var pointer := Vector2(865,651)
var peak_stretch := 0.0
var rear_seen := false
var peak_height := 0.0
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var output := OS.get_cmdline_user_args()[0]
	app = load("res://scenes/main/play.tscn").instantiate() as AppController
	root.add_child(app)
	ReplayInputGuard.install(self)
	app.new_rope(6.0)
	app.hud.visible = false
	for i in 120: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("long-mouse-start.png"))
	print("Long rope initialization stretch=",app.rope.get_simulation().get_max_segment_stretch())
	var button := InputEventMouseButton.new()
	button.device = ReplayInputGuard.DEVICE
	button.position = pointer*Vector2(root.size)/Vector2(1280,800)
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = true
	Input.parse_input_event(button)
	await process_frame
	if app.interaction_manager.get_selected_index() < 0:
		printerr("Visible long-rope endpoint pickup failed")
		quit(1)
		return
	for destination in [Vector2(800,630),Vector2(740,600),Vector2(690,570),Vector2(680,500),Vector2(670,420),Vector2(665,350),Vector2(600,350),Vector2(565,350),Vector2(600,350),Vector2(665,350),Vector2(700,370),Vector2(660,400)]:
		var start := pointer
		for frame in 90:
			var point := start.lerp(destination,float(frame+1)/90)
			var event := InputEventMouseMotion.new()
			event.device = ReplayInputGuard.DEVICE
			event.position = point*Vector2(root.size)/Vector2(1280,800)
			event.relative = (point-pointer)*Vector2(root.size)/Vector2(1280,800)
			event.button_mask = MOUSE_BUTTON_MASK_LEFT
			Input.parse_input_event(event)
			pointer = point
			await process_frame
			peak_stretch = maxf(peak_stretch,app.rope.get_simulation().get_max_segment_stretch())
			peak_height = maxf(peak_height,app.rope.get_simulation().get_grip_position().y)
			rear_seen = rear_seen or app.interaction_manager._rope_interaction._surface_intent.rear
		print("Body attempt ",pointer," tip=",app.rope.get_simulation().get_grip_position()," surface=",app.interaction_manager._rope_interaction._surface_intent.active," rear=",rear_seen)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("body-%d-%d.png" % [pointer.x,pointer.y]))
	button = button.duplicate()
	button.pressed = false
	button.position = pointer*Vector2(root.size)/Vector2(1280,800)
	Input.parse_input_event(button)
	for i in 120: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("body-release.png"))
	print("Body mouse probe peak stretch=",peak_stretch," rear intent seen=",rear_seen)
	var report := {"scope":"mouse-only endpoint lift and surface approach, not complete lacing",
		"peak_height":peak_height,"peak_stretch":peak_stretch,"rear_intent_seen":rear_seen,
		"lift_acceptance":peak_height > 1.0 and peak_stretch < 0.08,
		"complete_lattice_acceptance":"not achieved; see release screenshot"}
	var file := FileAccess.open(output.path_join("body-mouse-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	quit(0 if report.lift_acceptance else 1)
