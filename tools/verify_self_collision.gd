extends SceneTree
## Rendered figure-eight drag/release fixture and same-process timing comparison.
var failures := 0

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		quit(1)
		return
	var output := args[0]
	var app := load("res://scenes/main/main.tscn").instantiate() as AppController
	root.add_child(app)
	app.rope.set_held(true)
	app.mannequin.visible = false
	app.rope.visible = false
	var renderer := RopeRenderer.new()
	renderer.material_override = load("res://assets/materials/rope.tres")
	app.add_child(renderer)
	var points := SelfCollisionFixture.points()
	var config := RopeConfig.new()
	config.length = RopeLayout.polyline_length(points)
	config.gravity = Vector3.ZERO
	config.radius = 0.02
	config.damping = 6.0
	var sim := RopeSimulation.new(config, points)
	sim.pin(0, points[0])
	sim.pin(config.segment_count, points[-1])
	var worst_stretch := 0.0
	var least_clearance := INF
	for frame in 360:
		if frame == 60:
			sim.begin_drag(24)
		if frame >= 60 and frame < 180:
			sim.update_drag_target(points[24] + Vector3(0.06, 0.03, -0.08) * float(frame - 59) / 120.0)
		if frame == 180:
			sim.end_drag()
		sim.step(config.get_time_step())
		worst_stretch = maxf(worst_stretch, sim.get_max_segment_stretch())
		if frame > 20:
			least_clearance = minf(least_clearance, SelfCollisionFixture.clearance(sim.get_positions(), config))
		if frame in [59, 179, 359]:
			renderer.update_mesh(sim.get_positions(), config.radius)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("self-contact-%d.png" % frame))
	print("Figure eight: min clearance=", least_clearance, " diameter=", 2 * config.radius, " worst stretch=", worst_stretch)
	if least_clearance < config.radius * 1.9 or worst_stretch > 0.08:
		failures += 1
	for enabled in [false, true]:
		var preset := load("res://data/rope/default_rope.tres").duplicate() as RopeConfig
		preset.self_collision_enabled = enabled
		var initial := RopeLayout.hanging(Vector3(0.55, 1.45, 0.12), Vector3(-0.55, 1.45, 0.12), preset.length, preset.segment_count)
		var benchmark := RopeSimulation.new(preset, initial)
		benchmark.pin(0, initial[0])
		benchmark.pin(preset.segment_count, initial[-1])
		var obstacles := RopeCollision.new()
		obstacles.configure(load("res://data/mannequin/default_mannequin.tres"))
		benchmark.set_collision(obstacles)
		for warmup in 60:
			benchmark.step(preset.get_time_step())
		var timings: Array[float] = []
		for frame in 240:
			var start := Time.get_ticks_usec()
			benchmark.step(preset.get_time_step())
			timings.append(float(Time.get_ticks_usec() - start) / 1000.0)
		timings.sort()
		print("Default scene self_collision=", enabled, " median ms=", timings[120], " p95 ms=", timings[227])
	print("Self collision smoke failures: ", failures)
	quit(1 if failures else 0)
