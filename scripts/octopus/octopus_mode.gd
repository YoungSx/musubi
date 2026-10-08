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
## Whether the aim currently has material in reach. Owned here rather than read
## back out of the indicator, which presents this state and does not define it.
var _aim_locked := false


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
	_update_aim()
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
	if not octopus.grab(aim_direction(aim, view), view.z) and controls != null:
		# A miss has to say so. The aim is judged by a cone and a line of sight,
		# both of which fail silently, and a silent failure is indistinguishable
		# from a stick that does nothing.
		controls.notify("Nothing in reach that way")
	_update_hint()


## Draws where the aim currently points, every frame the stick is pushed.
##
## The grab decides on release, so without this the player pushes the stick and
## sees nothing until the gesture is already spent. The preview runs the octopus's
## own aim query, so the ring marks exactly what releasing would take.
func _update_aim() -> void:
	if controls == null:
		return
	var stick := OctopusControls.read_aim()
	var camera := camera_rig.get_camera()
	# Nothing to preview while holding: a push of this stick releases whatever is
	# held, whichever way it points, so a target would promise a grab that is not
	# what the gesture does. Behind the camera there is no screen position to draw
	# at, and unproject_position does not report that -- it returns a point.
	if stick.is_zero_approx() or octopus.is_holding() or camera.is_position_behind(octopus.get_eye()):
		_aim_locked = false
		controls.clear_aim()
		return
	var view := camera.global_transform.basis
	var origin := camera.unproject_position(octopus.get_eye())
	var material := octopus.aim_material(aim_direction(stick, view), view.z)
	var target := octopus.get_material_position(material) if material >= 0.0 else Vector3.ZERO
	_aim_locked = material >= 0.0 and not camera.is_position_behind(target)
	if _aim_locked:
		controls.show_aim_target(origin, camera.unproject_position(target))
	else:
		controls.show_aim_search(origin, stick)


func _update_hint() -> void:
	if controls == null:
		return
	controls.set_hint(_hint_text())


## The steady hint. Aiming states come first: while the stick is pushed, what the
## line has to answer is whether releasing will take anything.
func _hint_text() -> String:
	if octopus.is_holding():
		return "Centre the right stick and release to let go"
	if OctopusControls.read_aim().is_zero_approx():
		return "Push the right stick toward the rope, then release"
	return "Release to grab" if _aim_locked else "Nothing in reach yet · keep sweeping"
