extends TestCase

var _tracker: GestureTracker
var _primary: Array[Vector2] = []
var _secondary: Array[Vector2] = []
var _zooms: Array[float] = []
var _starts: Array[Vector2] = []
var _ends := 0
var _cancels := 0


## Bound methods (not lambdas) so the tracker's connections don't capture
## `self` strongly, which would form a test <-> tracker reference cycle.
func _init() -> void:
	_tracker = GestureTracker.new()
	_tracker.primary_drag.connect(_on_primary_drag)
	_tracker.primary_started.connect(_on_primary_started)
	_tracker.primary_ended.connect(_on_primary_ended)
	_tracker.primary_cancelled.connect(_on_primary_cancelled)
	_tracker.secondary_drag.connect(_on_secondary_drag)
	_tracker.zoom.connect(_on_zoom)


func _on_primary_drag(_position: Vector2, relative: Vector2) -> void:
	_primary.append(relative)


func _on_primary_started(position: Vector2) -> void:
	_starts.append(position)


func _on_primary_ended() -> void:
	_ends += 1


func _on_primary_cancelled() -> void:
	_cancels += 1


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


func test_primary_lifecycle_and_duplicate_release() -> void:
	_tracker.handle(_touch(0, Vector2.ONE, true))
	_tracker.handle(_touch(0, Vector2.ONE, false))
	_tracker.handle(_touch(0, Vector2.ONE, false))
	assert_eq(_starts, [Vector2.ONE], "one primary start")
	assert_eq(_ends, 1, "one primary end")
	assert_eq(_cancels, 0, "ordinary release is not cancellation")


func test_two_finger_transition_never_restarts_primary_until_full_release() -> void:
	_tracker.handle(_touch(0, Vector2(10, 10), true))
	_tracker.handle(_touch(1, Vector2(20, 10), true))
	assert_eq(_cancels, 1, "second finger cancels primary")
	_tracker.handle(_touch(1, Vector2(20, 10), false))
	_tracker.handle(_drag(0, Vector2(30, 10)))
	assert_eq(_starts.size(), 1, "remaining finger does not start another pick")
	assert_eq(_primary.size(), 1, "remaining finger still drives camera motion")
	_tracker.handle(_touch(0, Vector2(30, 10), false))
	assert_eq(_ends, 0, "cancelled primary does not also end")
	_tracker.handle(_touch(2, Vector2.ONE, true))
	assert_eq(_starts.size(), 2, "new gesture may pick again")


func test_cancel_and_reset_emit_once_and_clear_capture() -> void:
	_tracker.handle(_touch(0, Vector2.ONE, true))
	var cancel := _touch(0, Vector2.ONE, true)
	cancel.canceled = true
	assert_true(_tracker.is_captured_release(cancel), "cancel treated as release even if pressed is true")
	_tracker.handle(cancel)
	_tracker.reset()
	assert_eq(_cancels, 1, "cancel emitted once")
	assert_eq(_tracker.get_pointer_count(), 0, "cancel removed pointer")
	assert_true(not _tracker.is_captured_release(cancel), "cancel no longer captured")
	_tracker.handle(_touch(1, Vector2.ZERO, true))
	_tracker.reset()
	assert_eq(_cancels, 2, "reset cancels active primary")


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
