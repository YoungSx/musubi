extends TestCase


func test_segment_interiors_separate_with_endpoints_far_apart() -> void:
	var points := _crossing(0.01)
	var previous := points.duplicate()
	var mass := PackedFloat32Array([1, 1, 0, 1, 1])
	var solver := RopeSelfCollision.new()
	solver.solve(points, previous, mass, previous.duplicate(), 0.02, 0.5, 0.0)
	assert_true(_gap(points) >= 0.0399, "interior capsules separate even though endpoints never touch")
	assert_true(solver.contacts > 0, "contact recorded")
	assert_true(points[2] == Vector3(2, 2, 2), "unrelated fixed point preserved")


func test_centimeter_crossing_resolves_true_interior_contact() -> void:
	var points := _crossing(0.1)
	for i in points.size():
		points[i] *= 0.01
	var previous := points.duplicate()
	RopeSelfCollision.new().solve(points, previous, PackedFloat32Array([0, 0, 0, 1, 1]), points.duplicate(), 0.002, 0.01, 0.0)
	# Independent analytic oracle for perpendicular strands at their midpoints.
	assert_true((points[3].z + points[4].z) * 0.5 >= 0.004, "centimeter-scale interior contact separates by diameter")


func test_pins_and_symmetric_response() -> void:
	var points := _crossing(0.01)
	var original := points.duplicate()
	var history := points.duplicate()
	RopeSelfCollision.new().solve(points, history, PackedFloat32Array([0, 0, 0, 1, 1]), original, 0.02, 0.5, 0.0)
	assert_eq(points[0], original[0], "first pin stays exact")
	assert_eq(points[1], original[1], "second pin stays exact")
	assert_true(_gap(points) >= 0.0399, "movable strand receives full correction")
	points = _crossing(0.01)
	history = points.duplicate()
	RopeSelfCollision.new().solve(points, history, PackedFloat32Array([1, 1, 0, 1, 1]), original, 0.02, 0.5, 0.0)
	var before_sum := original[0] + original[1] + original[3] + original[4]
	assert_true((points[0] + points[1] + points[3] + points[4]).is_equal_approx(before_sum), "equal mass contact preserves center of mass")
	assert_eq(points, history, "resting correction injects no velocity")


func test_fast_crossing_preserves_incident_side() -> void:
	var start := _crossing(0.2)
	var points := _crossing(-0.2)
	var previous := start.duplicate()
	RopeSelfCollision.new().solve(points, previous, PackedFloat32Array([0, 0, 0, 1, 1]), start, 0.02, 0.5, 0.0)
	assert_true(points[3].z >= 0.0399 and points[4].z >= 0.0399, "sweep catches separated end states on opposite sides")
	assert_true((points[3] - previous[3]).z >= -0.00001, "inward relative velocity removed")


func test_degenerate_contacts_are_finite_and_repeatable() -> void:
	for points in [_crossing(0.0), PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3(2, 2, 2), Vector3.ZERO, Vector3.ZERO])]:
		var a: PackedVector3Array = points.duplicate()
		var b: PackedVector3Array = points.duplicate()
		var masses := PackedFloat32Array([1, 1, 0, 1, 1])
		RopeSelfCollision.new().solve(a, points.duplicate(), masses, points, 0.02, 0.5, 0.18)
		RopeSelfCollision.new().solve(b, points.duplicate(), masses, points, 0.02, 0.5, 0.18)
		assert_eq(a, b, "zero-distance fallback is deterministic")
		for p in a:
			assert_true(p.is_finite(), "degenerate contact stays finite")


func test_adjacent_material_and_free_flight_unchanged() -> void:
	var points := PackedVector3Array()
	var masses := PackedFloat32Array()
	for i in 16:
		points.append(Vector3(i * 0.01, 0, 0))
		masses.append(1.0)
	var original := points.duplicate()
	RopeSelfCollision.new().solve(points, points.duplicate(), masses, original, 0.02, 0.01, 0.18)
	assert_eq(points, original, "fine straight rope does not collide with local material")
	points = _crossing(0.5)
	original = points.duplicate()
	RopeSelfCollision.new().solve(points, points.duplicate(), PackedFloat32Array([1, 1, 0, 1, 1]), original, 0.02, 0.5, 0.18)
	assert_eq(points, original, "separated segments have no artificial forces")


