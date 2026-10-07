extends TestCase


func _rig() -> CameraRig:
	var rig := load("res://scenes/camera/camera_rig.tscn").instantiate() as CameraRig
	rig.config = CameraConfig.new()
	rig.config.focus = Vector3(0, 1, 0)
	rig.config.yaw_degrees = 0
	rig.config.pitch_degrees = 0
	rig.config.distance = 3.0
	add_to_tree(rig)
	rig.set_process(false)
	return rig


func test_default_and_mode_switch_do_not_change_pose() -> void:
	var rig := _rig()
	assert_eq(rig.mode, CameraRig.Mode.ASSISTED, "new default is assisted")
	var pose := rig.get_target_transform()
	rig.set_mode(CameraRig.Mode.FREE)
	assert_eq(rig.get_target_transform(), pose, "switch does not snap")
	rig.set_mode(CameraRig.Mode.ASSISTED)
	assert_eq(rig.get_target_transform(), pose, "switching back preserves pose")


func test_small_manipulation_and_passive_physics_leave_camera_stable() -> void:
	var rig := _rig()
	var controller := FollowCameraController.new()
	var grips: Dictionary[int, Vector3] = {0: Vector3(0, 1, 0)}
	var targets := grips.duplicate()
	var pose := rig.get_target_transform()
	controller.update(0.016, rig, grips, targets, PackedVector3Array(), null)
	for frame in 60:
		targets[0] = Vector3(float(frame) * 0.0008, 1, 0)
		grips[0] = targets[0]
		controller.update(0.016, rig, grips, targets, PackedVector3Array(), null)
	assert_eq(rig.get_target_transform(), pose, "fine work inside safe region keeps camera fixed")
	for frame in 90:
		grips[0] = Vector3(2, 1, 0) # Physics moves, but requested target does not.
		controller.update(0.016, rig, grips, targets, PackedVector3Array(), null)
	var settled := rig.get_target_transform()
	grips[0] = Vector3(-2, 0.1, 0)
	for frame in 60: controller.update(0.016, rig, grips, targets, PackedVector3Array(), null)
	assert_eq(rig.get_target_transform(), settled, "passive motion cannot restart tracking")


func test_edge_follow_requires_intent_and_is_rate_limited() -> void:
	var rig := _rig()
	var controller := FollowCameraController.new()
	var grips: Dictionary[int, Vector3] = {4: Vector3(1.8, 1, 0)}
	var targets := grips.duplicate()
	controller.update(0.016, rig, grips, targets, PackedVector3Array(), null)
	assert_vec3_near(rig.get_target_focus(), rig.config.focus, "press alone does not move camera")
	for frame in 30:
		targets[4].x += 0.004
		var before := rig.get_target_focus()
		controller.update(0.016, rig, grips, targets, PackedVector3Array(), null)
		assert_true(rig.get_target_focus().distance_to(before) <= rig.config.follow_focus_speed * 0.016 + 0.0001, "focus speed bounded")
	assert_true(rig.get_target_focus().x > 0.05, "camera follows operation leaving safe region")
	assert_true(absf(rig.get_target_yaw()) < deg_to_rad(15), "heading preference does not swing abruptly")


func test_free_mode_never_follows() -> void:
	var rig := _rig()
	rig.set_mode(CameraRig.Mode.FREE)
	var controller := FollowCameraController.new()
	var grips: Dictionary[int, Vector3] = {0: Vector3(2, 1, 0)}
	var targets := grips.duplicate()
	var pose := rig.get_target_transform()
	for frame in 60:
		targets[0].x += 0.01
		controller.update(0.016, rig, grips, targets, PackedVector3Array(), null)
	assert_eq(rig.get_target_transform(), pose, "legacy free camera is exact")


func test_manual_override_waits_for_fresh_drag_after_release() -> void:
	var rig := _rig()
	var controller := FollowCameraController.new()
	rig.manual_input.connect(controller.manual_override)
	var grips: Dictionary[int, Vector3] = {0: Vector3(2, 1, 0)}
	var targets := grips.duplicate()
	controller.update(0.016, rig, grips, targets, PackedVector3Array(), null)
	rig.pan(Vector2(0.03, 0))
	var pose := rig.get_target_transform()
	for frame in 30:
		targets[0].x += 0.01
		controller.update(0.016, rig, grips, targets, PackedVector3Array(), null, true)
	assert_eq(rig.get_target_transform(), pose, "manual gesture owns camera even while rope moves")
	for frame in 60: controller.update(0.016, rig, grips, targets, PackedVector3Array(), null)
	assert_eq(rig.get_target_transform(), pose, "timer expiry alone cannot recenter")
	targets[0].x += 0.01
	controller.update(0.016, rig, grips, targets, PackedVector3Array(), null)
	assert_true(rig.get_target_transform() != pose, "fresh drag resumes assistance")


