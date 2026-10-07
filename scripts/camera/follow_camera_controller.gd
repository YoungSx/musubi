class_name FollowCameraController
extends RefCounted
## Read-only observer of grip intent/geometry. Writes camera intent only.
## Predicts framing against the rig's requested pose, avoiding feedback from
## its render smoothing. Actual rope velocity never creates movement intent.

var _previous_targets: Dictionary[int, Vector3] = {}
var _intent_age := INF
var _manual_wait := false
var _manual_remaining := 0.0
var _heading := Vector3.ZERO
var _travel := 0.0
var _occlusion_time := 0.0
var _visibility_timer := 0.0
var _hidden := 0
var _avoid_yaw := NAN


func reset() -> void:
	_previous_targets.clear()
	_intent_age = INF
	_manual_wait = false
	_manual_remaining = 0.0
	_heading = Vector3.ZERO
	_travel = 0.0
	_clear_occlusion()


func manual_override(cooldown := 0.35) -> void:
	_manual_wait = true
	_manual_remaining = maxf(_manual_remaining, cooldown)
	_intent_age = INF
	_heading = Vector3.ZERO
	_travel = 0.0
	_clear_occlusion()


func update(delta: float, rig: CameraRig, grips: Dictionary[int, Vector3],
		targets: Dictionary[int, Vector3], context: PackedVector3Array,
		collision: RopeCollision, manual_active := false) -> void:
	if delta <= 0.0: return
	if rig.mode != CameraRig.Mode.ASSISTED or grips.is_empty():
		reset()
		return
	var config := rig.config
	var membership_changed := targets.size() != _previous_targets.size()
	var movement := Vector3.ZERO
	var activity := 0.0
	for id: int in targets:
		if not _previous_targets.has(id):
			membership_changed = true
		else:
			var change := targets[id] - _previous_targets[id]
			movement += change
			activity += change.length()
	_previous_targets = targets.duplicate()
	if membership_changed:
		_intent_age = INF
		_heading = Vector3.ZERO
		_travel = 0.0
		_clear_occlusion()
		return
	if manual_active:
		manual_override()
		_manual_remaining = config.follow_manual_cooldown
		return
	_manual_remaining = maxf(0.0, _manual_remaining - delta)
	if _manual_wait:
		if _manual_remaining > 0.0 or activity < 0.001: return
		_manual_wait = false
	_intent_age = 0.0 if activity > 0.0005 else _intent_age + delta
	if _intent_age > config.follow_settle_time:
		_clear_occlusion()
		return
	movement /= maxf(float(targets.size()), 1.0)
	movement.y = 0.0
	if movement.length() > 0.0005:
		_travel += movement.length()
		_heading = movement.normalized() if _heading.is_zero_approx() else _heading.lerp(movement.normalized(), 1.0 - exp(-delta * 5.0))
	var subjects := context.duplicate()
	for point: Vector3 in grips.values(): subjects.append(point)
	var view := rig.get_target_transform()
	var bounds := _bounds(subjects, view, rig)
	var safe := config.follow_safe_region
	var distance := rig.get_target_distance()
	var focus := rig.get_target_focus()
	var yaw := rig.get_target_yaw()
	var overflow := not safe.encloses(bounds)
	var fit := maxf(bounds.size.x / safe.size.x, bounds.size.y / safe.size.y)
	if fit > 1.0:
		distance = move_toward(distance, minf(config.max_distance, distance * fit * 1.04), config.follow_distance_speed * delta)
	if overflow:
		var center := bounds.get_center()
		var margin := bounds.size.min(safe.size) * 0.5
		var correction := center - center.clamp(safe.position + margin, safe.end - margin)
		var viewport := rig.get_viewport().get_visible_rect().size
		var height := 2.0 * rig.get_target_distance() * tan(deg_to_rad(rig.get_camera().fov) * 0.5)
		var world_shift := view.basis.x * correction.x * height * viewport.x / maxf(viewport.y, 1.0) - view.basis.y * correction.y * height
		focus += (rig.global_basis.inverse() * world_shift).limit_length(config.follow_focus_speed * delta)
	_visibility_timer -= delta
	var visibility_due := _visibility_timer <= 0.0
	if visibility_due:
		_visibility_timer = 0.10
		_hidden = _hidden_count(view.origin, grips, collision)
	_occlusion_time = _occlusion_time + delta if _hidden > 0 else 0.0
	if _hidden == 0: _avoid_yaw = NAN
	if _occlusion_time >= config.follow_occlusion_delay:
		if is_nan(_avoid_yaw) or (visibility_due and absf(wrapf(_avoid_yaw - yaw, -PI, PI)) < 0.02):
			_avoid_yaw = _choose_visible_yaw(rig, grips, collision)
		yaw += clampf(wrapf(_avoid_yaw - yaw, -PI, PI), -deg_to_rad(config.follow_turn_speed_degrees) * delta, deg_to_rad(config.follow_turn_speed_degrees) * delta)
	elif overflow and _travel > 0.08 and _heading.length() > 0.5:
		# A trailing view is a gentle preference, subordinate to framing/visibility.
		var behind := atan2(-_heading.x, -_heading.z)
		yaw += clampf(wrapf(behind - yaw, -PI, PI), -deg_to_rad(config.follow_turn_speed_degrees * 0.4) * delta, deg_to_rad(config.follow_turn_speed_degrees * 0.4) * delta)
	focus = config.focus + (focus - config.focus).limit_length(config.max_focus_offset)
	var next_view := rig.global_transform * CameraRig.compute_camera_transform(yaw, rig.get_target_pitch(), distance, focus)
	if collision == null or collision.get_clearance(next_view.origin) >= 0.08:
		rig.apply_assisted_view(focus, distance, yaw)


