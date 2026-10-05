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


func _ready() -> void:
	assert(camera_rig and mannequin and rope and interaction_manager and hud, "AppController is missing a module reference.")
	hud.reset_requested.connect(reset)
	_configure_collision()
	rope_debug.configure(rope, mannequin, hud)
	hud.debug_toggled.connect(rope_debug.set_debug_enabled)
	interaction_manager.hover_changed.connect(rope_debug.set_hover_index)
	$DesktopShortcuts.action_requested.connect(handle_action)


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


## Returns every module to its initial state.
func reset() -> void:
	interaction_manager.reset()
	mannequin.reset_pose()
	_configure_collision()
	rope.reset()
	camera_rig.reset_view()


func _configure_collision() -> void:
	var collision := RopeCollision.new()
	collision.configure(mannequin.config, mannequin.global_transform)
	rope.set_collision(collision)
