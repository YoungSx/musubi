class_name GroundPassIntent
extends RefCounted
## Time-dependent hypotheses for a single left-drag. Temporary support belongs
## to the assist layer, never to another player-controlled hand.
enum Phase { FREE, APPROACH, PREPARE, PASS, PULL, UNWIND }
var phase := Phase.FREE
var confidence := 0.0
var support_u := -1.0
var support_origin := Vector3.ZERO
var support_strength := 0.0
var prefer_under := false
var confirmed_passes := 0
var topology := GroundLoopTopology.new()
var _candidate := {}
var _last_raw := Vector2.ZERO
var _direction := Vector2.ZERO
var _speed := 0.0
var _dwell := 0.0
var _distance_moved := 0.0
var _query_time := 0.0
var _loops: Array[Dictionary] = []
var _recent_pass := {}
var _previous_actual := Vector3.ZERO
var _last_output := Vector3.ZERO


func begin(point: Vector3) -> void:
	phase = Phase.FREE
	confidence = 0
	support_u = -1
	support_strength = 0
	prefer_under = false
	_candidate = {}
	_last_raw = Vector2(point.x, point.z)
	_direction = Vector2.ZERO
	_speed = 0
	_dwell = 0
	_distance_moved = 0
	_query_time = 0
	_loops.clear()
	_previous_actual = point
	_last_output = point


func clear() -> void:
	begin(Vector3.ZERO)
	_recent_pass.clear()
	confirmed_passes = 0


func rebase(point: Vector3) -> void:
	_last_raw = Vector2(point.x, point.z)
	_last_output = point


func update(raw: Vector3, actual: Vector3, points: PackedVector3Array, grip_u: float,
		radius: float, floor_height: float, collision: RopeCollision, dt: float) -> Vector3:
	_last_output = _update(raw, actual, points, grip_u, radius, floor_height, collision, dt)
	return _last_output


func _update(raw: Vector3, actual: Vector3, points: PackedVector3Array, grip_u: float,
		radius: float, floor_height: float, collision: RopeCollision, dt: float) -> Vector3:
	var cursor := Vector2(raw.x, raw.z)
	var movement := cursor - _last_raw
	_last_raw = cursor
	if movement.length_squared() < 1e-12:
		return _last_output
	prefer_under = false
	var speed := movement.length() / maxf(dt, 0.001)
	var continuity := minf(speed, _speed) / maxf(maxf(speed, _speed), 0.001) if _speed > 0 else 1.0
	_speed = lerpf(_speed, speed, 0.3)
	_direction = _direction.lerp(movement.normalized(), 0.4).normalized()
	var tip := Vector2(actual.x, actual.z)
	observe_actual(actual, points, radius)
	if support_u >= 0:
		var coordinate := support_u * (points.size() - 1)
		var index := mini(floori(coordinate), points.size() - 2)
		var supported := points[index].lerp(points[index + 1], coordinate - index)
		var entry: Vector2 = _candidate.entry
		var normal: Vector2 = _candidate.normal
		var side := (tip - entry).dot(normal)
		if (movement.normalized().dot(normal) < -0.5 and side < -radius * 3) or tip.distance_to(entry) > 0.22:
			_drop()
			return raw
		if phase == Phase.PULL and side > 0.10:
			_drop()
			return raw
		prefer_under = true
		support_strength = minf(1.0, support_strength + dt * 5.0)
		if phase != Phase.PULL and phase != Phase.UNWIND:
			phase = Phase.PASS if supported.y > floor_height + radius * 3.5 else Phase.PREPARE
		# Do not push through a still-closed gap. The target only advances on input.
		var raw_side := (cursor - entry).dot(normal)
		if supported.y < floor_height + radius * 3.5 and raw_side > -radius * 2:
			cursor -= normal * (raw_side + radius * 2)
		return Vector3(cursor.x, raw.y, cursor.y)
	if not _recent_pass.is_empty():
		var entry: Vector2 = _recent_pass.entry
		var normal: Vector2 = _recent_pass.normal
		if tip.distance_to(entry) < 0.18 and (tip - entry).dot(normal) > 0 and _direction.dot(normal) < -0.7:
			_activate(_recent_pass, actual)
			phase = Phase.UNWIND
			return raw
	_query_time -= dt
	if _query_time <= 0:
		_loops = topology.observe(points, radius, floor_height)
		_query_time = 0.08
	var candidates := topology.entries(_loops, points, actual, _direction, grip_u, radius, collision)
	var winner := {}
	var best := -INF
	var second := -INF
	for candidate in candidates:
		var score: float = candidate.alignment * 0.45 + continuity * 0.2 + (1.0 - candidate.distance / 0.18) * 0.25 + 0.1
		if score > best:
			second = best
			best = score
			winner = candidate
		else:
			second = maxf(second, score)
	if winner.is_empty() or best < 0.7 or best - second < 0.1:
		_dwell = maxf(0.0, _dwell - dt * 2)
		confidence = _dwell / 0.12
		phase = Phase.FREE
		return raw
	if _candidate.is_empty() or winner.loop.id != _candidate.loop.id or absf(float(winner.u) - float(_candidate.u)) * (points.size() - 1) > 3:
		_dwell = 0
		_distance_moved = 0
	_candidate = winner
	_dwell += minf(dt, 0.04)
	_distance_moved += movement.length()
	confidence = clampf(_dwell / 0.12, 0, 1)
	phase = Phase.APPROACH
	if confidence >= 1.0 and _distance_moved > radius:
		_activate(winner, actual)
	return raw


