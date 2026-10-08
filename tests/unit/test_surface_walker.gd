extends TestCase
## Adhesion locomotion. The walker's only authority is RopeCollision, so these
## cases are pure geometry: no nodes, no input, no rendering.


func test_places_body_on_floor_at_its_radius() -> void:
	var walker := _walker(_collision(_sphere(), true))
	walker.place(Vector3(0.4, 0.02, 0.4))
	assert_true(walker.contact == SurfaceWalker.Contact.FLOOR, "a point near the floor lands on it")
	assert_near(walker.position.y, 0.03, "body center rests one radius above the floor")
	assert_vec3_near(walker.up, Vector3.UP, "floor normal is world up")
	walker.place(Vector3(0.4, 1.0, 0.4))
	assert_true(walker.contact == SurfaceWalker.Contact.AIR, "a point out of reach stays airborne and falls")


func test_adheres_to_body_surface_with_its_normal_as_up() -> void:
	var walker := _walker(_collision(_sphere(), false))
	walker.place(Vector3(0.35, 0.0, 0.0))
	assert_true(walker.contact == SurfaceWalker.Contact.BODY, "point near the sphere attaches to it")
	assert_near(walker.position.x, 0.33, "center sits one body radius off the surface", 0.001)
	assert_true(walker.up.dot(Vector3.RIGHT) > 0.99, "up follows the outward surface normal")


func test_climbs_over_a_convex_edge_instead_of_launching_off() -> void:
	var walker := _walker(_collision(_sphere(), false))
	walker.place(Vector3(0.35, 0.0, 0.0))
	var up_before := walker.up
	for i in 120:
		walker.step(1.0 / 60.0, Vector3.UP * 1.0)
	assert_true(walker.contact == SurfaceWalker.Contact.BODY, "still attached after walking up the sphere")
	assert_true(walker.position.y > 0.2, "body travelled around the silhouette")
	assert_true(walker.up.dot(up_before) < 0.9, "surface frame turned with the surface")
	assert_near(_collision(_sphere(), false).get_body_clearance(walker.position), 0.03, "clearance held throughout", 0.002)


func test_unsupported_body_falls_until_a_surface_catches_it() -> void:
	var walker := _walker(_collision(_sphere(), true))
	walker.position = Vector3(2.0, 1.5, 0.0)
	walker.contact = SurfaceWalker.Contact.AIR
	walker.step(1.0 / 60.0, Vector3.ZERO)
	assert_true(walker.velocity.y < 0.0, "gravity accumulates while airborne")
	for i in 180:
		walker.step(1.0 / 60.0, Vector3.ZERO)
	assert_true(walker.contact == SurfaceWalker.Contact.FLOOR, "falls onto the floor")
	assert_near(walker.position.y, 0.03, "landing keeps the adhesion radius")
	assert_vec3_near(walker.velocity, Vector3.ZERO, "landing clears fall velocity")


func test_walking_off_a_ledge_keeps_forward_momentum() -> void:
	var collision := _collision(_sphere(), false)
	var walker := _walker(collision)
	walker.place(Vector3(0.0, 0.35, 0.0))
	assert_true(walker.contact == SurfaceWalker.Contact.BODY, "starts on top of the sphere")
	for i in 240:
		walker.step(1.0 / 60.0, Vector3.RIGHT)
		if walker.contact == SurfaceWalker.Contact.AIR:
			break
	if walker.contact == SurfaceWalker.Contact.AIR:
		assert_true(walker.velocity.length() > 0.0, "departure carries the walking speed")
	else:
		assert_true(walker.position.x > 0.2, "or it wrapped around the surface instead")


