extends TestCase

const RopeScene := preload("res://scenes/rope/rope.tscn")


func test_mesh_matches_centerline() -> void:
	var renderer := add_to_tree(RopeRenderer.new()) as RopeRenderer
	var points := RopeLayout.straight(Vector3.ZERO, Vector3.RIGHT, 1.0, 8)
	renderer.update_mesh(points, 0.02)
	var mesh := renderer.mesh as ArrayMesh
	assert_eq(mesh.get_surface_count(), 1, "single surface")
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var rings := 8 * renderer.subdivisions + 1 + renderer.cap_rings * 2
	assert_eq(vertices.size(), rings * (renderer.radial_segments + 1), "vertex count")
	var aabb := mesh.get_aabb()
	assert_near(aabb.size.x, 1.0 + 0.04, "length plus caps", 1e-3)
	assert_near(aabb.size.y, 0.04, "diameter", 1e-3)


func test_body_normals_point_outward() -> void:
	var renderer := add_to_tree(RopeRenderer.new()) as RopeRenderer
	renderer.update_mesh(RopeLayout.straight(Vector3.ZERO, Vector3.RIGHT, 1.0, 4), 0.02)
	var arrays := (renderer.mesh as ArrayMesh).surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var start := renderer.cap_rings * (renderer.radial_segments + 1)
	for i in range(start, start + renderer.radial_segments):
		var radial := Vector3(0, vertices[i].y, vertices[i].z).normalized()
		assert_vec3_near(normals[i].normalized(), radial, "normal %d outward" % i, 1e-3)


func test_degenerate_input_clears_mesh() -> void:
	var renderer := add_to_tree(RopeRenderer.new()) as RopeRenderer
	renderer.update_mesh(PackedVector3Array([Vector3.ZERO]), 0.02)
	assert_eq((renderer.mesh as ArrayMesh).get_surface_count(), 0, "no surface")


func test_rope_reset_restores_rest_shape() -> void:
	var rope := add_to_tree(RopeScene.instantiate()) as Rope
	var rest := rope.get_simulation().get_positions().duplicate()
	for i in 60:
		rope.advance(1.0 / 60.0)
	assert_true(rope.get_simulation().get_positions() != rest, "rope moved")
	rope.reset()
	assert_eq(rope.get_simulation().get_positions(), rest, "rest shape restored")


func test_advance_uses_fixed_steps() -> void:
	var rope := add_to_tree(RopeScene.instantiate()) as Rope
	var dt := rope.config.get_time_step()
	assert_eq(rope.advance(dt * 0.5), 0, "half step accumulates")
	assert_eq(rope.advance(dt * 0.5), 1, "then one step")
	assert_eq(rope.advance(10.0), rope.config.max_steps_per_tick, "hitch is capped")


func test_held_rope_skips_mesh_work_and_still_accepts_radius_changes() -> void:
	var rope := add_to_tree(RopeScene.instantiate()) as Rope
	rope.config = rope.config.duplicate() as RopeConfig
	rope.begin_drag(24)
	rope.end_drag()
	rope._process(1.0 / 60.0)
	assert_near(rope.get_last_mesh_ms(), 0.0, "held frames do no mesh work")
	var renderer := rope.get_node("RopeRenderer") as RopeRenderer
	var previous := renderer.mesh.get_aabb()
	rope.config.radius *= 2.0
	rope._process(1.0 / 60.0)
	assert_true(renderer.mesh.get_aabb().size.z > previous.size.z, "radius remains adjustable when held")


func test_radial_segments_can_change_after_circle_cache_is_built() -> void:
	var renderer := add_to_tree(RopeRenderer.new()) as RopeRenderer
	var points := RopeLayout.straight(Vector3.ZERO, Vector3.RIGHT, 1.0, 4)
	renderer.update_mesh(points, 0.02)
	renderer.radial_segments = 16
	renderer.update_mesh(points, 0.02)
	var arrays := renderer.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_eq(vertices.size(), (4 * renderer.subdivisions + 1 + renderer.cap_rings * 2) * 17, "cache follows radial count")
	assert_near(renderer.mesh.get_aabb().size.y, 0.04, "updated ring has same diameter", 1e-3)


func test_tightened_strands_keep_rendered_clearance() -> void:
	var points := SelfCollisionFixture.trefoil()
	var config := RopeConfig.new()
	config.segment_count = points.size() - 1
	config.length = RopeLayout.polyline_length(points)
	config.gravity = Vector3.ZERO
	config.damping = 6.0
	var simulation := RopeSimulation.new(config, points)
	simulation.pin(0, points[0])
	simulation.begin_drag(config.segment_count)
	for step in 600:
		if step < 360:
			simulation.update_drag_target(points[-1] + Vector3(1.5, -2.0, 0.75) * float(step + 1) / 360.0)
		elif step == 360:
			simulation.end_drag()
		simulation.step(config.get_time_step())
		assert_true(simulation.get_max_segment_stretch() < 0.08, "tightening keeps bounded length")
	var renderer := add_to_tree(RopeRenderer.new()) as RopeRenderer
	renderer.update_mesh(simulation.get_positions(), config.radius)
	var gap := SelfCollisionFixture.rendered_clearance(renderer._centers, config, renderer.subdivisions)
	assert_true(gap >= config.radius * 1.9, "smoothing preserves contact clearance; gap=%f" % gap)
