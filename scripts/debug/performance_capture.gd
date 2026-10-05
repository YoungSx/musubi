class_name PerformanceCapture
extends Node
## Records after scene simulation/mesh updates. Exports are explicit user actions.

var recorder := PerformanceRecorder.new()
var rope: Rope
var last_report_path := ""
var _last_frame_usec := 0


func _ready() -> void:
	process_priority = 100


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if rope != null and _last_frame_usec > 0:
		recorder.record(float(now - _last_frame_usec) / 1000000.0, rope.get_last_simulation_ms(), rope.get_last_mesh_ms())
	_last_frame_usec = now


func export_report(directory: String, scene_state: Dictionary = {}) -> Error:
	last_report_path = ""
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return error
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var base := directory.path_join("musubi-%s-%d" % [stamp, Time.get_ticks_usec()])
	error = recorder.write_csv(base + ".csv")
	if error != OK:
		return error
	var report := {
		"schema_version": 1,
		"recorded_at": Time.get_datetime_string_from_system(),
		"application_version": ProjectSettings.get_setting("application/config/version", "dev"),
		"engine": Engine.get_version_info().string,
		"platform": OS.get_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"window_size": [get_window().size.x, get_window().size.y],
		"ui_scale": get_window().content_scale_factor,
		"debug_build": OS.is_debug_build(),
		"summary": recorder.summary(),
		"samples_file": (base + ".csv").get_file(),
		"scene": scene_state,
		"measurement": "Monotonic wall-clock frame intervals and CPU simulation/mesh submission time; not GPU completion time.",
	}
	var file := FileAccess.open(base + ".json", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(report, "\t", true, true))
	file.flush()
	error = file.get_error()
	file.close()
	if error == OK:
		last_report_path = base + ".json"
	return error
