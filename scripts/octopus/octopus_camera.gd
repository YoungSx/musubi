class_name OctopusCamera
extends RefCounted
## Third-person follow policy for the octopus.
##
## Maximize reuse of Godot's built-in math and smoothing capabilities:
## - lerp_angle() for shortest-arc angular interpolation without 360-degree wrapping bugs.
## - Exponential decay damping (1.0 - exp(-damping * delta)) for organic, frame-rate independent easing.
## - move_toward() for directional spring-arm distance recovery.
## - Continuous SDF clearance refinement to eliminate discrete distance hopping.
##
## Mario Camera Philosophy:
## - Decouples stick input from aggressive camera spinning (lazy follow on lateral motion).
## - Look-ahead framing leading the player's movement direction.
## - Soft collision avoidance with immediate pull-in on occlusion and smooth spring return.

const MIN_CLEARANCE := 0.08

var _config: OctopusConfig
var _rig: CameraRig
var _collision: RopeCollision
var _yaw := 0.0
var _current_distance := 1.3
var _look_ahead := Vector3.ZERO
var _sustained_heading := Vector2.ZERO
var _sustained_time := 0.0


func configure(config: OctopusConfig, rig: CameraRig, collision: RopeCollision) -> void:
	_config = config
	_rig = rig
	_collision = collision
	_yaw = rig.get_target_yaw() if rig != null else 0.0
	_current_distance = rig.config.distance if rig != null and rig.config != null else 1.3
	_look_ahead = Vector3.ZERO
	_sustained_heading = Vector2.ZERO
	_sustained_time = 0.0


## Frames the body and eases the view behind sustained movement.
func update(delta: float, body: Vector3, up: Vector3, intent: Vector3) -> void:
	if _rig == null or _config == null:
		return
	if delta <= 0.0:
		return

	# 1. Update sustained movement tracking and yaw.
	var flat := Vector2(intent.x, intent.z)
	var speed := flat.length()
	if speed >= _config.follow_turn_threshold and speed > 0.0001:
		var heading := flat / speed
		if _sustained_heading.is_zero_approx() or _sustained_heading.dot(heading) > 0.7:
			_sustained_time += delta
		else:
			_sustained_time = 0.0
		_sustained_heading = heading
	else:
		_sustained_time = 0.0
		_sustained_heading = Vector2.ZERO

	_yaw = _turn(_yaw, intent, _config, delta, _sustained_time)

	# 2. Look-ahead focus calculation using Godot's Vector3.lerp.
	var target_look_ahead := Vector3.ZERO
	if speed >= _config.follow_turn_threshold and "follow_look_ahead" in _config and _config.follow_look_ahead > 0.0:
		target_look_ahead = intent.normalized() * _config.follow_look_ahead
	_look_ahead = _look_ahead.lerp(target_look_ahead, 1.0 - exp(-10.0 * delta))
	var focus := body + up * _config.focus_height + _look_ahead

	# 3. Continuous Spring-Arm distance avoidance and spring return.
	var clear_dist := _find_clear_distance(focus, _yaw)
	if clear_dist < _current_distance:
		# Immediate pull-in to avoid penetrating geometry.
		_current_distance = clear_dist
	else:
		# Smooth spring return outward.
		var recovery_speed: float = _config.follow_distance_recovery_speed if "follow_distance_recovery_speed" in _config else 3.0
		_current_distance = move_toward(_current_distance, clear_dist, recovery_speed * delta)

	_rig.apply_assisted_view(focus, _current_distance, _yaw)


func get_yaw() -> float:
	return _yaw


## Yaw that puts the camera behind a heading using Godot's lerp_angle and exponential decay.
static func _turn(current: float, intent: Vector3, config: OctopusConfig, delta: float, sustained_time := 1.0) -> float:
	if delta <= 0.0:
		return current

	var flat := Vector2(intent.x, intent.z)
	var speed := flat.length()
	if speed < config.follow_turn_threshold or speed <= 0.0001:
		return current

	# CameraRig places the camera along +Z of its orbit basis, so the view sits
	# behind a heading when the basis' +Z opposes it.
	var desired := atan2(-flat.x, -flat.y)

	# Directional alignment: forward movement eases camera immediately, while lateral
	# or reverse movement requires sustained motion to prevent steering feedback loops.
	var forward_dir := Vector2(-sin(current), -cos(current))
	var dot := forward_dir.dot(flat / speed)
	var turn_delay: float = config.follow_turn_delay if "follow_turn_delay" in config else 0.2
	var alignment_weight := 1.0
	if dot <= 0.0:
		if turn_delay > 0.0:
			alignment_weight = smoothstep(turn_delay, turn_delay + 0.3, sustained_time)
		else:
			alignment_weight = 1.0
	elif dot < 0.5:
		var lateral_weight: float = smoothstep(turn_delay, turn_delay + 0.3, sustained_time) if turn_delay > 0.0 else 1.0
		alignment_weight = lerpf(lateral_weight, 1.0, dot * 2.0)

	if alignment_weight <= 0.0001:
		return current

	# Exponential decay easing using Godot's built-in lerp_angle.
	var damping: float = config.follow_turn_damping if "follow_turn_damping" in config else 6.0
	var decay_weight: float = (1.0 - exp(-damping * delta)) * alignment_weight
	var damped := lerp_angle(current, desired, decay_weight)

	# Enforce maximum turn speed rate limit.
	var limit := deg_to_rad(config.follow_turn_speed_degrees) * delta
	var step := wrapf(damped - current, -PI, PI)
	return current + clampf(step, -limit, limit)


## Continuous spring-arm style clearance refinement.
func _find_clear_distance(focus: Vector3, yaw: float) -> float:
	if _rig == null or _rig.config == null:
		return _current_distance
	var distance := _rig.config.distance
	if _collision == null:
		return distance

	var pitch := _rig.get_target_pitch()
	var min_dist := _rig.config.min_distance
	for attempt in 6:
		var origin := _rig.global_transform * CameraRig.compute_camera_transform(yaw, pitch, distance, focus).origin
		var clearance := _collision.get_clearance(origin)
		if clearance >= MIN_CLEARANCE:
			break
		var deficit := MIN_CLEARANCE - clearance
		distance = maxf(min_dist, distance - maxf(deficit, 0.02))
		if distance <= min_dist:
			break
	return clampf(distance, min_dist, _rig.config.distance)


## Backward-compatible helper for clearance check.
func _clear_distance(focus: Vector3, yaw: float) -> float:
	return _find_clear_distance(focus, yaw)