func _clear_occlusion() -> void:
	_occlusion_time = 0.0
	_visibility_timer = 0.0
	_hidden = 0
	_avoid_yaw = NAN


func _hidden_count(origin: Vector3, grips: Dictionary[int, Vector3], collision: RopeCollision) -> int:
	var count := 0
	for point: Vector3 in grips.values():
		if not RopeVisibility.is_visible(origin, point, collision): count += 1
	return count


func _choose_visible_yaw(rig: CameraRig, grips: Dictionary[int, Vector3], collision: RopeCollision) -> float:
	var current := rig.get_target_yaw()
	var result := current
	var best := float(_hidden) * 10.0
	for degrees in [25.0, -25.0, 50.0, -50.0, 90.0, -90.0, 135.0, -135.0]:
		var candidate := current + deg_to_rad(degrees)
		var pose := rig.global_transform * CameraRig.compute_camera_transform(candidate, rig.get_target_pitch(), rig.get_target_distance(), rig.get_target_focus())
		if collision != null and collision.get_clearance(pose.origin) < 0.08: continue
		var score := float(_hidden_count(pose.origin, grips, collision)) * 10.0 + absf(degrees) / 180.0
		if score < best:
			best = score
			result = candidate
	return result


func _bounds(points: PackedVector3Array, view: Transform3D, rig: CameraRig) -> Rect2:
	var viewport := rig.get_viewport().get_visible_rect().size
	var aspect := viewport.x / maxf(viewport.y, 1.0)
	var slope := tan(deg_to_rad(rig.get_camera().fov) * 0.5)
	var bounds := Rect2()
	for i in points.size():
		var local := view.affine_inverse() * points[i]
		var half_height := maxf(-local.z, 0.05) * slope
		var point := Vector2(0.5 + local.x / (2.0 * half_height * aspect), 0.5 - local.y / (2.0 * half_height))
		bounds = Rect2(point, Vector2.ZERO) if i == 0 else bounds.expand(point)
	return bounds
