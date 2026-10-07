class_name GestureTracker
extends RefCounted
## Mouse gestures plus touch ownership: each touch is claimed once at press.
## Unclaimed touches: two orbit/pinch; three pan; one/four or more do nothing.
## Adding/removing a finger changes only membership, never emits camera motion.

signal touch_started(id: int, position: Vector2)
signal touch_moved(id: int, position: Vector2)
signal touch_ended(id: int)
signal touch_orbit(relative: Vector2)
signal touch_pan(relative: Vector2)
signal touch_zoom(factor: float)

var _touches: Dictionary[int, Vector2] = {}
var _claimed: Dictionary[int, bool] = {}

signal primary_started(position: Vector2)
signal primary_drag(position: Vector2, relative: Vector2)
signal primary_ended
signal primary_cancelled
signal secondary_drag(relative: Vector2)
signal zoom(factor: float)
signal inspection_started
signal inspection_ended(position: Vector2)
var preserve_grip_during_inspection := false

## Touch indices are >= 0, so the mouse pointer can never collide with a finger.
const MOUSE_POINTER := -1
const WHEEL_ZOOM_STEP := 1.12
## Below this finger spread (pixels) the pinch ratio is too noisy to use.
const MIN_PINCH_SPREAD := 1.0

var _pointers: Dictionary[int, Vector2] = {}
var _mouse_secondary_held := false
var _primary_active := false
var _primary_id := -2
var _inspecting := false


## Returns true when the event was consumed as part of a gesture.
func handle(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return _handle_touch(event as InputEventScreenTouch)
	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		return _move_touch(drag.index, drag.position)
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return false # Mouse events synthesized from touch; already handled as touch.
	if event is InputEventMouseButton:
		return _handle_mouse_button(event as InputEventMouseButton)
	if event is InputEventMouseMotion:
		return _handle_mouse_motion(event as InputEventMouseMotion)
	if event is InputEventMagnifyGesture:
		zoom.emit((event as InputEventMagnifyGesture).factor)
		return true
	return false


func reset() -> void:
	for id: int in _touches.keys():
		_release_touch(id)
	_cancel_primary()
	_pointers.clear()
	_mouse_secondary_held = false


func get_pointer_count() -> int:
	return _pointers.size() + _touches.size()


func has_camera_gesture() -> bool:
	return _mouse_secondary_held or _touches.size() - _claimed.size() >= 2


## Releases must be observed before UI handling, even outside the scene area.
func is_captured_release(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return (not event.pressed or event.canceled) and _touches.has(event.index)
	if event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			return _pointers.has(MOUSE_POINTER)
		return _mouse_secondary_held and event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]
	return false


func is_captured_motion(event: InputEvent) -> bool:
	if event is InputEventScreenDrag:
		return _touches.has(event.index)
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		return _pointers.has(MOUSE_POINTER) or _mouse_secondary_held
	return false


func claim_touch(id: int) -> void:
	if _touches.has(id):
		_claimed[id] = true


func _handle_touch(event: InputEventScreenTouch) -> bool:
	if event.canceled or not event.pressed:
		return _release_touch(event.index)
	if not _touches.has(event.index):
		_touches[event.index] = event.position
		touch_started.emit(event.index, event.position)
	return true


func _release_touch(id: int) -> bool:
	if not _touches.erase(id): return false
	_claimed.erase(id)
	touch_ended.emit(id)
	return true


func _camera_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	for id: int in _touches:
		if not _claimed.has(id): points.append(_touches[id])
	return points


func _move_touch(id: int, position: Vector2) -> bool:
	if not _touches.has(id): return false
	var before := _camera_points()
	_touches[id] = position
	if _claimed.has(id):
		touch_moved.emit(id, position)
		return true
	var after := _camera_points()
	if after.size() not in [2, 3]: return true
	var relative := Vector2.ZERO
	for i in after.size(): relative += after[i] - before[i]
	relative /= float(after.size())
	if after.size() == 3:
		touch_pan.emit(relative)
	else:
		touch_orbit.emit(relative)
		var spread := before[0].distance_to(before[1])
		if spread >= MIN_PINCH_SPREAD:
			var factor := after[0].distance_to(after[1]) / spread
			if is_finite(factor) and factor > 0.0: touch_zoom.emit(factor)
	return true


func _handle_mouse_button(event: InputEventMouseButton) -> bool:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				return _press_pointer(MOUSE_POINTER, event.position)
			return _release_pointer(MOUSE_POINTER)
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				if preserve_grip_during_inspection and _primary_active:
					_inspecting = true
					inspection_started.emit()
				else:
					_cancel_primary()
			elif _inspecting:
				_inspecting = false
				inspection_ended.emit(_pointers.get(_primary_id, event.position))
			_mouse_secondary_held = event.pressed
			return true
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				var steps := event.factor if event.factor > 0.0 else 1.0
				var direction := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
				zoom.emit(pow(WHEEL_ZOOM_STEP, steps * direction))
			return true
	return false


func _handle_mouse_motion(event: InputEventMouseMotion) -> bool:
	if _mouse_secondary_held:
		if _pointers.has(MOUSE_POINTER):
			_pointers[MOUSE_POINTER] = event.position
		secondary_drag.emit(event.relative)
		return true
	if _pointers.has(MOUSE_POINTER):
		return _move_pointer(MOUSE_POINTER, event.position)
	return false


func _press_pointer(index: int, position: Vector2) -> bool:
	if _pointers.has(index):
		return true
	var first := _pointers.is_empty() and not _mouse_secondary_held
	_pointers[index] = position
	if first:
		_primary_active = true
		_primary_id = index
		primary_started.emit(position)
	else:
		_cancel_primary()
	return true


func _release_pointer(index: int) -> bool:
	if not _pointers.erase(index):
		return false
	if _inspecting:
		_inspecting = false
		inspection_ended.emit(_pointers.get(_primary_id, Vector2.ZERO))
		if index != _primary_id:
			return true
	if _primary_active:
		_primary_active = false
		primary_ended.emit()
	return true


func _cancel_primary() -> void:
	if _inspecting:
		_inspecting = false
		inspection_ended.emit(_pointers.get(_primary_id, Vector2.ZERO))
	if _primary_active:
		_primary_active = false
		primary_cancelled.emit()


func _move_pointer(index: int, position: Vector2) -> bool:
	if not _pointers.has(index):
		return false

	var previous: Vector2 = _pointers[index]
	_pointers[index] = position
	if _pointers.size() == 1:
		primary_drag.emit(position, position - previous)
	return true
