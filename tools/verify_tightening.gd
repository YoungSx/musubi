extends SceneTree
## Open trefoil tightening/release stress test. Optional output directory renders
## checkpoints; without it, this runs headless and prints quantitative results.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var renderer: RopeRenderer
	if not args.is_empty():
		var app := load("res://scenes/main/main.tscn").instantiate() as AppController
		root.add_child(app)
		app.rope.visible = false
		app.rope.set_held(true)
		app.mannequin.visible = false
		renderer = RopeRenderer.new()
		renderer.material_override = load("res://assets/materials/rope.tres")
		app.add_child(renderer)
	var points := SelfCollisionFixture.trefoil()
	var config := RopeConfig.new()
	config.segment_count = points.size() - 1
	config.length = RopeLayout.polyline_length(points)
	config.gravity = Vector3.ZERO
	config.damping = 6.0
	config.radius = 0.012
	var simulation := RopeSimulation.new(config, points)
	simulation.pin(0, points[0])
	simulation.begin_drag(config.segment_count)
	var minimum := INF
	var stretch := 0.0
	var rendered_minimum := INF
	var start := Time.get_ticks_usec()
	for step in 600:
		if step < 360:
			simulation.update_drag_target(points[-1] + Vector3(1.5, -2.0, 0.75) * float(step + 1) / 360.0)
		elif step == 360:
			simulation.end_drag()
		simulation.step(config.get_time_step())
		minimum = minf(minimum, SelfCollisionFixture.clearance(simulation.get_positions(), config))
		stretch = maxf(stretch, simulation.get_max_segment_stretch())
		if step in [0, 179, 359, 599]:
			print("Checkpoint ", step, " gap=", SelfCollisionFixture.clearance(simulation.get_positions(), config), " stretch=", simulation.get_max_segment_stretch())
			if renderer != null:
				renderer.update_mesh(simulation.get_positions(), config.radius)
				var rendered_gap := SelfCollisionFixture.rendered_clearance(renderer._centers, config, renderer.subdivisions)
				rendered_minimum = minf(rendered_minimum, rendered_gap)
				print("Rendered gap=", rendered_gap)
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(args[0].path_join("tightening-%d.png" % step))
	print("Tightening min gap=", minimum, " diameter=", config.radius * 2.0, " max stretch=", stretch, " wall ms=", (Time.get_ticks_usec() - start) / 1000.0)
	quit(0 if minimum >= config.radius * 1.9 and rendered_minimum >= config.radius * 1.9 and stretch < 0.08 else 1)
