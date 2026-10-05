class_name CameraRig
extends Node3D
## Orbit camera around a focus point.
##
## Input-agnostic: callers express intent through orbit(), pan() and zoom() in
## screen-normalized units (1.0 = one screen height). The rig eases its current
## view toward the requested target view every frame.

@export var config: CameraConfig

var _target := OrbitState.new()
var _current := OrbitState.new()

@onready var _camera: Camera3D = $Camera3D


static func orbit_basis(yaw: float, pitch: float) -> Basis:
	return Basis.from_euler(Vector3(-pitch, yaw, 0.0))


## Camera transform (in rig space) for an orbit view. The camera sits on the
## basis' +Z axis and therefore looks along -Z, straight at the focus.
static func compute_camera_transform(yaw: float, pitch: float, distance: float, focus: Vector3) -> Transform3D:
	var view_basis := orbit_basis(yaw, pitch)
	return Transform3D(view_basis, focus + view_basis.z * distance)


func _ready() -> void:
	assert(config != null, "CameraRig requires a CameraConfig.")
	_camera.fov = config.fov
	reset_view()


func _process(delta: float) -> void:
	_current.approach(_target, 1.0 - exp(-config.smoothing * delta))
	_apply_current()


func orbit(screen_delta: Vector2) -> void:
	var radians_per_screen := deg_to_rad(config.orbit_degrees_per_screen)
	_target.yaw -= screen_delta.x * radians_per_screen
	_target.pitch = clampf(
		_target.pitch + screen_delta.y * radians_per_screen,
		deg_to_rad(config.min_pitch_degrees),
		deg_to_rad(config.max_pitch_degrees),
	)


## factor > 1 moves closer (pinch out), factor < 1 moves away.
func zoom(factor: float) -> void:
	if factor <= 0.0:
		return
	_target.distance = clampf(_target.distance / factor, config.min_distance, config.max_distance)


func pan(screen_delta: Vector2) -> void:
	var view_basis := orbit_basis(_target.yaw, _target.pitch)
	var world_per_screen := config.pan_per_screen * _target.distance
	var offset := (view_basis.y * screen_delta.y - view_basis.x * screen_delta.x) * world_per_screen
	var drift := (_target.focus + offset - config.focus).limit_length(config.max_focus_offset)
	_target.focus = config.focus + drift


## Snaps immediately to the configured default view.
func reset_view() -> void:
	_target.yaw = deg_to_rad(config.yaw_degrees)
	_target.pitch = deg_to_rad(config.pitch_degrees)
	_target.distance = config.distance
	_target.focus = config.focus
	_current.copy_from(_target)
	_apply_current()


func get_camera() -> Camera3D:
	return _camera


func get_target_yaw() -> float:
	return _target.yaw


func get_target_pitch() -> float:
	return _target.pitch


func get_target_distance() -> float:
	return _target.distance


func get_target_focus() -> Vector3:
	return _target.focus


func _apply_current() -> void:
	_camera.transform = compute_camera_transform(_current.yaw, _current.pitch, _current.distance, _current.focus)


class OrbitState:
	var yaw := 0.0
	var pitch := 0.0
	var distance := 1.0
	var focus := Vector3.ZERO

	func copy_from(other: OrbitState) -> void:
		yaw = other.yaw
		pitch = other.pitch
		distance = other.distance
		focus = other.focus

	func approach(other: OrbitState, weight: float) -> void:
		yaw = lerpf(yaw, other.yaw, weight)
		pitch = lerpf(pitch, other.pitch, weight)
		distance = lerpf(distance, other.distance, weight)
		focus = focus.lerp(other.focus, weight)
