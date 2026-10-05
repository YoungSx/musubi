class_name InteractionManager
extends Node
## Single entry point for user input in the 3D scene.
##
##   Input -> InteractionManager -> GestureTracker -> consumer
##
## Presses begin only outside UI. Captured motion and release are observed
## before UI handling so crossing a button cannot leave a stuck constraint.

@export var camera_rig: CameraRig
@export var rope: Rope

var _gestures := GestureTracker.new()
var _rope_interaction := RopeInteraction.new()


func _ready() -> void:
	assert(camera_rig != null, "InteractionManager requires a CameraRig.")
	assert(rope != null, "InteractionManager requires a Rope.")
	_rope_interaction.configure(rope, camera_rig.get_camera())
	_gestures.primary_started.connect(_on_primary_started)
	_gestures.primary_drag.connect(_on_primary_drag)
	_gestures.primary_ended.connect(_on_primary_ended)
	_gestures.primary_cancelled.connect(_on_primary_ended)
	_gestures.secondary_drag.connect(_on_secondary_drag)
	_gestures.zoom.connect(_on_zoom)


func _unhandled_input(event: InputEvent) -> void:
	if handle_input(event):
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if _gestures.is_captured_release(event):
		# Allow UI to see its own release too. Reprocessing in unhandled_input
		# is harmless: the pointer has already been removed.
		handle_input(event)
	elif _gestures.is_captured_motion(event):
		handle_input(event)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		reset()


## Public event seam shared by real input and headless interaction tests.
func handle_input(event: InputEvent) -> bool:
	return _gestures.handle(event)


func get_selected_index() -> int:
	return _rope_interaction.get_selected_index()


func reset() -> void:
	_gestures.reset()
	_rope_interaction.end()


func _on_primary_started(position: Vector2) -> void:
	_rope_interaction.begin(position)


func _on_primary_drag(position: Vector2, relative: Vector2) -> void:
	if _rope_interaction.get_selected_index() >= 0:
		_rope_interaction.move(position)
	else:
		camera_rig.orbit(_to_screen_units(relative))


func _on_primary_ended() -> void:
	_rope_interaction.end()


func _on_secondary_drag(relative: Vector2) -> void:
	camera_rig.pan(_to_screen_units(relative))


func _on_zoom(factor: float) -> void:
	camera_rig.zoom(factor)


## Normalizes pixel deltas by screen height so gestures feel identical on
## every resolution and aspect ratio.
func _to_screen_units(pixels: Vector2) -> Vector2:
	return pixels / maxf(get_viewport().get_visible_rect().size.y, 1.0)
