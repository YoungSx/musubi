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
@export var pass_assist_config: PassAssistConfig
signal hover_changed(index: int)

var _gestures := GestureTracker.new()
var _rope_interaction := RopeInteraction.new()
var _touch_grips: Dictionary[int, RopeInteraction] = {}
var _hover_index := -1
var _hover_time := 0.0
var _inspecting := false
var play_enabled := false
## Test-window policy seam. Real application windows always keep this enabled.
var cancel_on_focus_loss := true


func _ready() -> void:
	assert(camera_rig != null, "InteractionManager requires a CameraRig.")
	assert(rope != null, "InteractionManager requires a Rope.")
	_rope_interaction.configure(rope, camera_rig.get_camera())
	_rope_interaction.configure_pass_assistance(pass_assist_config)
	_gestures.primary_started.connect(_on_primary_started)
	_gestures.primary_drag.connect(_on_primary_drag)
	_gestures.primary_ended.connect(_on_primary_ended)
	_gestures.primary_cancelled.connect(_on_primary_ended)
	_gestures.secondary_drag.connect(_on_secondary_drag)
	_gestures.zoom.connect(_on_zoom)
	_gestures.inspection_started.connect(func(): _inspecting = get_selected_index() >= 0)
	_gestures.inspection_ended.connect(_on_inspection_ended)
	_gestures.touch_started.connect(_on_touch_started)
	_gestures.touch_moved.connect(_on_touch_moved)
	_gestures.touch_ended.connect(_on_touch_ended)
	_gestures.touch_orbit.connect(func(relative: Vector2): camera_rig.orbit(_to_screen_units(relative)))
	_gestures.touch_pan.connect(func(relative: Vector2): camera_rig.pan(_to_screen_units(relative)))
	_gestures.touch_zoom.connect(camera_rig.zoom)


func set_play_mode(enabled: bool) -> void:
	play_enabled = enabled
	_gestures.preserve_grip_during_inspection = enabled
	_rope_interaction.set_pass_assist_enabled(enabled)


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
	if cancel_on_focus_loss and (what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT):
		reset()


## Public event seam shared by real input and headless interaction tests.
func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouse and event.device != InputEvent.DEVICE_ID_EMULATION:
		_rope_interaction.pick_radius_pixels = 12.0
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		_rope_interaction.pick_radius_pixels = 24.0
	return _gestures.handle(event)


func _process(delta: float) -> void:
	_rope_interaction.tick(delta)
	for hand: RopeInteraction in _touch_grips.values(): hand.tick(delta)
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
	if not _touch_grips.is_empty():
		return _touch_grips.values()[0].get_selected_index()
	return _rope_interaction.get_selected_index()


func get_touch_grip_count() -> int:
	return _touch_grips.size()


func _on_touch_started(id: int, position: Vector2) -> void:
	var hand := RopeInteraction.new()
	hand.grip_id = id
	hand.configure(rope, camera_rig.get_camera())
	hand.configure_pass_assistance(pass_assist_config)
	hand.set_pass_assist_enabled(play_enabled)
	if hand.begin(position):
		_touch_grips[id] = hand
		_gestures.claim_touch(id)
		if rope.get_simulation().get_grip_count() > 1:
			for active: RopeInteraction in _touch_grips.values(): active.use_multiple_hands()
			if _rope_interaction.get_selected_index() >= 0: _rope_interaction.use_multiple_hands()


func _on_touch_moved(id: int, position: Vector2) -> void:
	if _touch_grips.has(id): _touch_grips[id].move(position)


func _on_touch_ended(id: int) -> void:
	if _touch_grips.has(id):
		_touch_grips[id].end()
		_touch_grips.erase(id)


func reset() -> void:
	_gestures.reset()
	_rope_interaction.end()
	rope.end_support()


func _on_primary_started(position: Vector2) -> void:
	_rope_interaction.begin(position)


func _on_primary_drag(position: Vector2, relative: Vector2) -> void:
	if _rope_interaction.get_selected_index() >= 0:
		_rope_interaction.move(position)
	else:
		if play_enabled and rope.initial_layout == Rope.InitialLayout.FLOOR:
			return
		camera_rig.orbit(_to_screen_units(relative))


func _on_primary_ended() -> void:
	_inspecting = false
	_rope_interaction.end()


func _on_secondary_drag(relative: Vector2) -> void:
	if play_enabled and rope.initial_layout == Rope.InitialLayout.FLOOR:
		return
	if _inspecting:
		camera_rig.orbit(_to_screen_units(relative))
	else:
		camera_rig.pan(_to_screen_units(relative))


func _on_zoom(factor: float) -> void:
	if play_enabled and rope.initial_layout == Rope.InitialLayout.FLOOR:
		return
	if _rope_interaction.get_selected_index() >= 0 and not _inspecting:
		_rope_interaction.adjust_depth(factor)
	else:
		camera_rig.zoom(factor)


## Normalizes pixel deltas by screen height so gestures feel identical on
## every resolution and aspect ratio.
func _to_screen_units(pixels: Vector2) -> Vector2:
	return pixels / maxf(get_viewport().get_visible_rect().size.y, 1.0)
