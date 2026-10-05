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

signal primary_drag(position: Vector2, relative: Vector2)
signal secondary_drag(relative: Vector2)
signal zoom(factor: float)

## Touch indices are >= 0, so the mouse pointer can never collide with a finger.
const MOUSE_POINTER := -1
const WHEEL_ZOOM_STEP := 1.12
## Below this finger spread (pixels) the pinch ratio is too noisy to use.
const MIN_PINCH_SPREAD := 1.0

var _pointers: Dictionary[int, Vector2] = {}
var _mouse_secondary_held := false


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
	_pointers.clear()
	_mouse_secondary_held = false


func get_pointer_count() -> int:
	return _pointers.size()


func _handle_touch(event: InputEventScreenTouch) -> bool:
	if event.pressed:
		_pointers[event.index] = event.position
		return true
	return _pointers.erase(event.index)


func _handle_mouse_button(event: InputEventMouseButton) -> bool:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pointers[MOUSE_POINTER] = event.position
				return true
			return _pointers.erase(MOUSE_POINTER)
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
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
	if _pointers.has(MOUSE_POINTER):
		return _move_pointer(MOUSE_POINTER, event.position)
	if _mouse_secondary_held:
		secondary_drag.emit(event.relative)
		return true
	return false


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
