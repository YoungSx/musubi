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


func test_smooth_angular_damping_decelerates_near_target() -> void:
	var rig := _rig()
	var camera := _camera(rig, null)
	var config := load("res://data/octopus/default_octopus.tres") as OctopusConfig
	# Start with a small angular difference (15 degrees) where damping is below the max speed clamp
	var initial_yaw := deg_to_rad(15.0)
	var delta := 1.0 / 60.0
	var step1 := absf(OctopusCamera._turn(initial_yaw, Vector3.FORWARD, config, delta) - initial_yaw)
	var step2 := absf(OctopusCamera._turn(initial_yaw * 0.5, Vector3.FORWARD, config, delta) - (initial_yaw * 0.5))
	assert_true(step2 < step1, "angular speed decreases smoothly as view approaches target heading")


func test_lateral_movement_delays_camera_spin_preventing_feedback_loop() -> void:
	var rig := _rig()
	var camera := _camera(rig, null)
	var initial_yaw := camera.get_yaw()
	# The camera initially faces -Z (yaw -25 deg). Moving along +Z is behind the camera (dot < 0).
	# A single frame of lateral/reverse intent must hold yaw to avoid spinning feedback.
	camera.update(1.0 / 60.0, Vector3.ZERO, Vector3.UP, Vector3.BACK)
	assert_near(camera.get_yaw(), initial_yaw, "instant lateral/reverse motion holds yaw to prevent spin loop")


func test_sustained_lateral_movement_eventually_follows_after_delay() -> void:
	var rig := _rig()
	var camera := _camera(rig, null)
	var initial_yaw := camera.get_yaw()
	# Walk right continuously for 60 frames (1.0s > follow_turn_delay + 0.3s)
	for i in 60:
		camera.update(1.0 / 60.0, Vector3.ZERO, Vector3.UP, Vector3.RIGHT)
	assert_true(absf(wrapf(camera.get_yaw() - initial_yaw, -PI, PI)) > 0.1, "sustained lateral motion eventually eases camera behind heading")


func test_zero_threshold_and_zero_intent_does_not_produce_nan_or_turn() -> void:
	var rig := _rig()
	var config := load("res://data/octopus/default_octopus.tres").duplicate() as OctopusConfig
	config.follow_turn_threshold = 0.0
	var camera := OctopusCamera.new()
	camera.configure(config, rig, null)
	var initial_yaw := camera.get_yaw()
	for i in 30:
		camera.update(1.0 / 60.0, Vector3.ZERO, Vector3.UP, Vector3.ZERO)
	assert_true(is_finite(camera.get_yaw()), "yaw remains finite")
	assert_near(camera.get_yaw(), initial_yaw, "stationary character does not turn or produce NaN")


func test_continuous_clearance_avoids_discrete_step_jumps() -> void:
	var rig := _rig()
	var focus := Vector3(0.0, 0.5, 0.0)
	var origin := rig.global_transform * CameraRig.compute_camera_transform(rig.get_target_yaw(), rig.get_target_pitch(), 1.3, focus).origin

	var sphere_radius := 0.2
	var part := MannequinPart.new()
	part.primitive = MannequinPart.Primitive.SPHERE
	part.radius = sphere_radius
	var camera_dir := (origin - focus).normalized()
	# Center sphere so origin is penetrated by 3cm
	part.position = origin + camera_dir * (sphere_radius - 0.03)

	var config := MannequinConfig.new()
	config.parts = [part]
	var collision := RopeCollision.new()
	collision.floor_enabled = false
	collision.configure(config)

	var camera := _camera(rig, collision)
	camera.update(0.1, focus, Vector3.UP, Vector3.ZERO)
	var new_dist := rig.get_target_distance()

	# Under old discrete stepping: 1.3 * 0.75 = 0.975m (a 0.325m jump).
	# Under continuous stepping: distance adjusts by only ~0.11m (0.08 - (-0.03)), so new_dist > 1.10m.
	assert_true(new_dist > 1.10, "continuous clearance avoids 25% discrete step jumping")
	assert_true(new_dist < 1.30, "and clears the required deficit")


func test_distance_springs_back_smoothly_after_obstacle_cleared() -> void:
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
	var body := Vector3(0.0, 0.5, 0.0)

	# 1. Obstacle pushes camera in
	camera.update(0.1, body, Vector3.UP, Vector3.ZERO)
	var pushed_distance := rig.get_target_distance()
	assert_true(pushed_distance < 1.3, "obstacle pushes camera in")

	# 2. Clear the obstacle
	config.parts = []
	collision.configure(config)

	# 3. Next small frame does not snap immediately to 1.3, but springs outward
	camera.update(1.0 / 60.0, body, Vector3.UP, Vector3.ZERO)
	var recovering_distance := rig.get_target_distance()
	assert_true(recovering_distance > pushed_distance, "camera begins recovering outward")
	assert_true(recovering_distance < 1.3, "camera does not snap/pop out in a single frame")


func test_look_ahead_leads_movement_intent() -> void:
	var rig := _rig()
	var camera := _camera(rig, null)
	var body := Vector3(0.0, 0.5, 0.0)
	camera.update(0.1, body, Vector3.UP, Vector3.ZERO)
	var resting_focus := rig.get_target_focus()

	# Move forward along -Z
	for i in 30:
		camera.update(1.0 / 60.0, body, Vector3.UP, Vector3.FORWARD)
	var forward_focus := rig.get_target_focus()
	assert_true(forward_focus.z < resting_focus.z, "moving forward shifts focus ahead in movement direction")


func _rig() -> CameraRig:
	var rig := load("res://scenes/camera/camera_rig.tscn").instantiate() as CameraRig
	rig.config = load("res://data/camera/octopus_camera.tres")
	add_to_tree(rig)
	return rig


func _camera(rig: CameraRig, collision: RopeCollision) -> OctopusCamera:
	var camera := OctopusCamera.new()
	camera.configure(load("res://data/octopus/default_octopus.tres"), rig, collision)
	return camera
