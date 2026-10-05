extends TestCase

var _tracker: GestureTracker
var _primary: Array[Vector2] = []
var _secondary: Array[Vector2] = []
var _zooms: Array[float] = []


## Bound methods (not lambdas) so the tracker's connections don't capture
## `self` strongly, which would form a test <-> tracker reference cycle.
func _init() -> void:
	_tracker = GestureTracker.new()
	_tracker.primary_drag.connect(_on_primary_drag)
	_tracker.secondary_drag.connect(_on_secondary_drag)
	_tracker.zoom.connect(_on_zoom)


func _on_primary_drag(_position: Vector2, relative: Vector2) -> void:
	_primary.append(relative)


func _on_secondary_drag(relative: Vector2) -> void:
	_secondary.append(relative)


func _on_zoom(factor: float) -> void:
	_zooms.append(factor)


func test_single_finger_emits_primary_drag() -> void:
	_tracker.handle(_touch(0, Vector2(100, 100), true))
	_tracker.handle(_drag(0, Vector2(110, 95)))
	assert_eq(_primary.size(), 1, "one primary drag")
	assert_eq(_primary[0], Vector2(10, -5), "primary relative")
	assert_true(_secondary.is_empty() and _zooms.is_empty(), "no secondary gestures")


func test_two_fingers_emit_pan_and_pinch() -> void:
	_tracker.handle(_touch(0, Vector2(100, 100), true))
	_tracker.handle(_touch(1, Vector2(200, 100), true))
	_tracker.handle(_drag(1, Vector2(300, 100)))
	assert_true(_primary.is_empty(), "no primary drag with two fingers")
	assert_eq(_secondary.size(), 1, "one secondary drag")
	assert_eq(_secondary[0], Vector2(50, 0), "centroid motion")
	assert_eq(_zooms.size(), 1, "one zoom")
	assert_near(_zooms[0], 2.0, "spread doubled")


func test_release_and_reset_clear_pointers() -> void:
	_tracker.handle(_touch(0, Vector2.ZERO, true))
	_tracker.handle(_touch(1, Vector2.ONE, true))
	_tracker.handle(_touch(0, Vector2.ZERO, false))
	assert_eq(_tracker.get_pointer_count(), 1, "one pointer after release")
	_tracker.reset()
	assert_eq(_tracker.get_pointer_count(), 0, "no pointers after reset")


func test_mouse_left_drag_and_wheel() -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(10, 10)
	_tracker.handle(press)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(20, 10)
	_tracker.handle(motion)
	assert_eq(_primary.size(), 1, "mouse drag is primary")
	assert_eq(_primary[0], Vector2(10, 0), "mouse relative")

	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	_tracker.handle(wheel)
	assert_eq(_zooms.size(), 1, "wheel zooms")
	assert_true(_zooms[0] > 1.0, "wheel up zooms in")


func test_emulated_mouse_is_ignored() -> void:
	var press := InputEventMouseButton.new()
	press.device = InputEvent.DEVICE_ID_EMULATION
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	assert_true(not _tracker.handle(press), "emulated mouse not consumed")
	assert_eq(_tracker.get_pointer_count(), 0, "no pointer registered")


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
