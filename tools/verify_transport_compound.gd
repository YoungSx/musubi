extends SceneTree
## Controlled compound-knot solver/intent fixture, NOT a mouse-created knot.
## Kept separate from the actual-input single-knot acceptance replay.
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var output := OS.get_cmdline_user_args()[0]
	var app := load("res://scenes/main/play.tscn").instantiate() as AppController
	root.add_child(app)
	ReplayInputGuard.install(self)
	app.process_mode = Node.PROCESS_MODE_DISABLED
	app.handle_action(&"ground")
	app.new_rope(6.0)
	app.hud.visible = false
	var path := PackedVector3Array()
	for knot in 2:
		for p in SelfCollisionFixture.trefoil(144):
			var sign_x := 1.0 if knot == 0 else -1.0
			path.append(Vector3(p.x*sign_x+(-0.5 if knot == 0 else 0.5),0.11+p.z,(p.y-1.1)*sign_x+2.0))
	var points := RopeLayout.resample(path,192)
	var config := app.rope.config.duplicate() as RopeConfig
	config.length = RopeLayout.polyline_length(points)
	var sim := RopeSimulation.new(config,points)
	sim.set_collision(app.rope.get_collision())
	for i in 60: sim.step(config.get_time_step())
	var scene := app.rope.capture_scene_state()
	scene.simulation = sim.capture_state()
	app.rope.restore_scene_state(scene)
	sim = app.rope.get_simulation()
	var initial_word := RopeTransport.crossing_word(sim.get_positions(),config.radius)
	_check(initial_word.size() >= 12,"fixture retains at least six nontrivial crossings")
	await _capture(app,output,"compound-before")
	var transport := RopeTransport.new()
	transport.begin(sim.get_positions(),1,config.radius,0,app.rope.get_collision())
	_check(transport.eligible,"compound geometry can supply a transport guide")
	sim.begin_grip(1)
	var camera := app.camera_rig.get_camera()
	var end := sim.get_point_count()-1
	var axis := (camera.unproject_position(sim.get_point(end-1))-camera.unproject_position(sim.get_point(end))).normalized()
	var peak_stretch := 0.0
	var gap := INF
	var started := Time.get_ticks_usec()
	for step in 1200:
		var targets := transport.update(axis*2,camera,sim.get_positions(),config.radius,1.0/60)
		sim.set_transport_targets(targets)
		if not targets.is_empty(): sim.update_drag_target(targets[-1])
		sim.step(1.0/60)
		peak_stretch = maxf(peak_stretch,sim.get_max_segment_stretch())
		if step%30 == 0:
			gap = minf(gap,SelfCollisionFixture.clearance(sim.get_positions(),config))
		if step%120 == 0:
			print("Compound step=",step," progress=",transport.progress," word=",RopeTransport.crossing_word(sim.get_positions(),config.radius))
			if not targets.is_empty():
				var worst := 0
				for i in targets.size():
					if sim.get_point(i).distance_to(targets[i]) > sim.get_point(worst).distance_to(targets[worst]): worst = i
				print("Guide lag particle=",worst," actual=",sim.get_point(worst)," target=",targets[worst]," clearance=",app.rope.get_collision().get_clearance(targets[worst]))
			await process_frame
		if transport.progress > config.length*0.9: break
	sim.release_grip()
	for step in 120: sim.step(1.0/60)
	var final_word := RopeTransport.crossing_word(sim.get_positions(),config.radius,false)
	await _capture(app,output,"compound-after")
	_check(final_word.is_empty(),"both knots unthread and stay clear after release")
	_check(peak_stretch < 0.05,"compound segment length error stays below five percent")
	_check(gap >= config.radius*1.8,"compound sampled clearance remains bounded")
	_check(not sim.has_transport_targets(),"release clears compound guidance")
	var report := {"scope":"prearranged two-knot fixture, not player-created","length":config.length,
		"initial_word":initial_word,"final_word":final_word,"peak_stretch":peak_stretch,
		"sampled_clearance":gap,"elapsed_ms":(Time.get_ticks_usec()-started)/1000.0,"failures":failures}
	var file := FileAccess.open(output.path_join("compound-report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print(JSON.stringify(report))
	quit(1 if failures else 0)

func _capture(app: AppController,output: String,label: String) -> void:
	app.rope._refresh_mesh()
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output.path_join(label+".png")) == OK,"capture "+label)

func _check(condition: bool,message: String) -> void:
	print("PASS " if condition else "FAIL ",message)
	if not condition: failures += 1