func test_self_friction_reduces_relative_slide() -> void:
	var speeds: Array[float] = []
	for friction in [0.0, 1.0]:
		var points := _crossing(0.03)
		var previous := points.duplicate()
		previous[3].x -= 0.01
		previous[4].x -= 0.01
		RopeSelfCollision.new().solve(points, previous, PackedFloat32Array([0, 0, 0, 1, 1]), points.duplicate(), 0.02, 0.5, friction)
		speeds.append(absf((points[3] - previous[3]).x))
	assert_true(speeds[1] < speeds[0] * 0.1, "contact friction reduces sliding relative to fixed strand")


func test_state_version_and_self_collision_options() -> void:
	var config := RopeConfig.new()
	var sim := RopeSimulation.new(config, RopeLayout.hanging(Vector3.ZERO, Vector3.RIGHT, config.length, config.segment_count))
	var state := sim.capture_state()
	assert_eq(state.version, 3, "new format records contact and continuous grip settings")
	assert_true(RopeSimulation.restore_state(state).capture_state().config.self_collision_enabled, "new files enable self collision")
	var old := state.duplicate(true)
	old.version = 1
	old.config.erase("self_collision_enabled")
	old.config.erase("self_friction")
	assert_true(not RopeSimulation.restore_state(old).capture_state().config.self_collision_enabled, "legacy files preserve old simulation behavior")
	for value in [null, 1, "true"]:
		var invalid := state.duplicate(true)
		invalid.config.self_collision_enabled = value
		assert_true(RopeSimulation.restore_state(invalid) == null, "invalid flag rejected")


func test_contacting_loop_snapshot_continues_deterministically() -> void:
	var points := SelfCollisionFixture.points()
	var config := RopeConfig.new()
	config.gravity = Vector3.ZERO
	config.radius = 0.02
	config.length = RopeLayout.polyline_length(points)
	var sim := RopeSimulation.new(config, points)
	sim.pin(0, points[0])
	sim.pin(config.segment_count, points[-1])
	for step in 30:
		sim.step(config.get_time_step())
	var restored := RopeSimulation.restore_state(JSON.parse_string(JSON.stringify(sim.capture_state(), "", true, true)))
	assert_true(restored != null, "contacting loop restores from JSON")
	if restored == null:
		return
	for step in 90:
		sim.step(config.get_time_step())
		restored.step(config.get_time_step())
	assert_eq(restored.get_positions(), sim.get_positions(), "contact response has no hidden unsaved cache")
	assert_true(SelfCollisionFixture.clearance(sim.get_positions(), config) >= config.radius * 1.95, "loop maintains full strand separation")
	assert_true(sim.get_max_segment_stretch() < 0.02, "loop length stays bounded")


func test_legacy_full_scene_loads_and_reset_enables_new_contacts() -> void:
	var app := add_to_tree(load("res://scenes/main/main.tscn").instantiate()) as AppController
	app.process_mode = Node.PROCESS_MODE_DISABLED
	var state := MusubiSceneState.capture(app)
	state.rope.simulation.version = 1
	state.rope.simulation.config.erase("self_collision_enabled")
	state.rope.simulation.config.erase("self_friction")
	assert_true(MusubiSceneState.apply(app, state), "existing creation remains loadable")
	assert_true(not app.rope.get_simulation().is_self_collision_enabled(), "legacy behavior preserved")
	app.reset()
	assert_true(app.rope.get_simulation().is_self_collision_enabled(), "Reset starts new default simulation")


func _crossing(z: float) -> PackedVector3Array:
	return PackedVector3Array([Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(2, 2, 2), Vector3(0, -1, z), Vector3(0, 1, z)])


func _gap(points: PackedVector3Array) -> float:
	var pair := Geometry3D.get_closest_points_between_segments(points[0], points[1], points[3], points[4])
	return pair[0].distance_to(pair[1])
