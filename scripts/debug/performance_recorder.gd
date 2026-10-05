class_name PerformanceRecorder
extends RefCounted
## Bounded rolling CPU/frame timings. Summary/export allocate only on demand.
## CSV timestamps are relative to reset, even after older samples roll out.

const MAX_SAMPLES := 3600

var _frame_ms := PackedFloat64Array()
var _simulation_ms := PackedFloat64Array()
var _mesh_ms := PackedFloat64Array()
var _elapsed_s := PackedFloat64Array()
var _next := 0
var _count := 0
var _elapsed := 0.0


func _init() -> void:
	_frame_ms.resize(MAX_SAMPLES)
	_simulation_ms.resize(MAX_SAMPLES)
	_mesh_ms.resize(MAX_SAMPLES)
	_elapsed_s.resize(MAX_SAMPLES)


func reset() -> void:
	_next = 0
	_count = 0
	_elapsed = 0.0


func record(frame_seconds: float, simulation_ms: float, mesh_ms: float) -> void:
	if not is_finite(frame_seconds) or frame_seconds <= 0.0:
		return
	if not is_finite(simulation_ms) or simulation_ms < 0.0:
		return
	if not is_finite(mesh_ms) or mesh_ms < 0.0:
		return
	_elapsed += frame_seconds
	_frame_ms[_next] = frame_seconds * 1000.0
	_simulation_ms[_next] = simulation_ms
	_mesh_ms[_next] = mesh_ms
	_elapsed_s[_next] = _elapsed
	_next = (_next + 1) % MAX_SAMPLES
	_count = mini(_count + 1, MAX_SAMPLES)


## Nearest-rank p95; FPS uses total frames / time, not an average of FPS.
func summary() -> Dictionary:
	var frame_total := 0.0
	var simulation_total := 0.0
	var mesh_total := 0.0
	var sorted_frames := _frame_ms.slice(0, _count)
	for index in _count:
		frame_total += _frame_ms[index]
		simulation_total += _simulation_ms[index]
		mesh_total += _mesh_ms[index]
	sorted_frames.sort()
	var divisor := float(maxi(_count, 1))
	return {
		"sample_count": _count,
		"duration_s": frame_total / 1000.0,
		"frame_ms_mean": frame_total / divisor,
		"frame_ms_p95": sorted_frames[ceili(_count * 0.95) - 1] if _count else 0.0,
		"fps": _count * 1000.0 / frame_total if frame_total > 0.0 else 0.0,
		"simulation_ms_mean": simulation_total / divisor,
		"mesh_ms_mean": mesh_total / divisor,
	}


## Exports retained samples oldest first. Does not clear the recording.
func write_csv(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_csv_line(PackedStringArray(["frame_ms", "simulation_ms", "mesh_ms", "elapsed_s"]))
	var oldest := (_next - _count + MAX_SAMPLES) % MAX_SAMPLES
	for offset in _count:
		var index := (oldest + offset) % MAX_SAMPLES
		file.store_csv_line(PackedStringArray([
			"%.9f" % _frame_ms[index], "%.9f" % _simulation_ms[index],
			"%.9f" % _mesh_ms[index], "%.9f" % _elapsed_s[index],
		]))
	file.flush()
	var error := file.get_error()
	file.close()
	return error
