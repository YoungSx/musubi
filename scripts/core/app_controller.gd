class_name AppController
extends Node3D
## Root of the main scene: owns scene lifecycle and app-wide actions.
##
## Modules never reference each other directly; they are wired together here.

@export var camera_rig: CameraRig
@export var mannequin: Mannequin
@export var rope: Rope
@export var interaction_manager: InteractionManager
@export var hud: Hud
@export var rope_debug: RopeDebug
@export var play_mode := false

var _last_creation_path := ""
var history := RopeHistory.new()


func _ready() -> void:
	assert(camera_rig and mannequin and rope and interaction_manager and hud, "AppController is missing a module reference.")
	hud.reset_requested.connect(reset)
	_configure_collision()
	rope_debug.configure(rope, mannequin, hud)
	hud.debug_toggled.connect(rope_debug.set_debug_enabled)
	hud.action_requested.connect(handle_action)
	camera_rig.mode_changed.connect(hud.set_camera_mode)
	hud.set_camera_mode(camera_rig.mode)
	hud.save_requested.connect(save_creation)
	hud.load_requested.connect(load_creation)
	hud.new_rope_requested.connect(new_rope)
	interaction_manager.hover_changed.connect(rope_debug.set_hover_index)
	$DesktopShortcuts.action_requested.connect(handle_action)
	$PerformanceCapture.rope = rope
	rope.edit_completed.connect(_record_edit)
	_refresh_history_controls()
	set_play_mode(play_mode)


func handle_action(action: StringName) -> void:
	match action:
		&"camera_assisted", &"camera_free":
			camera_rig.set_mode(CameraRig.Mode.ASSISTED if action == &"camera_assisted" else CameraRig.Mode.FREE)
			hud.set_status("Camera: Assisted follow" if camera_rig.mode == CameraRig.Mode.ASSISTED else "Camera: Free")
		&"ground":
			interaction_manager.reset()
			var before := rope.capture_scene_state()
			rope.initial_layout = Rope.InitialLayout.FLOOR
			rope.hold_on_release = false
			rope.reset()
			set_play_mode(true)
			camera_rig.frame_ground(rope.config.length)
			_record_edit(before, rope.capture_scene_state())
		&"advanced":
			hud.set_advanced_visible(not hud.is_advanced_visible())
		&"debug":
			rope_debug.set_debug_enabled(not rope_debug.is_debug_enabled())
		&"reset": reset()
		&"focus":
			if play_mode and rope.initial_layout == Rope.InitialLayout.FLOOR:
				camera_rig.frame_ground(rope.config.length)
			else:
				camera_rig.reset_view()
		&"back":
			interaction_manager.reset()
			camera_rig.turn_around()
		&"pause":
			var held := rope.is_held()
			interaction_manager.reset()
			rope.set_held(not held)
		&"cancel": interaction_manager.cancel_drag()
		&"attachment_a", &"attachment_b":
			interaction_manager.reset()
			var before := rope.capture_scene_state()
			var side := 0 if action == &"attachment_a" else 1
			rope.set_endpoint_attached(side, not (rope.is_start_attached() if side == 0 else rope.is_end_attached()))
			_record_edit(before, rope.capture_scene_state())
		&"undo", &"redo":
			if interaction_manager.get_selected_index() >= 0 or rope.has_support():
				interaction_manager.cancel_drag()
				return
			var changed := history.undo(self) if action == &"undo" else history.redo(self)
			if changed:
				hud.set_status("Undone" if action == &"undo" else "Redone")
			_refresh_history_controls()
		&"fullscreen":
			get_window().mode = Window.MODE_WINDOWED if get_window().mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
		&"report": export_performance_report()
		&"save", &"load":
			interaction_manager.reset()
			hud.show_file_dialog(action == &"save", _last_creation_path)


func save_creation(path: String) -> Error:
	var state := MusubiSceneState.capture(self)
	if state.is_empty():
		hud.set_status("Release the rope before saving.")
		return ERR_BUSY
	var error := MusubiSceneState.write_file(path, state)
	if error == OK:
		_last_creation_path = path
	hud.set_status("Saved: " + path.get_file() if error == OK else "Could not save creation: " + error_string(error))
	return error


func new_rope(length_m: float) -> bool:
	if RopeConfig.for_length(length_m) == null:
		return false
	interaction_manager.reset()
	var before := rope.capture_scene_state()
	var changed := rope.new_rope(length_m)
	if changed:
		if rope.initial_layout == Rope.InitialLayout.FLOOR:
			camera_rig.frame_ground(rope.config.length)
		_record_edit(before, rope.capture_scene_state())
		_last_creation_path = ""
		$PerformanceCapture.recorder.reset()
		hud.set_status("New %.1f m rope" % length_m)
	return changed


func load_creation(path: String) -> bool:
	if not MusubiSceneState.apply(self, MusubiSceneState.read_file(path)):
		hud.set_status("Could not open this creation. The file is invalid or incompatible.")
		return false
	_last_creation_path = path
	history.clear()
	_refresh_history_controls()
	rope_debug.refresh_collision(mannequin)
	$PerformanceCapture.recorder.reset()
	hud.set_status("Opened: " + path.get_file())
	return true


func export_performance_report() -> Error:
	var capture := $PerformanceCapture as PerformanceCapture
	var state := MusubiSceneState.capture(self)
	if state.is_empty():
		hud.set_status("Release the rope before saving a report.")
		return ERR_BUSY
	var error := capture.export_report("user://reports", state)
	hud.set_status("Report saved: " + capture.last_report_path.get_file() if error == OK else "Could not save performance report.")
	return error


## Returns every module to its initial state.
func reset() -> void:
	interaction_manager.reset()
	var before := MusubiSceneState.capture(self)
	mannequin.reset_pose()
	_configure_collision()
	rope.reset()
	camera_rig.reset_view()
	if rope.initial_layout == Rope.InitialLayout.FLOOR:
		camera_rig.frame_ground(rope.config.length)
	$PerformanceCapture.recorder.reset()
	rope_debug.refresh_collision(mannequin)
	hud.set_status("")
	history.record(before, MusubiSceneState.capture(self))
	_refresh_history_controls()


func _record_edit(before: Dictionary, after: Dictionary) -> void:
	var scene_before := MusubiSceneState.capture(self)
	var scene_after := scene_before.duplicate(true)
	scene_before.rope = before
	scene_after.rope = after
	history.record(scene_before, scene_after)
	_refresh_history_controls()


func _refresh_history_controls() -> void:
	hud.set_history_state(history.can_undo(), history.can_redo())


func _configure_collision() -> void:
	var collision := RopeCollision.new()
	collision.configure(mannequin.config, mannequin.global_transform)
	rope.set_collision(collision)


func set_play_mode(enabled: bool) -> void:
	play_mode = enabled
	hud.set_play_mode(enabled)
	rope_debug.play_mode = enabled
	interaction_manager.set_play_mode(enabled)
