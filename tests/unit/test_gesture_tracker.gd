extends TestCase

var _tracker: GestureTracker
var _primary: Array[Vector2] = []
var _secondary: Array[Vector2] = []
var _zooms: Array[float] = []
var _starts: Array[Vector2] = []
var _orbit: Array[Vector2] = []
var _pan: Array[Vector2] = []
var _touch_moves: Array[int] = []
var _touch_ends: Array[int] = []
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
	_tracker.touch_orbit.connect(_on_orbit)
	_tracker.touch_pan.connect(_on_pan)
	_tracker.touch_zoom.connect(_on_zoom)
	_tracker.touch_moved.connect(_on_touch_move)
	_tracker.touch_ended.connect(_on_touch_end)


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

func _on_orbit(relative: Vector2) -> void: _orbit.append(relative)
func _on_pan(relative: Vector2) -> void: _pan.append(relative)
func _on_touch_move(id: int, _position: Vector2) -> void: _touch_moves.append(id)
func _on_touch_end(id: int) -> void: _touch_ends.append(id)


func test_two_free_fingers_orbit_and_pinch_three_pan() -> void:
	_tracker.handle(_touch(5, Vector2(100, 100), true))
	_tracker.handle(_drag(5, Vector2(110, 100)))
	assert_true(_orbit.is_empty() and _pan.is_empty(), "one free finger does not move camera")
	_tracker.handle(_touch(9, Vector2(210, 100), true))
	_tracker.handle(_drag(9, Vector2(310, 100)))
	assert_eq(_orbit, [Vector2(50, 0)], "two free touches orbit by centroid")
	assert_eq(_zooms, [2.0], "two free touches pinch")
	_tracker.handle(_touch(2, Vector2(210, 200), true))
	_tracker.handle(_drag(2, Vector2(240, 230)))
	assert_eq(_pan, [Vector2(10, 10)], "three free touches pan")
	assert_eq(_orbit.size(), 1, "pan does not orbit")
	assert_eq(_zooms.size(), 1, "pan does not zoom")


func test_claimed_touches_move_independently_and_do_not_count_for_camera() -> void:
	for id in [0, 7]:
		_tracker.handle(_touch(id, Vector2(id * 20, 20), true))
		_tracker.claim_touch(id)
	_tracker.handle(_drag(7, Vector2(180, 40)))
	_tracker.handle(_drag(0, Vector2(15, 40)))
	assert_eq(_touch_moves, [7, 0], "each grip receives its own moves")
	assert_true(_orbit.is_empty() and _zooms.is_empty(), "two grips never become a camera gesture")
	_tracker.handle(_touch(3, Vector2(300, 300), true))
	_tracker.handle(_drag(3, Vector2(320, 300)))
	assert_true(_orbit.is_empty(), "one free finger beside grips does not orbit")
	_tracker.handle(_touch(4, Vector2(400, 300), true))
	_tracker.handle(_drag(4, Vector2(420, 300)))
	assert_eq(_orbit, [Vector2(10, 0)], "two free fingers orbit beside two grips")


func test_membership_changes_rebase_without_jump_or_repick() -> void:
	_tracker.handle(_touch(0, Vector2.ZERO, true))
	_tracker.handle(_touch(1, Vector2(100, 0), true))
	_tracker.handle(_touch(2, Vector2(900, 900), true))
	assert_true(_orbit.is_empty() and _pan.is_empty(), "adding fingers never emits a delta")
	_tracker.handle(_touch(2, Vector2.ZERO, false))
	_tracker.handle(_drag(1, Vector2(100, 0)))
	assert_eq(_orbit, [Vector2.ZERO], "three-to-two transition has fresh baseline")
	_tracker.handle(_touch(1, Vector2.ZERO, false))
	_tracker.handle(_drag(0, Vector2(30, 0)))
	assert_eq(_orbit.size(), 1, "remaining finger stays idle")
	assert_true(_touch_moves.is_empty(), "camera fingers never acquire a grip midway")


func test_cancel_release_and_reset_clear_each_capture_once() -> void:
	for id in [2, 8]:
		_tracker.handle(_touch(id, Vector2.ONE, true))
		_tracker.claim_touch(id)
	var cancel := _touch(2, Vector2.ONE, true)
	cancel.canceled = true
	assert_true(_tracker.is_captured_release(cancel), "pressed cancellation is a release")
	_tracker.handle(cancel)
	_tracker.handle(cancel)
	_tracker.handle(_drag(8, Vector2(30, 30)))
	assert_eq(_touch_moves, [8], "other finger survives cancellation")
	_tracker.reset()
	_tracker.reset()
	assert_eq(_touch_ends, [2, 8], "one end per finger")
	assert_eq(_tracker.get_pointer_count(), 0, "all capture cleared")


func test_four_free_touches_and_degenerate_pinch_are_safe() -> void:
	_tracker.handle(_touch(0, Vector2.ZERO, true))
	_tracker.handle(_touch(1, Vector2.ZERO, true))
	_tracker.handle(_drag(1, Vector2.ONE))
	assert_true(_zooms.is_empty(), "zero spread cannot divide")
	_tracker.handle(_touch(2, Vector2(200, 0), true))
	_tracker.handle(_touch(3, Vector2(300, 0), true))
	_tracker.handle(_drag(3, Vector2(330, 30)))
	assert_eq(_orbit.size(), 1, "four free touches do not orbit")
	assert_true(_pan.is_empty(), "four free touches do not pan")
