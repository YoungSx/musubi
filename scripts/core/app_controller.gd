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

var _last_creation_path := ""


func _ready() -> void:
	assert(camera_rig and mannequin and rope and interaction_manager and hud, "AppController is missing a module reference.")
	hud.reset_requested.connect(reset)
	_configure_collision()
	rope_debug.configure(rope, mannequin, hud)
	hud.debug_toggled.connect(rope_debug.set_debug_enabled)
	hud.action_requested.connect(handle_action)
	hud.save_requested.connect(save_creation)
	hud.load_requested.connect(load_creation)
	interaction_manager.hover_changed.connect(rope_debug.set_hover_index)
	$DesktopShortcuts.action_requested.connect(handle_action)
	$PerformanceCapture.rope = rope


func handle_action(action: StringName) -> void:
	match action:
		&"reset": reset()
		&"focus": camera_rig.reset_view()
		&"pause":
			var held := rope.is_held()
			interaction_manager.reset()
			rope.set_held(not held)
		&"cancel": interaction_manager.cancel_drag()
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


func load_creation(path: String) -> bool:
	if not MusubiSceneState.apply(self, MusubiSceneState.read_file(path)):
		hud.set_status("Could not open this creation. The file is invalid or incompatible.")
		return false
	_last_creation_path = path
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
	mannequin.reset_pose()
	_configure_collision()
	rope.reset()
	camera_rig.reset_view()
	$PerformanceCapture.recorder.reset()
	rope_debug.refresh_collision(mannequin)
	hud.set_status("")


func _configure_collision() -> void:
	var collision := RopeCollision.new()
	collision.configure(mannequin.config, mannequin.global_transform)
	rope.set_collision(collision)
