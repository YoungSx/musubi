extends TestCase

const RopeScene := preload("res://scenes/rope/rope.tscn")
const CameraScene := preload("res://scenes/camera/camera_rig.tscn")

var _rope: Rope
var _rig: CameraRig
var _manager: InteractionManager


func test_visible_segment_grab_has_no_jump_and_moves_target_only() -> void:
	_setup()
	# Give this grab test slack; the other fixtures deliberately use a taut rope.
	_rope.config.length = 1.2
	_rope.reset()
	var interaction := RopeInteraction.new()
	interaction.configure(_rope, _rig.get_camera())
	var point := _rope.get_simulation().get_point(2)
	var press := _screen(2) + Vector2(0, 10)
	assert_true(interaction.begin(press), "touch tolerance selects rope")
	assert_eq(interaction.get_selected_index(), 2, "center particle selected")
	interaction.move(press)
	assert_vec3_near(_rope.get_simulation().get_drag_target(), point, "grab offset prevents jump")
	interaction.move(press + Vector2(35, 0))
	assert_true(_rope.get_simulation().get_drag_target().x > point.x, "screen motion updates world target")
	assert_vec3_near(_rope.get_simulation().get_point(2), point, "input itself does not change particle positions")
	interaction.end()
	assert_eq(_rope.get_simulation().get_drag_index(), -1, "end removes temporary constraint")


func test_endpoints_can_be_picked_but_hidden_rope_cannot() -> void:
	_setup()
	var interaction := RopeInteraction.new()
	interaction.configure(_rope, _rig.get_camera())
	assert_true(interaction.begin(_screen(0)), "attached endpoint can be grabbed")
	assert_true(not _rope.is_start_attached(), "grabbing endpoint releases its attachment")
	interaction.cancel()
	assert_true(_rope.is_start_attached(), "cancel restores endpoint attachment")
	var part := MannequinPart.new()
	part.primitive = MannequinPart.Primitive.SPHERE
	part.radius = 0.15
	part.position = Vector3(0, 1, 0.3)
	var mannequin_config := MannequinConfig.new()
	mannequin_config.parts = [part]
	var collision := RopeCollision.new()
	collision.floor_enabled = false
	collision.configure(mannequin_config)
	_rope.set_collision(collision)
	assert_true(not interaction.begin(_screen(2)), "body occludes centerline")
	_rope.set_collision(null)
	assert_true(interaction.begin(_screen(2)), "same point selects when unobstructed")
	interaction.end()


func test_hit_routes_to_rope_and_miss_stays_camera_until_release() -> void:
	_setup()
	var yaw := _rig.get_target_yaw()
	_manager.handle_input(_touch(0, _screen(2), true))
	_manager.handle_input(_drag(0, _screen(2) + Vector2(30, 0)))
	assert_eq(_manager.get_selected_index(), 2, "hit routed to rope")
	assert_near(_rig.get_target_yaw(), yaw, "rope movement leaves camera alone")
	_manager.handle_input(_touch(0, _screen(2), false))
	_manager.handle_input(_touch(1, Vector2(10, 10), true))
	_manager.handle_input(_drag(1, _screen(2)))
	assert_eq(_manager.get_selected_index(), -1, "camera gesture cannot acquire rope midway")
	assert_true(not is_equal_approx(_rig.get_target_yaw(), yaw), "empty-space gesture rotates camera")
	_manager.reset()


func test_release_before_ui_handling_clears_drag() -> void:
	_setup()
	_manager.handle_input(_touch(0, _screen(2), true))
	assert_eq(_manager.get_selected_index(), 2, "drag began")
	# UI may consume the release, so unhandled_input will never be called.
	_manager._input(_touch(0, Vector2(195, 790), false))
	assert_eq(_manager.get_selected_index(), -1, "pre-UI release clears selection")
	assert_eq(_rope.get_simulation().get_drag_index(), -1, "pre-UI release removes constraint")


func test_second_finger_cancels_drag_and_remaining_finger_cannot_repick() -> void:
	_setup()
	_manager.handle_input(_touch(0, _screen(2), true))
	_manager.handle_input(_touch(1, _screen(2) + Vector2(100, 0), true))
	assert_eq(_manager.get_selected_index(), -1, "second finger releases rope")
	var distance := _rig.get_target_distance()
	_manager.handle_input(_drag(1, _screen(2) + Vector2(130, 0)))
	assert_true(_rig.get_target_distance() < distance, "two-finger pinch zooms")
	_manager.handle_input(_touch(1, _screen(2), false))
	var yaw := _rig.get_target_yaw()
	_manager.handle_input(_drag(0, _screen(2) + Vector2(10, 0)))
	assert_eq(_manager.get_selected_index(), -1, "remaining finger remains camera-only")
	assert_true(not is_equal_approx(_rig.get_target_yaw(), yaw), "remaining finger orbits")
	_manager.reset()


func test_canceled_touch_focus_loss_and_reset_clear_constraints() -> void:
	_setup()
	_manager.handle_input(_touch(0, _screen(2), true))
	var cancel := _touch(0, _screen(2), false)
	cancel.canceled = true
	_manager._input(cancel)
	assert_eq(_rope.get_simulation().get_drag_index(), -1, "cancel clears drag")
	_manager.handle_input(_touch(1, _screen(2), true))
	_manager.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	assert_eq(_manager.get_selected_index(), -1, "focus loss clears selection")
	assert_eq(_rope.get_simulation().get_drag_index(), -1, "focus loss clears constraint")
	_manager.handle_input(_touch(2, _screen(2), true))
	_manager.reset()
	assert_eq(_rope.get_simulation().get_drag_index(), -1, "reset clears constraint")


func _setup() -> void:
	_rig = CameraScene.instantiate() as CameraRig
	_rig.config = CameraConfig.new()
	_rig.config.focus = Vector3(0, 1, 0)
	_rig.config.distance = 3.0
	_rig.config.yaw_degrees = 0.0
	_rig.config.pitch_degrees = 0.0
	add_to_tree(_rig)
	_rig.set_process(false)
	_rope = RopeScene.instantiate() as Rope
	_rope.config = RopeConfig.new()
	_rope.config.segment_count = 4
	_rope.config.length = 1.0
	_rope.get_node("StartAnchor").position = Vector3(-0.5, 1, 0)
	_rope.get_node("EndAnchor").position = Vector3(0.5, 1, 0)
	add_to_tree(_rope)
	_rope.set_process(false)
	_manager = InteractionManager.new()
	_manager.camera_rig = _rig
	_manager.rope = _rope
	add_to_tree(_manager)


func _screen(index: int) -> Vector2:
	return _rig.get_camera().unproject_position(_rope.get_simulation().get_point(index))


func _touch(index: int, position: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	return event


func _drag(index: int, position: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	return event
