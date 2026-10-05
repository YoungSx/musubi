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


## Stores both sides of the easing operation so loading does not jump views.
func capture_state() -> Dictionary:
	return {"config_path": config.resource_path, "current": _encode_orbit(_current), "target": _encode_orbit(_target)}


func validate_state(data: Dictionary) -> bool:
	if config == null or data.get("config_path") != config.resource_path:
		return false
	for key in ["current", "target"]:
		var view: Variant = data.get(key)
		if not view is Dictionary:
			return false
		for field in ["yaw", "pitch", "distance"]:
			if not _finite_number(view.get(field)):
				return false
		var focus: Variant = view.get("focus")
		if not focus is Array or focus.size() != 3:
			return false
		for coordinate in focus:
			if not _finite_number(coordinate):
				return false
		var point := Vector3(focus[0], focus[1], focus[2])
		if not point.is_finite() or point.distance_to(config.focus) > config.max_focus_offset + 0.00001:
			return false
		if view.distance < config.min_distance or view.distance > config.max_distance:
			return false
		if view.pitch < deg_to_rad(config.min_pitch_degrees) or view.pitch > deg_to_rad(config.max_pitch_degrees):
			return false
	return true


func restore_state(data: Dictionary) -> bool:
	if not validate_state(data):
		return false
	_decode_orbit(data.current, _current)
	_decode_orbit(data.target, _target)
	_apply_current()
	return true


static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _encode_orbit(view: OrbitState) -> Dictionary:
	return {"yaw": view.yaw, "pitch": view.pitch, "distance": view.distance, "focus": [view.focus.x, view.focus.y, view.focus.z]}


static func _decode_orbit(data: Dictionary, view: OrbitState) -> void:
	view.yaw = data.yaw
	view.pitch = data.pitch
	view.distance = data.distance
	view.focus = Vector3(data.focus[0], data.focus[1], data.focus[2])


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
