extends TestCase

const CameraRigScene := preload("res://scenes/camera/camera_rig.tscn")


func test_camera_looks_at_focus() -> void:
	var focus := Vector3(0.2, 1.0, -0.3)
	var xform := CameraRig.compute_camera_transform(0.7, 0.3, 2.5, focus)
	assert_near(xform.origin.distance_to(focus), 2.5, "camera at orbit distance")
	var forward := -xform.basis.z
	assert_vec3_near(forward, (focus - xform.origin).normalized(), "camera faces focus")


func test_positive_pitch_is_above_focus() -> void:
	var xform := CameraRig.compute_camera_transform(0.0, deg_to_rad(30.0), 2.0, Vector3.ZERO)
	assert_true(xform.origin.y > 0.0, "camera above focus")


func test_reset_restores_default_view() -> void:
	var rig := _make_rig()
	var config := rig.config
	rig.orbit(Vector2(0.3, 0.2))
	rig.zoom(1.5)
	rig.pan(Vector2(0.1, 0.1))
	rig.reset_view()
	assert_near(rig.get_target_yaw(), deg_to_rad(config.yaw_degrees), "yaw reset")
	assert_near(rig.get_target_pitch(), deg_to_rad(config.pitch_degrees), "pitch reset")
	assert_near(rig.get_target_distance(), config.distance, "distance reset")
	assert_vec3_near(rig.get_target_focus(), config.focus, "focus reset")


func test_limits_are_enforced() -> void:
	var rig := _make_rig()
	var config := rig.config
	rig.orbit(Vector2(0.0, 100.0))
	assert_near(rig.get_target_pitch(), deg_to_rad(config.max_pitch_degrees), "pitch clamped")
	rig.zoom(1000.0)
	assert_near(rig.get_target_distance(), config.min_distance, "zoom-in clamped")
	rig.zoom(0.0001)
	assert_near(rig.get_target_distance(), config.max_distance, "zoom-out clamped")
	rig.pan(Vector2(100.0, 100.0))
	assert_near(rig.get_target_focus().distance_to(config.focus), config.max_focus_offset, "pan clamped")


func test_orbit_changes_yaw() -> void:
	var rig := _make_rig()
	var before := rig.get_target_yaw()
	rig.orbit(Vector2(0.1, 0.0))
	assert_true(not is_equal_approx(rig.get_target_yaw(), before), "yaw changed")


func _make_rig() -> CameraRig:
	return add_to_tree(CameraRigScene.instantiate()) as CameraRig
