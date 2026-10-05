extends SceneTree
## One minute of rendered operation across all lengths, fullscreen transitions
## and window sizes. Run separately from other rendered automation/profiling.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var app := load("res://scenes/main/main.tscn").instantiate() as AppController
	root.add_child(app)
	var failures := 0
	var memory_before := 0.0
	var objects_before := 0.0
	for length_m in [1.4, 2.2, 3.0]:
		app.new_rope(length_m)
		for frame in 120:
			await process_frame
		if memory_before == 0:
			memory_before = Performance.get_monitor(Performance.MEMORY_STATIC)
			objects_before = Performance.get_monitor(Performance.OBJECT_COUNT)
		app.get_node("PerformanceCapture").recorder.reset()
		for frame in 1200:
			if frame in [300, 600]:
				var key := InputEventKey.new()
				key.keycode = KEY_F11
				key.pressed = true
				Input.parse_input_event(key)
				key = key.duplicate()
				key.pressed = false
				Input.parse_input_event(key)
			if frame == 800:
				root.size = Vector2i(960, 640)
			if frame == 1000:
				root.size = Vector2i(1280, 800)
			await process_frame
		var summary: Dictionary = app.get_node("PerformanceCapture").recorder.summary()
		print("Rendered stability ", length_m, "m: ", summary)
		if (length_m == 1.4 and summary.fps < 55) or summary.fps < 30:
			failures += 1
		for point in app.rope.get_simulation().get_positions():
			if not point.is_finite():
				failures += 1
	var growth := Performance.get_monitor(Performance.MEMORY_STATIC) - memory_before
	var objects := Performance.get_monitor(Performance.OBJECT_COUNT) - objects_before
	print("Rendered stability memory growth bytes=", growth, " live object growth=", objects)
	if growth > 8 * 1024 * 1024 or objects > 32:
		failures += 1
	print("Rendered stability failures: ", failures)
	quit(1 if failures else 0)
