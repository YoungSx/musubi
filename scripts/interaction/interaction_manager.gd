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
signal hover_changed(index: int)

var _gestures := GestureTracker.new()
var _rope_interaction := RopeInteraction.new()
var _hover_index := -1
var _hover_time := 0.0
var _inspecting := false


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
	_gestures.inspection_started.connect(func(): _inspecting = get_selected_index() >= 0)
	_gestures.inspection_ended.connect(_on_inspection_ended)


func set_play_mode(enabled: bool) -> void:
	_gestures.preserve_grip_during_inspection = enabled


func _on_inspection_ended(position: Vector2) -> void:
	_inspecting = false
	_rope_interaction.rebase(position)


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
	if event is InputEventMouse and event.device != InputEvent.DEVICE_ID_EMULATION:
		_rope_interaction.pick_radius_pixels = 12.0
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		_rope_interaction.pick_radius_pixels = 24.0
	return _gestures.handle(event)


func _process(delta: float) -> void:
	if not OS.has_feature("pc"):
		return
	_hover_time -= delta
	if _hover_time > 0.0:
		return
	_hover_time = 0.05
	var index := -1
	var point := get_viewport().get_mouse_position()
	if _gestures.get_pointer_count() == 0 and get_viewport().gui_get_hovered_control() == null and get_viewport().get_visible_rect().has_point(point):
		_rope_interaction.pick_radius_pixels = 12.0
		index = _rope_interaction.pick(point)
	if index != _hover_index:
		_hover_index = index
		hover_changed.emit(index)
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if index >= 0 else Input.CURSOR_ARROW)


func cancel_drag() -> void:
	_rope_interaction.cancel()
	_gestures.reset()


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
	_inspecting = false
	_rope_interaction.end()


func _on_secondary_drag(relative: Vector2) -> void:
	if _inspecting:
		camera_rig.orbit(_to_screen_units(relative))
	else:
		camera_rig.pan(_to_screen_units(relative))


func _on_zoom(factor: float) -> void:
	if _rope_interaction.get_selected_index() >= 0 and not _inspecting:
		_rope_interaction.adjust_depth(factor)
	else:
		camera_rig.zoom(factor)


## Normalizes pixel deltas by screen height so gestures feel identical on
## every resolution and aspect ratio.
func _to_screen_units(pixels: Vector2) -> Vector2:
	return pixels / maxf(get_viewport().get_visible_rect().size.y, 1.0)