func _activate(candidate: Dictionary, _actual: Vector3) -> void:
	_candidate = candidate.duplicate(true)
	support_u = candidate.u
	support_origin = candidate.world
	support_strength = 0.2
	prefer_under = true
	phase = Phase.PREPARE


func _drop() -> void:
	support_u = -1
	support_strength = 0
	prefer_under = false
	_candidate = {}
	phase = Phase.FREE
	_dwell = 0
	confidence = 0


func abort() -> void:
	_drop()


func observe_actual(actual: Vector3, points: PackedVector3Array, radius: float) -> void:
	if support_u >= 0 and not _candidate.is_empty():
		var coordinate := support_u * (points.size() - 1)
		var index := mini(floori(coordinate), points.size() - 2)
		var a := Vector2(points[index].x, points[index].z)
		var b := Vector2(points[index + 1].x, points[index + 1].z)
		var before := Vector2(_previous_actual.x, _previous_actual.z)
		var after := Vector2(actual.x, actual.z)
		var hit: Variant = Geometry2D.segment_intersects_segment(before, after, a, b)
		if hit != null:
			var p: Vector2 = hit
			var t := clampf((p - a).dot(b - a) / maxf(a.distance_squared_to(b), 1e-10), 0, 1)
			var edge_y := lerpf(points[index].y, points[index + 1].y, t)
			var height_clear := maxf(actual.y, _previous_actual.y) + radius * 1.8 < edge_y
			var forward := (after - before).dot(_candidate.normal)
			if height_clear and forward > 0 and not _candidate.get("passed", false) and Geometry2D.is_point_in_polygon(after + (_candidate.normal as Vector2) * radius * 0.5, _candidate.loop.polygon):
				_candidate.passed = true
				phase = Phase.PULL
				confirmed_passes += 1
				_recent_pass = _candidate.duplicate(true)
			elif height_clear and forward < 0 and phase == Phase.UNWIND:
				_recent_pass.clear()
				_drop()
	_previous_actual = actual


func validate_active(points: PackedVector3Array, radius: float) -> bool:
	if support_u < 0:
		return true
	var loop: Dictionary = _candidate.loop
	var i := floori(loop.first)
	var j := floori(loop.last)
	var closure_exists := false
	for a in range(maxi(0, i - 1), mini(points.size() - 1, i + 2)):
		for b in range(maxi(a + 3, j - 1), mini(points.size() - 1, j + 2)):
			var hit: Variant = Geometry2D.segment_intersects_segment(Vector2(points[a].x, points[a].z), Vector2(points[a + 1].x, points[a + 1].z), Vector2(points[b].x, points[b].z), Vector2(points[b + 1].x, points[b + 1].z))
			if hit != null: closure_exists = true
	var coordinate := support_u * (points.size() - 1)
	var index := mini(floori(coordinate), points.size() - 2)
	var actual := points[index].lerp(points[index + 1], coordinate - index)
	if not closure_exists or Vector2(actual.x, actual.z).distance_to(_candidate.entry) > radius * 5:
		_drop()
		return false
	return true
