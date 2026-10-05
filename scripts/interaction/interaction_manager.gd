class_name InteractionManager
extends Node
## Single entry point for user input in the 3D scene.
##
##   Input -> InteractionManager -> GestureTracker -> consumer
##
## Only receives input the UI did not consume. Today every gesture drives the
## camera; once the rope exists, primary drags will be hit-tested against the
## rope first and fall back to the camera when nothing is picked.

@export var camera_rig: CameraRig

var _gestures := GestureTracker.new()


func _ready() -> void:
	assert(camera_rig != null, "InteractionManager requires a CameraRig.")
	_gestures.primary_drag.connect(_on_primary_drag)
	_gestures.secondary_drag.connect(_on_secondary_drag)
	_gestures.zoom.connect(_on_zoom)


func _unhandled_input(event: InputEvent) -> void:
	if _gestures.handle(event):
		get_viewport().set_input_as_handled()


func reset() -> void:
	_gestures.reset()


func _on_primary_drag(_position: Vector2, relative: Vector2) -> void:
	camera_rig.orbit(_to_screen_units(relative))


func _on_secondary_drag(relative: Vector2) -> void:
	camera_rig.pan(_to_screen_units(relative))


func _on_zoom(factor: float) -> void:
	camera_rig.zoom(factor)


## Normalizes pixel deltas by screen height so gestures feel identical on
## every resolution and aspect ratio.
func _to_screen_units(pixels: Vector2) -> Vector2:
	return pixels / maxf(get_viewport().get_visible_rect().size.y, 1.0)
