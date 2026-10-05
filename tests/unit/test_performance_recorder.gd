extends TestCase


func test_summary_uses_elapsed_time_and_nearest_rank_p95() -> void:
	var recorder := PerformanceRecorder.new()
	for index in 20:
		recorder.record((index + 1) / 1000.0, 2.0, 0.5)
	var metrics := recorder.summary()
	assert_eq(metrics.sample_count, 20, "all samples retained")
	assert_near(metrics.duration_s, 0.21, "duration includes all frame time")
	assert_near(metrics.frame_ms_mean, 10.5, "mean frame duration")
	assert_near(metrics.frame_ms_p95, 19.0, "nearest rank p95")
	assert_near(metrics.fps, 20.0 / 0.21, "FPS derives from elapsed duration")
	assert_near(metrics.simulation_ms_mean, 2.0, "mean simulation duration")
	assert_near(metrics.mesh_ms_mean, 0.5, "mean mesh duration")


func test_invalid_measurements_and_reset() -> void:
	var recorder := PerformanceRecorder.new()
	for dt in [0.0, -1.0, NAN, INF]:
		recorder.record(dt, 1.0, 1.0)
	for value in [-1.0, NAN, INF]:
		recorder.record(0.016, value, 1.0)
		recorder.record(0.016, 1.0, value)
	assert_eq(recorder.summary().sample_count, 0, "invalid samples discarded")
	recorder.record(0.016, 0.0, 0.0)
	assert_eq(recorder.summary().sample_count, 1, "zero work is valid")
	recorder.reset()
	var metrics := recorder.summary()
	assert_eq(metrics.sample_count, 0, "reset clears samples")
	assert_near(metrics.duration_s, 0.0, "reset clears elapsed duration")
	assert_near(metrics.fps, 0.0, "empty summary has finite FPS")
	assert_near(metrics.frame_ms_p95, 0.0, "empty summary has zero p95")


func test_bounded_export_preserves_chronology_and_reset_timestamps() -> void:
	var recorder := PerformanceRecorder.new()
	var capacity := PerformanceRecorder.MAX_SAMPLES
	# Discard these large initial frames from the rolling window.
	recorder.record(1.0, 50.0, 50.0)
	recorder.record(1.0, 50.0, 50.0)
	for index in capacity:
		recorder.record(0.01, float(index), 0.25)
	var metrics := recorder.summary()
	assert_eq(metrics.sample_count, capacity, "recording remains bounded")
	assert_near(metrics.duration_s, capacity * 0.01, "duration only covers retained window")
	assert_near(metrics.frame_ms_mean, 10.0, "old frames leave summary")
	assert_near(metrics.simulation_ms_mean, (capacity - 1) / 2.0, "mean uses retained samples")
	var path := "user://performance-recorder-test-%s.csv" % Time.get_ticks_usec()
	assert_eq(recorder.write_csv(path), OK, "CSV export succeeds")
	var file := FileAccess.open(path, FileAccess.READ)
	assert_true(file != null, "export can be read")
	if file == null:
		return
	assert_eq(file.get_csv_line(), PackedStringArray(["frame_ms", "simulation_ms", "mesh_ms", "elapsed_s"]), "CSV header")
	for index in capacity:
		var row := file.get_csv_line()
		assert_eq(row.size(), 4, "four columns per sample")
		if row.size() != 4:
			break
		assert_near(float(row[0]), 10.0, "frame duration round trip")
		assert_near(float(row[1]), float(index), "oldest-to-newest sample order")
		assert_near(float(row[2]), 0.25, "mesh duration round trip")
		assert_near(float(row[3]), 2.0 + (index + 1) * 0.01, "timestamps relative to reset")
	assert_eq(file.get_position(), file.get_length(), "exactly one row per retained sample")
	file.close()
	recorder.reset()
	recorder.record(0.02, 1.0, 0.5)
	assert_eq(recorder.write_csv(path), OK, "reset recording exports")
	file = FileAccess.open(path, FileAccess.READ)
	file.get_csv_line()
	assert_near(float(file.get_csv_line()[3]), 0.02, "reset restarts timestamps")
	file.close()
	assert_eq(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)), OK, "test export cleaned")


func test_csv_export_reports_open_failure() -> void:
	var recorder := PerformanceRecorder.new()
	assert_true(recorder.write_csv("user://missing-%s/metrics.csv" % Time.get_ticks_usec()) != OK, "missing parent returns error")
