class_name Octopus
extends Node3D
## A climbing octopus: a surface walker, one elastic arm and one rope grip.
##
## It owns no input and no camera. Callers advance it with a world-space move
## intent and ask it to grab along an aim direction; everything else is the
## composition of SurfaceWalker, OctopusArm, OctopusGrab, and OctopusLocomotion.

const OctopusLocomotionScript = preload("res://scripts/octopus/octopus_locomotion.gd")

@export var config: OctopusConfig
@export var rope: Rope
@export var skin: OctopusSkin
@export var mascot: Node3D
## Where the octopus starts, in this node's parent space.
@export var spawn_point: Vector3 = Vector3(0.0, 0.0, 0.55)

var _walker := SurfaceWalker.new()
var _arm := OctopusArm.new()
var _grab := OctopusGrab.new()
var _locomotion = OctopusLocomotionScript.new()
var _base_mascot_transform: Transform3D
var _active_shoulder_local_dir := Vector2(0.0, 1.0)


func _ready() -> void:
	assert(config != null, "Octopus requires an OctopusConfig.")
	assert(rope != null, "Octopus requires a Rope to grab.")
	_arm.configure(config)
	_grab.configure(config, rope)
	if skin != null:
		skin.configure(config)
	if mascot == null and has_node("Mascot"):
		mascot = get_node("Mascot") as Node3D
	if mascot != null:
		_base_mascot_transform = mascot.transform


## Call after the rope's collision geometry is installed.
func attach_to_world() -> void:
	_walker.configure(config, rope.get_collision())
	_walker.place(spawn_point)
	_apply_transform()
	_update_skin()


func advance(delta: float, intent: Vector3) -> void:
	if delta <= 0.0:
		return
	var was_attached := _walker.is_attached()
	var effective_intent := intent
	if _grab.is_active() and "carry_drag_factor" in config:
		effective_intent *= config.carry_drag_factor
	var speed := effective_intent.length() * config.move_speed
	_walker.step(delta, effective_intent)
	_apply_transform(delta)

	var is_now_attached := _walker.is_attached()
	if not was_attached and is_now_attached:
		_locomotion.trigger_landing_impact(0.18)

	if mascot != null:
		var vert_vel := _walker.velocity.y if not is_now_attached else 0.0
		_locomotion.step(delta, speed, mascot, _base_mascot_transform, vert_vel, not is_now_attached)
	if _grab.is_active():
		_grab.carry(get_carry_point(), delta)
		_arm.hold(get_shoulder(_grab.get_position()), _grab.get_position(), _grab.is_drawn_in())
	_arm.step(delta)
	_update_skin()


## Jumps off the surface along its normal, with optional horizontal intent.
func jump(horizontal_intent := Vector3.ZERO) -> bool:
	return _walker.jump(horizontal_intent)


func is_attached() -> bool:
	return _walker.is_attached()


func get_locomotion() -> OctopusLocomotion:
	return _locomotion


## Grabs rope along an aim direction. A zero direction takes the nearest visible
## material, which is the conventional fallback for an aimless tap.
##
## `view_normal` is the axis the aim direction carries no information about, which
## for a stick-derived aim is the viewing axis. Passing it keeps the aim cone on
## the plane the gesture was made on. This stays a direction and an axis rather
## than a camera, so the octopus still owns no view.
func grab(direction: Vector3, view_normal := Vector3.ZERO) -> bool:
	if _grab.is_active():
		return false
	if not _grab.grab(get_eye(), direction, view_normal):
		return false
	var anchor := _grab.get_position()
	_update_shoulder_aim(anchor)
	_arm.reach(get_shoulder(anchor), anchor)
	return true


## Material coordinate a grab along this aim would take, or -1.0 for nothing,
## following pick()'s own convention.
##
## This is what makes an aim preview honest: it runs the same pick with the same
## cone and the same visibility test grab() runs, so a caller cannot show a target
## the grab would then refuse. It claims nothing and mutates nothing.
func aim_material(direction: Vector3, view_normal := Vector3.ZERO) -> float:
	return OctopusGrab.pick(rope, get_eye(), direction, config.get_aim_cone_cosine(), view_normal)


## World position of a material coordinate from aim_material().
func get_material_position(material_u: float) -> Vector3:
	return rope.get_simulation().get_material_position(material_u)


func release() -> void:
	if not _grab.is_active():
		return
	_grab.release()
	_arm.release(get_shoulder(get_position_in_world()))


func is_holding() -> bool:
	return _grab.is_active()


func get_position_in_world() -> Vector3:
	return _walker.position


func get_up() -> Vector3:
	return _walker.up


func get_contact() -> SurfaceWalker.Contact:
	return _walker.contact


## How far the reaching arm has stretched, 0 to 1.
func get_reach_extension() -> float:
	return _arm.get_extension()


## Whether the hold has finished drawing its material in, after which the arm
## carries it with only the solver's own give.
func is_carrying_taut() -> bool:
	return _grab.is_drawn_in()


## Tip of the reaching arm in world space, which is the held material once the
## arm is fully extended.
func get_reach_tip() -> Vector3:
	return _arm.get_tip()


## Sphere tracing starts here, one body radius clear of the surface, so a
## visibility query cannot immediately report the surface being stood on.
func get_eye() -> Vector3:
	return _walker.position + _walker.up * config.body_radius


## Carried material rides just above the mantle.
func get_carry_point() -> Vector3:
	return _walker.position + _walker.up * config.carry_offset


## Arm root on the mascot model's perimeter, seamlessly continuing from the tentacle base.
func get_shoulder(toward: Vector3) -> Vector3:
	if mascot != null and is_inside_tree() and mascot.is_inside_tree():
		if not _grab.is_active():
			_update_shoulder_aim(toward)
		var local_pt := Vector3(_active_shoulder_local_dir.x * 270.0, 50.0, _active_shoulder_local_dir.y * 270.0)
		return mascot.global_transform * local_pt

	var lateral := SurfaceWalker.tangent(toward - _walker.position, _walker.up)
	if lateral.length_squared() < 1e-4:
		lateral = SurfaceWalker.tangent(-global_transform.basis.z, _walker.up)
	else:
		lateral = lateral.normalized()
	return _walker.position + _walker.up * (config.body_radius * 0.25) + lateral * (config.mantle_radius * 0.90)


func _update_shoulder_aim(toward: Vector3) -> void:
	if mascot == null or not is_inside_tree() or not mascot.is_inside_tree():
		return
	var local_toward := mascot.global_transform.affine_inverse() * toward
	var dir_2d := Vector2(local_toward.x, local_toward.z)
	if dir_2d.length_squared() > 1e-4:
		_active_shoulder_local_dir = dir_2d.normalized()


func _apply_transform(delta: float = 0.0) -> void:
	var target_basis := _walker.get_basis()
	if delta > 0.0 and is_inside_tree() and global_transform.basis != Basis():
		var weight := 1.0 - exp(-delta * 22.0)
		var current_basis := global_transform.basis.orthonormalized()
		var smoothed_basis := current_basis.slerp(target_basis, weight).orthonormalized()
		global_transform = Transform3D(smoothed_basis, _walker.position)
	else:
		global_transform = Transform3D(target_basis, _walker.position)


func _update_skin() -> void:
	if skin == null:
		return
	var curve := _arm.get_curve(_walker.up, config.arm_beads) if _arm.is_active() else PackedVector3Array()
	skin.update_arms(global_transform, curve)
