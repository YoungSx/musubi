extends TestCase


func test_drag_is_an_intent_and_leaves_particle_movable() -> void:
	var sim := _simulation()
	var before := sim.get_positions().duplicate()
	assert_true(not sim.begin_drag(0), "fixed attachment cannot be grabbed")
	assert_true(sim.begin_drag(24), "middle can be grabbed")
	sim.update_drag_target(before[24] + Vector3(0, 0.12, 0.1))
	assert_eq(sim.get_positions(), before, "input never teleports particles")
	assert_true(not sim.is_pinned(24), "contacts can still move the grabbed point")
	for step in 120:
		sim.step(1.0 / 120.0)
	assert_true(sim.get_point(24).distance_to(before[24]) > 0.02, "rope responds")
	sim.end_drag()
	assert_eq(sim.get_drag_index(), -1, "constraint removed")
	sim.stop_motion()
	assert_near(sim.get_max_speed(), 0.0, "hold clears momentum")


func test_extreme_drag_remains_bounded_and_outside_mannequin() -> void:
	var sim := _simulation()
	var collision := _collision()
	sim.set_collision(collision)
	for step in 120:
		sim.step(1.0 / 120.0)
	sim.begin_drag(24)
	for target in [Vector3(100, 100, -100), Vector3(0, 1.1, -0.5), Vector3(0, -100, 0)]:
		sim.update_drag_target(target)
		for step in 120:
			sim.step(1.0 / 120.0)
		assert_true(sim.get_max_segment_stretch() < 0.08, "drag length bounded: %f" % sim.get_max_segment_stretch())
		for i in sim.get_point_count():
			assert_true(sim.get_point(i).is_finite(), "finite positions")
			assert_true(collision.get_clearance(sim.get_point(i)) >= 0.011, "grab remains outside obstacles")


func test_release_holds_shape_and_next_grab_resumes() -> void:
	var rope := add_to_tree(load("res://scenes/rope/rope.tscn").instantiate()) as Rope
	rope.begin_drag(24)
	rope.update_drag_target(rope.get_simulation().get_point(24) + Vector3(0, 0.12, 0.1))
	for step in 60:
		rope.advance(1.0 / 120.0)
	rope.end_drag()
	var held := rope.get_simulation().get_positions().duplicate()
	assert_true(rope.is_held(), "release holds shape")
	assert_eq(rope.advance(1.0), 0, "hold has no simulation work")
	assert_eq(rope.get_simulation().get_positions(), held, "shape stays exact")
	assert_true(rope.begin_drag(24), "can grab again")
	assert_true(not rope.is_held(), "grab resumes")
	rope.reset()
	assert_eq(rope.get_simulation().get_drag_index(), -1, "reset clears constraint")
	assert_true(not rope.is_held(), "reset resumes initial simulation")


func test_multiple_soft_grips_solve_together_and_round_trip() -> void:
	var sim := _simulation()
	assert_true(sim.begin_grip(0.25, 4), "first fractional grip")
	assert_true(sim.begin_grip(0.75, 9), "second fractional grip")
	var a := sim.get_grip_position(4)
	var b := sim.get_grip_position(9)
	sim.update_drag_target(a + Vector3(0, 0.08, 0.12), 4)
	sim.update_drag_target(b + Vector3(0, 0.08, -0.12), 9)
	assert_true(not sim.begin_grip(0.5, 4), "duplicate pointer cannot steal its own grip")
	for step in 120: sim.step(1.0 / 120.0)
	assert_true(sim.get_grip_position(4).z > a.z + 0.03, "first grip moves toward its target")
	assert_true(sim.get_grip_position(9).z < b.z - 0.03, "second grip moves toward its different target")
	assert_true(sim.get_max_segment_stretch() < 0.08, "multiple hands retain length constraints")
	var state := sim.capture_state()
	var restored := RopeSimulation.restore_state(JSON.parse_string(JSON.stringify(state, "", true, true)))
	assert_true(restored != null, "multiple grips deserialize")
	if restored == null: return
	assert_eq(restored.get_grip_ids(), [4, 9], "pointer identities retained")
	for step in 15:
		sim.step(1.0 / 120.0)
		restored.step(1.0 / 120.0)
	for index in sim.get_point_count():
		assert_vec3_near(sim.get_point(index), restored.get_point(index), "round-trip continuation is deterministic")
	sim.release_grip(4)
	assert_eq(sim.get_grip_ids(), [9], "release removes only one constraint")
	var target := sim.get_drag_target(9)
	sim.step(1.0 / 120.0)
	assert_vec3_near(sim.get_drag_target(9), target, "release leaves other target unchanged")
	var invalid := state.duplicate(true)
	invalid.touch_grips[1].id = 4
	assert_true(RopeSimulation.restore_state(invalid) == null, "duplicate serialized pointer IDs rejected")
	invalid = state.duplicate(true)
	invalid.touch_grips[1].target = [0, "bad", 0]
	assert_true(RopeSimulation.restore_state(invalid) == null, "malformed touch target rejected")


func test_touch_transport_ownership_roundtrip_and_release() -> void:
	var sim := _simulation()
	sim.begin_grip(0.5, 3)
	assert_true(sim.set_transport_targets(sim.get_positions(), 3), "single touch retains transport assistance")
	var restored := RopeSimulation.restore_state(sim.capture_state())
	assert_true(restored != null and restored.has_transport_targets(), "touch transport owner round-trips")
	if restored == null: return
	restored.end_drag(3)
	assert_true(not restored.has_transport_targets(), "ending owner clears distributed targets")
	var invalid := sim.capture_state()
	invalid.transport_grip_id = 8
	assert_true(RopeSimulation.restore_state(invalid) == null, "missing transport owner rejected")


func _simulation() -> RopeSimulation:
	var config := load("res://data/rope/default_rope.tres") as RopeConfig
	var a := Vector3(0.55, 1.45, 0.12)
	var b := Vector3(-0.55, 1.45, 0.12)
	var sim := RopeSimulation.new(config, RopeLayout.hanging(a, b, config.length, config.segment_count))
	sim.pin(0, a)
	sim.pin(config.segment_count, b)
	return sim


func _collision() -> RopeCollision:
	var collision := RopeCollision.new()
	collision.configure(load("res://data/mannequin/default_mannequin.tres"))
	return collision
