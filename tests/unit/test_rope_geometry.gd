extends TestCase


func test_perpendicular_interiors_at_multiple_scales() -> void:
	for scale in [0.0001, 0.01, 1.0, 100.0]:
		var pair := RopeGeometry.closest_segment_points(Vector3(-scale, 0, 0), Vector3(scale, 0, 0), Vector3(0, -scale, scale * 0.2), Vector3(0, scale, scale * 0.2))
		assert_vec3_near(pair[0], Vector3.ZERO, "first closest point is interior", scale * 1e-5)
		assert_vec3_near(pair[1], Vector3(0, 0, scale * 0.2), "second closest point is interior", scale * 1e-5)


func test_endpoints_parallel_and_degenerate_segments() -> void:
	var pair := RopeGeometry.closest_segment_points(Vector3.ZERO, Vector3.RIGHT, Vector3(2, 1, 0), Vector3(2, -1, 0))
	assert_vec3_near(pair[0], Vector3.RIGHT, "finite segment clamps endpoint")
	assert_vec3_near(pair[1], Vector3(2, 0, 0), "other segment interior")
	pair = RopeGeometry.closest_segment_points(Vector3.ZERO, Vector3.RIGHT, Vector3(0.5, 1, 0), Vector3(1.5, 1, 0))
	assert_near(pair[0].distance_to(pair[1]), 1.0, "parallel separation")
	pair = RopeGeometry.closest_segment_points(Vector3.ZERO, Vector3.ZERO, Vector3(-1, 1, 0), Vector3(1, 1, 0))
	assert_vec3_near(pair[1], Vector3.UP, "point to segment")
	pair = RopeGeometry.closest_segment_points(Vector3.ZERO, Vector3.ZERO, Vector3.UP, Vector3.UP)
	assert_near(pair[0].distance_to(pair[1]), 1.0, "point to point")
