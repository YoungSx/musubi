class_name OctopusCamera
extends RefCounted
## Third-person follow policy for the octopus.
##
## It observes the body and the move intent and writes only through
## CameraRig.apply_assisted_view(), the same policy-only seam the rope's
## FollowCameraController uses. The rig keeps ownership of pose limits and
## smoothing, so automatic motion can never masquerade as manual input.

const MIN_CLEARANCE := 0.08

var _config: OctopusConfig
var _rig: CameraRig
var _collision: RopeCollision
var _yaw := 0.0


func configure(config: OctopusConfig, rig: CameraRig, collision: RopeCollision) -> void:
	_config = config
	_rig = rig
	_collision = collision
	_yaw = rig.get_target_yaw()


## Frames the body and eases the view behind sustained movement. Small stick
## deflections hold the current yaw so fine positioning does not spin the view.
func update(delta: float, body: Vector3, up: Vector3, intent: Vector3) -> void:
	if _rig == null or _config == null:
		return
	_yaw = _turn(_yaw, intent, _config, delta)
	var focus := body + up * _config.focus_height
	_rig.apply_assisted_view(focus, _clear_distance(focus, _yaw), _yaw)


func get_yaw() -> float:
	return _yaw


## Yaw that puts the camera behind a heading, rate-limited. Returns the current
## yaw unchanged when the stick is near center.
static func _turn(current: float, intent: Vector3, config: OctopusConfig, delta: float) -> float:
	var flat := Vector2(intent.x, intent.z)
	if flat.length() < config.follow_turn_threshold:
		return current
	# CameraRig places the camera along +Z of its orbit basis, so the view sits
	# behind a heading when the basis' +Z opposes it.
	var desired := atan2(-flat.x, -flat.y)
	var limit := deg_to_rad(config.follow_turn_speed_degrees) * delta
	return current + clampf(wrapf(desired - current, -PI, PI), -limit, limit)


## Pulls the view in while its origin sits inside collision geometry. The rig
## clamps the result to its own distance range.
func _clear_distance(focus: Vector3, yaw: float) -> float:
	var distance := _rig.config.distance
	if _collision == null:
		return distance
	for attempt in 4:
		var origin := _rig.global_transform * CameraRig.compute_camera_transform(yaw, _rig.get_target_pitch(), distance, focus).origin
		if _collision.get_clearance(origin) >= MIN_CLEARANCE:
			return distance
		distance *= 0.75
	return distance
