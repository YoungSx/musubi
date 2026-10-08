class_name Octopus
extends Node3D
## A climbing octopus: a surface walker, one elastic arm and one rope grip.
##
## It owns no input and no camera. Callers advance it with a world-space move
## intent and ask it to grab along an aim direction; everything else is the
## composition of SurfaceWalker, OctopusArm and OctopusGrab.

@export var config: OctopusConfig
@export var rope: Rope
@export var skin: OctopusSkin
## Where the octopus starts, in this node's parent space.
@export var spawn_point: Vector3 = Vector3(0.0, 0.0, 0.55)

var _walker := SurfaceWalker.new()
var _arm := OctopusArm.new()
var _grab := OctopusGrab.new()


func _ready() -> void:
	assert(config != null, "Octopus requires an OctopusConfig.")
	assert(rope != null, "Octopus requires a Rope to grab.")
	_arm.configure(config)
	_grab.configure(config, rope)
	if skin != null:
		skin.configure(config)


## Call after the rope's collision geometry is installed.
func attach_to_world() -> void:
	_walker.configure(config, rope.get_collision())
	_walker.place(spawn_point)
	_apply_transform()
	_update_skin()


func advance(delta: float, intent: Vector3) -> void:
	_walker.step(delta, intent)
	_apply_transform()
	if _grab.is_active():
		_grab.carry(get_carry_point(), delta)
		_arm.hold(get_shoulder(_grab.get_position()), _grab.get_position())
	_arm.step(delta)
	_update_skin()


## Grabs rope along an aim direction. A zero direction takes the nearest visible
## material, which is the conventional fallback for an aimless tap.
func grab(direction: Vector3) -> bool:
	if _grab.is_active():
		return false
	if not _grab.grab(get_eye(), direction):
		return false
	var anchor := _grab.get_position()
	_arm.reach(get_shoulder(anchor), anchor)
	return true


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


## Arm root on the mantle, biased toward whatever the arm is reaching for.
func get_shoulder(toward: Vector3) -> Vector3:
	var lateral := SurfaceWalker.tangent(toward - _walker.position, _walker.up)
	return _walker.position + _walker.up * (config.mantle_radius * 0.3) + lateral * (config.mantle_radius * 0.6)


func _apply_transform() -> void:
	global_transform = Transform3D(_walker.get_basis(), _walker.position)


func _update_skin() -> void:
	if skin == null:
		return
	var curve := _arm.get_curve(_walker.up, config.arm_beads) if _arm.is_active() else PackedVector3Array()
	skin.update_arms(global_transform, curve)
