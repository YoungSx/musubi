extends SceneTree
## CPU/frame and bounded-memory stress. Run headless or rendered on the same host.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var app := load("res://scenes/main/main.tscn").instantiate() as AppController
	root.add_child(app)
	app.process_mode = Node.PROCESS_MODE_DISABLED
	var report := {}
	var failures := 0
	for length_m in [1.4, 2.2, 3.0]:
		app.new_rope(length_m)
		for frame in 120:
			app.rope._process(1.0 / 60.0)
		var timings: Array[float] = []
		var worst_stretch := 0.0
		for frame in 360:
			if frame == 30:
				app.rope.begin_drag(0)
			if frame >= 30 and frame < 240:
				app.rope.update_drag_target(Vector3(0.35 * cos(frame * 0.015), 1.3, 0.35 * sin(frame * 0.015)))
			if frame == 240:
				app.rope.end_drag()
				app.rope.set_held(false)
			app.rope._process(1.0 / 60.0)
			timings.append(app.rope.get_last_simulation_ms() + app.rope.get_last_mesh_ms())
			worst_stretch = maxf(worst_stretch, app.rope.get_simulation().get_max_segment_stretch())
			for point in app.rope.get_simulation().get_positions():
				if not point.is_finite():
					failures += 1
		timings.sort()
		report[str(length_m)] = {"cpu_median_ms": timings[180], "cpu_p95_ms": timings[341], "max_stretch": worst_stretch}
		print(length_m, "m: ", report[str(length_m)])
	# Saturate bounded history, then check repeated creation/reset does not keep
	# increasing live object count or grow memory by more than allocator slack.
	for edit in 40:
		app.handle_action(&"attachment_a")
	var memory_before := Performance.get_monitor(Performance.MEMORY_STATIC)
	var objects_before := Performance.get_monitor(Performance.OBJECT_COUNT)
	for cycle in 50:
		app.new_rope([1.4, 2.2, 3.0][cycle % 3])
		app.rope._process(1.0 / 60.0)
		app.handle_action(&"attachment_a")
		app.handle_action(&"undo")
		app.handle_action(&"redo")
		app.reset()
	var memory_growth := Performance.get_monitor(Performance.MEMORY_STATIC) - memory_before
	var objects_growth := Performance.get_monitor(Performance.OBJECT_COUNT) - objects_before
	print("Stress memory growth bytes=", memory_growth, " objects=", objects_growth, " history entries=", app.history.get_entry_count(), " encoded bytes=", app.history.get_encoded_bytes())
	if memory_growth > 8 * 1024 * 1024 or objects_growth > 32 or app.history.get_entry_count() > RopeHistory.MAX_ENTRIES:
		failures += 1
	print("Creation stress failures: ", failures)
	quit(1 if failures else 0)
