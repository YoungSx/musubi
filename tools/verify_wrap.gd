extends SceneTree
## Reproducible full-mannequin wrap with simultaneous obstacle/self contacts.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var app := load("res://scenes/main/main.tscn").instantiate() as AppController
	root.add_child(app)
	app.rope.visible = false
	app.rope.set_held(true)
	var renderer := RopeRenderer.new()
	renderer.material_override = load("res://assets/materials/rope.tres")
	app.add_child(renderer)
	var config := RopeConfig.new()
	config.gravity = Vector3(0, -0.98, 0)
	config.damping = 6.0
	var points := PackedVector3Array()
	for i in config.segment_count + 1:
		var angle := TAU * 1.2 * float(i) / config.segment_count
		points.append(Vector3(0.36 * sin(angle), 1.05 + 0.1 * angle / TAU, 0.36 * cos(angle)))
	config.length = RopeLayout.polyline_length(points)
	var simulation := RopeSimulation.new(config, points)
	simulation.set_collision(app.rope.get_collision())
	simulation.pin(0, points[0])
	simulation.begin_drag(config.segment_count)
	var least_world := INF
	var least_self := INF
	var stretch := 0.0
	for step in 600:
		if step < 360:
			simulation.update_drag_target(points[-1] + Vector3(-0.22, 0.12, -0.2) * float(step + 1) / 360.0)
		elif step == 360:
			simulation.end_drag()
		simulation.step(config.get_time_step())
		stretch = maxf(stretch, simulation.get_max_segment_stretch())
		var current := simulation.get_positions()
		least_self = minf(least_self, SelfCollisionFixture.clearance(current, config))
		for i in current.size() - 1:
			for sample in 5:
				least_world = minf(least_world, app.rope.get_collision().get_clearance(current[i].lerp(current[i + 1], float(sample) / 4.0)))
		if step in [0, 359, 599] and not args.is_empty():
			renderer.update_mesh(current, config.radius)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(args[0].path_join("wrap-%d.png" % step))
	print("Wrap: world clearance=", least_world, " radius=", config.radius, " self gap=", least_self, " max stretch=", stretch)
	quit(0 if least_world >= config.radius * 0.9 and least_self >= config.radius * 1.8 and stretch < 0.08 else 1)
