extends TestCase
## Follow policy. It observes the body and writes only through the rig's
## assisted-view seam, so these cases check framing intent and rate limits.


func test_follow_frames_the_body_above_its_surface() -> void:
	var rig := _rig()
	var camera := _camera(rig, null)
	camera.update(0.1, Vector3(0.4, 0.5, -0.2), Vector3.UP, Vector3.ZERO)
	assert_vec3_near(rig.get_target_focus(), Vector3(0.4, 0.68, -0.2), "focus sits above the body")
	camera.update(0.1, Vector3(0.4, 0.5, -0.2), Vector3.RIGHT, Vector3.ZERO)
	assert_vec3_near(rig.get_target_focus(), Vector3(0.58, 0.5, -0.2), "the offset follows the surface normal")


func test_sustained_movement_eases_the_view_behind_the_body() -> void:
	var rig := _rig()
	var camera := _camera(rig, null)
	var start := camera.get_yaw()
	for i in 120:
		camera.update(1.0 / 60.0, Vector3.ZERO, Vector3.UP, Vector3.FORWARD)
	assert_near(absf(wrapf(camera.get_yaw() - 0.0, -PI, PI)), 0.0, "walking away from the camera settles at zero yaw", 0.02)
	var turned := _camera(_rig(), null)
	for i in 120:
		turned.update(1.0 / 60.0, Vector3.ZERO, Vector3.UP, Vector3.RIGHT)
	assert_near(absf(wrapf(turned.get_yaw() + PI * 0.5, -PI, PI)), 0.0, "walking right puts the camera to the left", 0.02)
	assert_true(absf(start) > 0.0, "the rig started at its configured yaw")


func test_turn_rate_is_limited() -> void:
	var rig := _rig()
	var camera := _camera(rig, null)
	var before := camera.get_yaw()
	camera.update(1.0 / 60.0, Vector3.ZERO, Vector3.UP, Vector3.FORWARD)
	assert_true(absf(camera.get_yaw() - before) <= deg_to_rad(90.0) / 60.0 + 0.0001, "one frame cannot snap the view around")


func test_small_deflections_hold_the_view() -> void:
	var rig := _rig()
	var camera := _camera(rig, null)
	var before := camera.get_yaw()
	for i in 60:
		camera.update(1.0 / 60.0, Vector3.ZERO, Vector3.UP, Vector3.RIGHT * 0.2)
	assert_near(camera.get_yaw(), before, "fine positioning does not spin the view")


func test_view_pulls_in_when_its_origin_is_inside_geometry() -> void:
	var part := MannequinPart.new()
	part.primitive = MannequinPart.Primitive.SPHERE
	part.radius = 1.2
	part.position = Vector3(0.0, 0.5, 1.2)
	var config := MannequinConfig.new()
	config.parts = [part]
	var collision := RopeCollision.new()
	collision.floor_enabled = false
	collision.configure(config)
	var rig := _rig()
	var camera := _camera(rig, collision)
	camera.update(0.1, Vector3(0.0, 0.5, 0.0), Vector3.UP, Vector3.ZERO)
	assert_true(rig.get_target_distance() < 1.3, "an occluded view dollies in")
	assert_true(rig.get_target_distance() >= rig.config.min_distance, "and respects the rig's own limit")


func test_a_blocked_line_of_sight_does_not_dolly_the_view_in() -> void:
	# A slab between the body and the camera, with the camera's own origin in
	# open air. Pulling in here cannot clear the line, because a clinging body is
	# always within its own radius of the occluder; it only crops the scene.
	var part := MannequinPart.new()
	part.primitive = MannequinPart.Primitive.BOX
	part.box_size = Vector3(2.0, 2.0, 0.1)
	part.position = Vector3(0.0, 0.5, 0.6)
	var config := MannequinConfig.new()
	config.parts = [part]
	var collision := RopeCollision.new()
	collision.floor_enabled = false
	collision.configure(config)
	var rig := _rig()
	var camera := _camera(rig, collision)
	var body := Vector3(0.0, 0.5, 0.0)
	camera.update(0.1, body, Vector3.UP, Vector3.ZERO)
	assert_near(rig.get_target_distance(), rig.config.distance, "the framing distance is held")


func _rig() -> CameraRig:
	var rig := load("res://scenes/camera/camera_rig.tscn").instantiate() as CameraRig
	rig.config = load("res://data/camera/octopus_camera.tres")
	add_to_tree(rig)
	return rig


func _camera(rig: CameraRig, collision: RopeCollision) -> OctopusCamera:
	var camera := OctopusCamera.new()
	camera.configure(load("res://data/octopus/default_octopus.tres"), rig, collision)
	return camera
