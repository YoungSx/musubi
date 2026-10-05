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
