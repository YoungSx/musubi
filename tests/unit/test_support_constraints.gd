extends TestCase

func test_implicit_support_releases_as_one_edit_without_pins() -> void:
	var app := _app()
	app.handle_action(&"ground")
	app.history.clear()
	var before := app.rope.capture_scene_state()
	assert_true(app.rope.begin_support(0.513, 0.12), "implicit support grabs middle")
	assert_true(app.rope.begin_grip(1.0), "primary grip grabs end")
	assert_true(app.rope.capture_scene_state().is_empty(), "active constraints cannot be saved as completed intent")
	app.rope.update_drag_target(app.rope.get_simulation().get_point(app.rope.config.segment_count) + Vector3(-0.1, 0.01, 0.1))
	for frame in 90:
		app.rope.advance(1.0 / 60.0)
	assert_true(app.rope.get_simulation().get_support_position().y > 0.06, "support opens physical clearance")
	for i in app.rope.get_simulation().get_point_count():
		assert_true(not app.rope.get_simulation().is_pinned(i), "support is not a persistent pin")
	app.rope.end_support()
	assert_true(app.rope.get_simulation().get_drag_index() >= 0, "primary grip survives primary grip release")
	assert_eq(app.history.get_entry_count(), 0, "unfinished assisted action is not split into edits")
	app.rope.end_drag()
	assert_eq(app.history.get_entry_count(), 1, "grip and support form one transaction")
	app.handle_action(&"undo")
	assert_eq(app.rope.capture_scene_state(), before, "undo restores the whole action")

func test_support_simulation_snapshot_continues() -> void:
	var app := _app()
	app.handle_action(&"ground")
	app.rope.begin_support(0.513, 0.12)
	app.rope.begin_grip(1.0)
	for i in 20: app.rope.advance(1.0 / 60.0)
	var original := app.rope.get_simulation()
	var restored := RopeSimulation.restore_state(JSON.parse_string(JSON.stringify(original.capture_state(), "", true, true)))
	assert_true(restored != null, "grip and support decode")
	restored.set_collision(app.rope.get_collision())
	for i in 20:
		original.step(app.rope.config.get_time_step())
		restored.step(app.rope.config.get_time_step())
	assert_eq(original.get_positions(), restored.get_positions(), "both soft constraints resume deterministically")

func test_ground_over_and_under_intent() -> void:
	var points := PackedVector3Array([Vector3(-0.2, 0.012, 0), Vector3(-0.18, 0.012, 0), Vector3(-0.16, 0.012, 0), Vector3(0, 0.012, -0.1), Vector3(0, 0.012, 0.1)])
	var hand := GroundHand.new()
	hand.begin(points[0], 0)
	var above := hand.resolve(Vector3(0, 0.012, 0), points, 0, 0.012, 0, false, 0.1)
	assert_true(above.y >= 0.036, "ordinary crossing lifts over a low strand")
	hand.begin(points[0], 0)
	points[3].y = 0.12
	points[4].y = 0.12
	var below := hand.resolve(Vector3.ZERO, points, 0, 0.012, 0, true, 0.1)
	assert_true(below.y >= 0.012 and below.y + 0.024 < points[3].y, "support intent uses actual space below a lifted strand")

func test_fixed_ground_frame_keeps_stationary_hand_target() -> void:
	var app := _app()
	app.handle_action(&"ground")
	var view := app.camera_rig.capture_state()
	for frame in 120:
		app.camera_rig._process(1.0 / 60.0)
	assert_eq(app.camera_rig.capture_state(), view, "ground view does not chase motion")
	assert_true(rad_to_deg(app.camera_rig.get_target_pitch()) > 50, "floor work gets an oblique view without camera input")
	var screen := app.camera_rig.get_camera().unproject_position(app.rope.get_simulation().get_point(app.rope.config.segment_count))
	assert_true(app.interaction_manager._rope_interaction.begin(screen), "ground hand grabs")
	var target := app.rope.get_simulation().get_drag_target()
	app.camera_rig.orbit(Vector2(0.1, 0.05))
	app.camera_rig._process(0.1)
	app.interaction_manager._rope_interaction.move(screen)
	assert_vec3_near(app.rope.get_simulation().get_drag_target(), target, "camera movement alone cannot move rope intent")

func test_focus_loss_releases_support_and_primary() -> void:
	var app := _app()
	app.handle_action(&"ground")
	app.rope.begin_support(0.513, 0.12)
	var screen := app.camera_rig.get_camera().unproject_position(app.rope.get_simulation().get_point(0))
	app.interaction_manager._rope_interaction.begin(screen)
	app.interaction_manager._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	assert_true(not app.rope.has_support(), "support released on focus loss")
	assert_eq(app.rope.get_simulation().get_drag_index(), -1, "primary released on focus loss")
	assert_true(not app.rope.is_held(), "focus cleanup does not freeze Play")

func test_ground_camera_ignores_empty_drag_pan_and_wheel() -> void:
	var app := _app()
	app.handle_action(&"ground")
	var before := app.camera_rig.capture_state()
	app.interaction_manager._on_primary_drag(Vector2(100,100),Vector2(50,20))
	app.interaction_manager._on_secondary_drag(Vector2(50,20))
	app.interaction_manager._on_zoom(1.2)
	app.camera_rig._process(0.1)
	app.handle_action(&"focus")
	assert_eq(app.camera_rig.capture_state(),before,"ordinary mouse actions cannot disturb the ground camera")

func test_support_state_rejects_invalid_and_migrates_older_format() -> void:
	var app := _app()
	app.handle_action(&"ground")
	var state := app.rope.get_simulation().capture_state()
	state.support = {"u": 1.1, "target": [0,0,0]}
	assert_true(RopeState.decode(state).is_empty(),"out-of-range support is rejected")
	state.version = 3
	state.erase("support")
	assert_eq(RopeState.decode(state).support,{},"version three has no implicit support")

func _app() -> AppController:
	var app := add_to_tree(load("res://scenes/main/play.tscn").instantiate()) as AppController
	app.process_mode = Node.PROCESS_MODE_DISABLED
	return app