func test_group_framing_moves_back_without_changing_fov() -> void:
	var rig := _rig()
	var controller := FollowCameraController.new()
	var grips: Dictionary[int, Vector3] = {0: Vector3(-1.7, 1, 0), 5: Vector3(1.7, 1, 0)}
	var targets := grips.duplicate()
	var fov := rig.get_camera().fov
	controller.update(0.016, rig, grips, targets, PackedVector3Array(), null)
	for frame in 30:
		targets[0].x -= 0.002
		targets[5].x += 0.002
		controller.update(0.016, rig, grips, targets, PackedVector3Array(), null)
	assert_true(rig.get_target_distance() > 3.2, "two grips get more room")
	assert_near(rig.get_target_yaw(), 0, "opposite hands do not fight over heading")
	assert_near(rig.get_camera().fov, fov, "no lens breathing")
	targets.erase(5)
	grips.erase(5)
	var pose := rig.get_target_transform()
	controller.update(0.016, rig, grips, targets, PackedVector3Array(), null)
	assert_eq(rig.get_target_transform(), pose, "releasing one hand does not snap framing")


func test_occlusion_has_delay_and_selects_a_slow_visible_orbit() -> void:
	var rig := _rig()
	var controller := FollowCameraController.new()
	var part := MannequinPart.new()
	part.primitive = MannequinPart.Primitive.SPHERE
	part.radius = 0.4
	part.position = Vector3(0, 1, 0)
	var mannequin := MannequinConfig.new()
	mannequin.parts = [part]
	var collision := RopeCollision.new()
	collision.floor_enabled = false
	collision.configure(mannequin)
	var grips: Dictionary[int, Vector3] = {0: Vector3(0, 1, -0.55)}
	var targets := grips.duplicate()
	controller.update(0.016, rig, grips, targets, PackedVector3Array(), collision)
	for frame in 10:
		targets[0].x += 0.001
		controller.update(0.016, rig, grips, targets, PackedVector3Array(), collision)
	assert_near(rig.get_target_yaw(), 0, "brief obstruction does not move camera")
	for frame in 150:
		targets[0].x += 0.001
		var yaw := rig.get_target_yaw()
		controller.update(0.016, rig, grips, targets, PackedVector3Array(), collision)
		assert_true(absf(rig.get_target_yaw() - yaw) <= deg_to_rad(35) * 0.016 + 0.0001, "avoidance rotation bounded")
	assert_true(absf(rig.get_target_yaw()) > 0.1, "persistent occlusion triggers orbit")
	assert_true(RopeVisibility.is_visible(rig.get_target_transform().origin, grips[0], collision), "orbit recovers line of sight")


func test_saved_modes_validate_and_legacy_creations_remain_free() -> void:
	var rig := _rig()
	var state := rig.capture_state()
	assert_true(rig.restore_state(JSON.parse_string(JSON.stringify(state, "", true, true))), "new mode round-trips through JSON numeric types")
	assert_eq(rig.mode, CameraRig.Mode.ASSISTED, "assisted saved")
	state.erase("mode")
	assert_true(rig.restore_state(state), "legacy camera snapshot accepted")
	assert_eq(rig.mode, CameraRig.Mode.FREE, "old creation keeps manual camera behavior")
	state.mode = 3
	assert_true(not rig.restore_state(state), "unknown mode rejected")


func test_menu_changes_mode_without_releasing_grips() -> void:
	var app := add_to_tree(load("res://scenes/main/play.tscn").instantiate()) as AppController
	app.rope.begin_grip(0.3, 4)
	app.hud._play_menu_selected(7)
	assert_eq(app.camera_rig.mode, CameraRig.Mode.FREE, "menu selects free camera")
	assert_eq(app.rope.get_simulation().get_grip_count(), 1, "mode switch retains hand")
	app.hud._play_menu_selected(6)
	assert_eq(app.camera_rig.mode, CameraRig.Mode.ASSISTED, "menu restores follow")
	var menu: PopupMenu = app.hud.get_node("%PlayMenu").get_popup()
	assert_true(menu.is_item_checked(menu.get_item_index(6)), "menu shows actual active mode")
