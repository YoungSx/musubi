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


func _ready() -> void:
	assert(camera_rig and mannequin and rope and interaction_manager and hud, "AppController is missing a module reference.")
	hud.reset_requested.connect(reset)


## Returns every module to its initial state.
func reset() -> void:
	interaction_manager.reset()
	rope.reset()
	mannequin.reset_pose()
	camera_rig.reset_view()