func test_floor_and_body_crease_has_a_blended_normal() -> void:
	# A capsule lying on the floor makes a wedge. Taking either surface alone
	# leaves the two corrections fighting and the body stops dead in it.
	var part := MannequinPart.new()
	part.primitive = MannequinPart.Primitive.CAPSULE
	part.radius = 0.042
	part.height = 0.25
	part.position = Vector3(0.0, 0.042, 0.0)
	part.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	var walker := _walker(_collision(part, true))
	walker.place(Vector3(0.0, 0.03, 0.2))
	var start := walker.position.z
	for i in 120:
		walker.step(1.0 / 60.0, Vector3.FORWARD)
	assert_true(walker.position.z < start - 0.05, "body crosses the crease instead of stalling")
	assert_true(walker.up.y > 0.1, "blended normal keeps a usable tangent plane")


func test_camera_frame_walks_away_from_the_camera_on_flat_ground() -> void:
	var intent := SurfaceWalker.camera_intent(Vector2(0.0, -1.0), 0.0, Vector3.UP)
	assert_true(intent.z < -0.9, "stick up walks away from a camera looking down -Z")
	var right := SurfaceWalker.camera_intent(Vector2(1.0, 0.0), 0.0, Vector3.UP)
	assert_true(right.x > 0.9, "stick right walks screen-right")
	var turned := SurfaceWalker.camera_intent(Vector2(0.0, -1.0), PI * 0.5, Vector3.UP)
	assert_true(turned.x < -0.9, "the frame follows the camera yaw")
	assert_vec3_near(SurfaceWalker.camera_intent(Vector2.ZERO, 0.0, Vector3.UP), Vector3.ZERO, "center stick is no intent")


func test_camera_frame_climbs_a_vertical_face_the_camera_faces() -> void:
	# A surface facing the camera has no tangential component of the view
	# direction, so a camera-only frame would stall the climb here.
	var intent := SurfaceWalker.camera_intent(Vector2(0.0, -1.0), 0.0, Vector3.BACK)
	assert_true(intent.y > 0.9, "stick up climbs straight up the face")
	assert_true(SurfaceWalker.camera_intent(Vector2(0.0, 1.0), 0.0, Vector3.BACK).y < -0.9, "stick down descends it")
	var side := SurfaceWalker.camera_intent(Vector2(0.0, -1.0), 0.0, Vector3.RIGHT)
	assert_true(side.y > 0.9, "a face turned away from the camera still climbs upward")


func test_camera_frame_preserves_stick_magnitude() -> void:
	for up in [Vector3.UP, Vector3.BACK, Vector3(0.6, 0.8, 0.0).normalized()]:
		var half := SurfaceWalker.camera_intent(Vector2(0.0, -0.5), 0.3, up)
		assert_near(half.length(), 0.5, "half deflection is half intent")
		assert_near(half.dot(up), 0.0, "intent stays in the tangent plane", 0.001)
		assert_near(SurfaceWalker.camera_intent(Vector2(0.0, -4.0), 0.3, up).length(), 1.0, "overlong stick clamps to full intent")


func test_basis_lies_flat_on_the_surface() -> void:
	var walker := _walker(_collision(_sphere(), false))
	walker.place(Vector3(0.35, 0.0, 0.0))
	var basis := walker.get_basis()
	assert_vec3_near(basis.y, walker.up, "local up is the surface normal")
	assert_near(basis.x.dot(basis.y), 0.0, "frame is orthogonal")
	assert_near(basis.determinant(), 1.0, "frame is right-handed and unscaled", 0.001)


func _walker(collision: RopeCollision) -> SurfaceWalker:
	var walker := SurfaceWalker.new()
	walker.configure(_config(), collision)
	return walker


func _config() -> OctopusConfig:
	var config := OctopusConfig.new()
	config.body_radius = 0.03
	config.cling_range = 0.045
	config.move_speed = 0.55
	return config


func _sphere() -> MannequinPart:
	var part := MannequinPart.new()
	part.primitive = MannequinPart.Primitive.SPHERE
	part.radius = 0.3
	part.position = Vector3.ZERO
	return part


func _collision(part: MannequinPart, floor_enabled: bool) -> RopeCollision:
	var config := MannequinConfig.new()
	config.parts = [part]
	var collision := RopeCollision.new()
	collision.floor_enabled = floor_enabled
	collision.configure(config)
	return collision
