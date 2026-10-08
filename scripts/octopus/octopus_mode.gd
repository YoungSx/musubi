class_name OctopusMode
extends Node3D
## Scene root for octopus play: twin-stick input, the octopus, the rope and the
## follow camera, wired in one place.
##
## Frame order is explicit here rather than spread across node _process order:
## read input, advance the octopus, then move the camera. The rope keeps its own
## fixed-step schedule.

@export var camera_rig: CameraRig
@export var mannequin: Mannequin
@export var rope: Rope
@export var octopus: Octopus
@export var controls: OctopusControls

var _camera := OctopusCamera.new()
var _collision := RopeCollision.new()


func _ready() -> void:
	assert(camera_rig != null and mannequin != null and rope != null and octopus != null, "OctopusMode requires its scene references.")
	_collision.configure(mannequin.config, mannequin.global_transform)
	rope.set_collision(_collision)
	octopus.attach_to_world()
	_camera.configure(octopus.config, camera_rig, _collision)
	if controls != null:
		controls.grab_requested.connect(_grab)
		controls.release_requested.connect(octopus.release)
	_update_hint()


func _process(delta: float) -> void:
	var intent := SurfaceWalker.camera_intent(OctopusControls.read_move(), camera_rig.get_target_yaw(), octopus.get_up())
	octopus.advance(delta, intent)
	_camera.update(delta, octopus.get_position_in_world(), octopus.get_up(), intent)
	_update_hint()


## Maps an aim stick vector onto the world through the camera's own frame: screen
## right is the camera's right, screen up its up. A flick therefore points where
## the player sees the rope.
##
## Aiming deliberately ignores the climbing surface, which may be any wall, but
## it must keep the camera's pitch. A horizon-locked aim cannot reach material
## hanging above the body, which is where the rope is for most of a climb.
static func aim_direction(stick: Vector2, view: Basis) -> Vector3:
	if stick.is_zero_approx():
		return Vector3.ZERO
	var direction := view.x * stick.x - view.y * stick.y
	return direction.normalized() if direction.length_squared() > 1e-8 else Vector3.ZERO


func _grab(aim: Vector2) -> void:
	if octopus.is_holding():
		octopus.release()
		return
	# The view axis goes along with the aim: aim_direction spans the view plane,
	# so the cone has to be measured there too rather than against world depth.
	var view := camera_rig.get_camera().global_transform.basis
	octopus.grab(aim_direction(aim, view), view.z)
	_update_hint()


func _update_hint() -> void:
	if controls == null:
		return
	controls.set_hint("Tap the right stick to let go" if octopus.is_holding() else "Flick the right stick toward the rope")
