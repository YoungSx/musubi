class_name RopePassAssist
extends RefCounted
## Input-driven corridor guidance. No input means no progress. Writes only a
## grip target; the regular solver retains authority over all rope positions.
enum State { FREE, APPROACH, PASSING }
var state := State.FREE
var needs_rebase := false
var config := PassAssistConfig.new()
var provider := RopePassCandidates.new()
var _id := Vector3i(-1, -1, -1)
var _pending := Vector3i(-1, -1, -1)
var _dwell := 0.0
var _query_time := 0.0
var _candidates: Array[Dictionary] = []
var _last_raw := Vector3.ZERO
var _last_target := Vector3.ZERO
var _direction := Vector3.ZERO
var _entrance := Vector3.ZERO
var _travel := 0.0
var _lateral := Vector3.ZERO
var _history_direction := Vector3.ZERO


func begin(target: Vector3) -> void:
	state = State.FREE
	_id = Vector3i(-1, -1, -1)
	_pending = _id
	_dwell = 0.0
	_query_time = 0.0
	_candidates.clear()
	_last_raw = target
	_last_target = target
	_history_direction = Vector3.ZERO
	needs_rebase = false
	provider.config = config


func update(raw: Vector3, actual: Vector3, points: PackedVector3Array, radius: float,
		grip_u: float, camera_back: Vector3, collision: RopeCollision, dt: float) -> Vector3:
	needs_rebase = false
	var movement := raw - _last_raw
	_last_raw = raw
	var endpoint := 0 if grip_u < 0.5 else points.size() - 1
	if state != State.FREE:
		var candidate := provider.refresh(points, radius, _id, collision, endpoint)
		if candidate.is_empty():
			return _leave()
		if movement.length_squared() < 1e-12:
			return _last_target
		var normal: Vector3 = candidate.normal
		if normal.dot(_direction) < 0:
			normal = -normal
		if normal.dot(_direction) < 0.95 or candidate.center.distance_to(_entrance + _direction * candidate.half_length) > radius:
			return _leave()
		var projected := _direction - camera_back * _direction.dot(camera_back)
		if projected.length() < config.minimum_projection:
			return _leave()
		var along := movement.dot(projected) / projected.length_squared()
		var lateral_input := movement - projected * along
		# Sideways intent wins over the current path; do not fight the player's hand.
		if lateral_input.length() > absf(along) * 1.5 and lateral_input.length() > radius * 0.25:
			return _leave()
		if _last_target.distance_to(actual) > config.maximum_hand_gap and along > 0:
			return _last_target
		_travel += clampf(along, -movement.length() * 2.0, movement.length() * 2.0)
		_lateral = (_lateral + lateral_input).move_toward(Vector3.ZERO, movement.length() * config.lateral_gain)
		if _lateral.length() > config.approach_distance or _travel < -config.approach_distance:
			return _leave()
		var proposed := _entrance + _direction * _travel + _lateral
		if not RopePassCandidates.contains_clear_point(candidate, proposed, radius) or not provider.corridor_clear(points, radius, candidate.center + _lateral, candidate.normal, candidate.half_length, collision, endpoint):
			return _leave()
		# Assistance must not introduce a jump larger than the expressed movement.
		_last_target += (proposed - _last_target).limit_length(movement.length() * 2.0)
		state = State.PASSING if _travel >= 0 else State.APPROACH
		if _travel > candidate.half_length * 2.0 + radius:
			return _leave()
		return _last_target
	if movement.length_squared() < 1e-12 or (grip_u > 0.02 and grip_u < 0.98):
		_last_target = raw
		return raw
	_history_direction = _history_direction.lerp(movement.normalized(), 0.35).normalized()
	_query_time -= dt
	if _query_time <= 0:
		_candidates = provider.find(points, radius, grip_u, collision)
		_query_time = 0.05
	var best := -INF
	var second := -INF
	var winner := {}
	for cached in _candidates:
		var candidate := provider.refresh(points, radius, cached.id, collision, endpoint)
		if candidate.is_empty():
			continue
		if not RopePassCandidates.contains_clear_point(candidate, actual, radius):
			continue
		var normal: Vector3 = candidate.normal
		var side := 1.0 if (actual - candidate.center).dot(normal) >= 0 else -1.0
		var direction := -normal * side
		var entrance: Vector3 = candidate.center - direction * candidate.half_length
		var projected := direction - camera_back * direction.dot(camera_back)
		var distance := actual.distance_to(entrance)
		if projected.length() < config.minimum_projection or distance > config.approach_distance:
			continue
		var alignment := movement.normalized().dot(projected.normalized())
		if alignment < 0.5:
			continue
		var toward: Vector3 = entrance - actual
		toward -= camera_back * toward.dot(camera_back)
		var approach_alignment := movement.normalized().dot(toward.normalized()) if toward.length() > radius else alignment
		var score := alignment * 0.4 + (1.0 - distance / config.approach_distance) * 0.3 + maxf(approach_alignment, 0.0) * 0.2 + maxf(_history_direction.dot(projected.normalized()), 0.0) * 0.1
		if score > best:
			second = best
			best = score
			winner = candidate.duplicate()
			winner.direction = direction
			winner.entrance = entrance
		else:
			second = maxf(second, score)
	_last_target = raw
	if winner.is_empty() or best < config.score_threshold or best - second < config.score_margin:
		_pending = Vector3i(-1, -1, -1)
		_dwell = 0.0
		return raw
	if winner.id != _pending:
		_pending = winner.id
		_dwell = 0.0
	_dwell += minf(dt, 0.05)
	if _dwell >= config.dwell_seconds:
		_id = winner.id
		_direction = winner.direction
		_entrance = winner.entrance
		_travel = (raw - _entrance).dot(_direction)
		_lateral = raw - _entrance - _direction * _travel
		state = State.APPROACH
	return raw


func _leave() -> Vector3:
	state = State.FREE
	_pending = Vector3i(-1, -1, -1)
	_dwell = 0.0
	_query_time = 0.1
	_candidates.clear()
	needs_rebase = true
	return _last_target


func validate_active(points: PackedVector3Array, radius: float, grip_u: float, collision: RopeCollision) -> bool:
	if state == State.FREE:
		return true
	var endpoint := 0 if grip_u < 0.5 else points.size() - 1
	var candidate := provider.refresh(points, radius, _id, collision, endpoint)
	if candidate.is_empty() or absf(candidate.normal.dot(_direction)) < 0.95 or candidate.center.distance_to(_entrance + _direction * candidate.half_length) > radius:
		_leave()
		return false
	return true
