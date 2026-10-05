extends TestCase

const DT := 1.0 / 120.0


func test_layout_has_expected_length() -> void:
	var config := _config()
	var points := RopeLayout.hanging(Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0), config.length, config.segment_count)
	assert_eq(points.size(), config.segment_count + 1, "point count")
	assert_near(RopeLayout.polyline_length(points), config.length, "hanging length", 0.01)
	assert_true(points[config.segment_count / 2].y < 1.0, "rope sags below anchors")


func test_layout_straight_when_anchors_too_far() -> void:
	var points := RopeLayout.hanging(Vector3.ZERO, Vector3(5, 0, 0), 1.0, 10)
	assert_vec3_near(points[10], Vector3(1, 0, 0), "laid straight at full length")


func test_gravity_pulls_free_rope_down() -> void:
	var sim := _hanging_sim(false)
	var before := sim.get_point(sim.get_point_count() / 2).y
	for i in 10:
		sim.step(DT)
	assert_true(sim.get_point(sim.get_point_count() / 2).y < before, "middle falls")


func test_pins_stay_fixed() -> void:
	var sim := _hanging_sim(true)
	var start := sim.get_point(0)
	var end := sim.get_point(sim.get_point_count() - 1)
	for i in 240:
		sim.step(DT)
	assert_vec3_near(sim.get_point(0), start, "start pin fixed")
	assert_vec3_near(sim.get_point(sim.get_point_count() - 1), end, "end pin fixed")


func test_length_is_conserved() -> void:
	var sim := _hanging_sim(true)
	for i in 600:
		sim.step(DT)
	assert_near(sim.get_length(), _config().length, "total length", 0.01)
	assert_true(sim.get_max_segment_stretch() < 0.02, "segments within 2%% of rest (got %f)" % sim.get_max_segment_stretch())


func test_rope_settles() -> void:
	var sim := _hanging_sim(true)
	# Start from a disturbed state so there is energy to dissipate.
	sim.pin(sim.get_point_count() - 1, Vector3(-0.2, 1.3, 0.2))
	for i in 1800:
		sim.step(DT)
	assert_true(sim.get_max_speed() < 0.02, "rope at rest (max speed %f)" % sim.get_max_speed())


func test_deterministic() -> void:
	var a := _hanging_sim(true)
	var b := _hanging_sim(true)
	for i in 300:
		a.step(DT)
		b.step(DT)
	assert_eq(a.get_positions(), b.get_positions(), "identical runs match exactly")


func test_unpin_releases_point() -> void:
	var sim := _hanging_sim(true)
	var last := sim.get_point_count() - 1
	sim.unpin(last)
	assert_true(not sim.is_pinned(last), "unpinned")
	var before := sim.get_point(last).y
	for i in 30:
		sim.step(DT)
	assert_true(sim.get_point(last).y < before, "released end falls")


func _config() -> RopeConfig:
	return load("res://data/rope/default_rope.tres") as RopeConfig


func _hanging_sim(pinned: bool) -> RopeSimulation:
	var config := _config()
	var a := Vector3(0.5, 1.4, 0)
	var b := Vector3(-0.5, 1.4, 0)
	var sim := RopeSimulation.new(config, RopeLayout.hanging(a, b, config.length, config.segment_count))
	if pinned:
		sim.pin(0, a)
		sim.pin(sim.get_point_count() - 1, b)
	return sim
