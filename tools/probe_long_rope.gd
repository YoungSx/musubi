extends SceneTree
## Complex-case feasibility probe. Prearranged geometry is explicitly a solver
## stress fixture, never counted as a knot tied through player input.
var app: AppController

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var output := OS.get_cmdline_user_args()[0]
	app = load("res://scenes/main/play.tscn").instantiate()
	root.add_child(app)
	ReplayInputGuard.install(self)
	app.process_mode = Node.PROCESS_MODE_DISABLED
	app.new_rope(6.0)
	var raw := PackedVector3Array()
	# Continuous counterwound lacing with short vertical runs at each junction.
	# This fixture tests contact density around the real torso/arms, not knot type.
	for leg in 2:
		for i in range(145):
			var t := float(i)/144
			var angle := t*TAU*3
			var y := lerpf(1.38,0.86,t) if leg == 0 else lerpf(0.86,1.38,t)
			var radius: float = 0.19 + (0.029 if leg == 1 else 0)
			raw.append(Vector3(sin(angle)*radius,y,cos(angle)*radius))
	var points := RopeLayout.resample(raw,192)
	var config := RopeConfig.for_length(6.0)
	config.length = RopeLayout.polyline_length(points)
	config.drag_compliance = 0.00008
	config.friction = 0.35
	var sim := RopeSimulation.new(config,points)
	sim.set_collision(app.rope.get_collision())
	var fixture := app.rope.capture_scene_state()
	fixture.simulation = sim.capture_state()
	fixture.held = false
	app.rope.restore_scene_state(fixture)
	app.hud.visible = false
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("lattice-initial.png"))
	var start := Time.get_ticks_usec()
	var peak_stretch := 0.0
	var simulation_usec := 0
	for i in 300:
		var before := Time.get_ticks_usec()
		app.rope.advance(1.0/60)
		simulation_usec += Time.get_ticks_usec()-before
		peak_stretch = maxf(peak_stretch,app.rope.get_simulation().get_max_segment_stretch())
		if i%30 == 0:
			app.rope._refresh_mesh()
			await process_frame
	var elapsed := (Time.get_ticks_usec()-start)/1000.0
	app.rope._refresh_mesh()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("lattice-settled.png"))
	var clearance := INF
	var positions := app.rope.get_simulation().get_positions()
	for i in positions.size()-1:
		for sample in 5:
			clearance = minf(clearance,app.rope.get_collision().get_clearance(positions[i].lerp(positions[i+1],float(sample)/4)))
	var report := {"fixture":"prearranged counterwound torso lattice; not mouse-tied", "length":config.length,
		"simulation_ms_per_step":simulation_usec/300000.0,
		"segments":192,"simulated_seconds":5,"wall_ms":elapsed,"peak_stretch":peak_stretch,
		"final_stretch":app.rope.get_simulation().get_max_segment_stretch(),"sampled_body_clearance":clearance,
		"minimum_y":positions[0].y,"maximum_y":positions[0].y}
	for point in positions:
		report.minimum_y = minf(report.minimum_y,point.y)
		report.maximum_y = maxf(report.maximum_y,point.y)
	var file := FileAccess.open(output.path_join("lattice-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print(JSON.stringify(report))
	quit()
