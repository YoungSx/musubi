class_name GestureTracker
extends RefCounted
## Translates raw touch and mouse events into device-independent gestures.
##
##   one pointer moving   -> primary_drag
##   two pointers moving  -> secondary_drag (centroid motion) + zoom (spread ratio)
##   mouse                -> left = primary pointer, right/middle drag = secondary,
##                           wheel = zoom
##
## Pure input logic without scene access: unit-testable, and reusable when the
## InteractionManager starts routing primary drags to the rope.

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
		return _move_pointer(drag.index, drag.position)
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
	_cancel_primary()
	_pointers.clear()
	_mouse_secondary_held = false


func get_pointer_count() -> int:
	return _pointers.size()


## Releases must be observed before UI handling, even outside the scene area.
func is_captured_release(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return (not event.pressed or event.canceled) and _pointers.has(event.index)
	if event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			return _pointers.has(MOUSE_POINTER)
		return _mouse_secondary_held and event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]
	return false


func is_captured_motion(event: InputEvent) -> bool:
	if event is InputEventScreenDrag:
		return _pointers.has(event.index)
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		return _pointers.has(MOUSE_POINTER) or _mouse_secondary_held
	return false


func _handle_touch(event: InputEventScreenTouch) -> bool:
	if event.canceled:
		if not _pointers.has(event.index):
			return false
		_cancel_primary()
		_pointers.erase(event.index)
		return true
	if event.pressed:
		return _press_pointer(event.index, event.position)
	return _release_pointer(event.index)


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
	elif preserve_grip_during_inspection and _primary_active and _pointers.size() == 2:
		_inspecting = true
		inspection_started.emit()
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

	if _pointers.size() == 2:
		var centroid_before := _centroid()
		var spread_before := _spread()
		_pointers[index] = position
		secondary_drag.emit(_centroid() - centroid_before)
		if spread_before >= MIN_PINCH_SPREAD:
			zoom.emit(_spread() / spread_before)
		return true

	var previous: Vector2 = _pointers[index]
	_pointers[index] = position
	if _pointers.size() == 1:
		primary_drag.emit(position, position - previous)
	return true


func _centroid() -> Vector2:
	var sum := Vector2.ZERO
	for point: Vector2 in _pointers.values():
		sum += point
	return sum / float(_pointers.size())


func _spread() -> float:
	var points := _pointers.values()
	var a: Vector2 = points[0]
	var b: Vector2 = points[1]
	return a.distance_to(b)
