class_name RopeSimulation
extends RefCounted
## Particle rope: Verlet integration + XPBD distance constraints.
##
##   integrate (gravity, damping) -> reset multipliers -> solve constraints xN
##
## Pure data and math: no nodes, rendering or input. Positions are in world
## space. A particle with zero inverse mass is pinned: the solver never moves
## it, only pin() does. User grabs are separate soft positional constraints,
## keeping particles movable so length and contact constraints can respond.

var _config: RopeConfig
var _positions := PackedVector3Array()
var _previous := PackedVector3Array()
var _inverse_mass := PackedFloat32Array()
var _lambdas := PackedFloat32Array()
var _last_substep := 0.0
var _collision: RopeCollision
var _self_collision := RopeSelfCollision.new()
var _drag_index := -1
var _drag_fraction := 0.0
var _release_u := -1.0
var _release_remaining := 0.0
var _drag_target := Vector3.ZERO
var _drag_lambda := Vector3.ZERO
var _support_index := -1
var _support_fraction := 0.0
var _support_target := Vector3.ZERO
var _support_lambda := Vector3.ZERO
var _transport_targets := PackedVector3Array()
var _transport_lambdas := PackedVector3Array()
var _transport_grip_id := -1

## Mouse/legacy grip uses -1; touch grips retain their physical pointer IDs.
class TouchGrip:
	var index: int
	var fraction: float
	var target: Vector3
	var multiplier := Vector3.ZERO

var _touch_grips: Dictionary[int, TouchGrip] = {}


func _init(config: RopeConfig, initial_positions: PackedVector3Array) -> void:
	assert(config != null, "RopeSimulation requires a RopeConfig.")
	assert(initial_positions.size() == config.segment_count + 1, "Expected segment_count + 1 points.")
	_config = config
	_positions = initial_positions.duplicate()
	_previous = initial_positions.duplicate()
	_inverse_mass.resize(_positions.size())
	_inverse_mass.fill(1.0)
	_lambdas.resize(_positions.size() - 1)


## Advances by dt using RopeConfig.substeps small steps. Substepping converges
## far better than extra iterations on long chains (Macklin et al. 2019,
## "Small Steps in Physics Simulation").
func step(dt: float) -> void:
	if dt <= 0.0:
		return
	var h := dt / float(_config.substeps)
	var alpha := _config.stretch_compliance / (h * h)
	var sweep := 0
	for substep in _config.substeps:
		var start := _positions.duplicate() if _config.self_collision_enabled else PackedVector3Array()
		_integrate(h)
		_release_remaining = maxf(0.0, _release_remaining - h)
		_lambdas.fill(0.0)
		_drag_lambda = Vector3.ZERO
		for grip: TouchGrip in _touch_grips.values():
			grip.multiplier = Vector3.ZERO
		_support_lambda = Vector3.ZERO
		_transport_lambdas.fill(Vector3.ZERO)
		for iteration in _config.solver_iterations:
			_solve_drag(h)
			# Alternating sweep direction avoids a bias toward one end.
			for distance_pass in _config.distance_sweeps:
				_solve_distances(alpha, (sweep+distance_pass) % 2 == 1)
			if _config.self_collision_enabled:
				_self_collision.solve(_positions, _previous, _inverse_mass, start, _config.radius, _config.get_rest_length(), _config.self_friction)
			if _collision != null:
				for contact_pass in _config.collision_iterations:
					_collision.solve(_positions, _previous, _inverse_mass, _config.radius, _config.friction)
			sweep += 1
	_last_substep = h


func set_collision(collision: RopeCollision) -> void:
	_collision = collision


func is_self_collision_enabled() -> bool:
	return _config.self_collision_enabled


## Contacts resolved in the most recent constraint pass (not unique contacts).
func get_self_contact_count() -> int:
	return _self_collision.contacts if _config.self_collision_enabled else 0


func capture_state() -> Dictionary:
	var data := RopeState.encode(_config, _positions, _previous, _inverse_mass,
		_last_substep, _drag_index, _drag_target, _drag_fraction, _release_u, _release_remaining)
	data.support = {"u": get_support_u(), "target": [_support_target.x, _support_target.y, _support_target.z]} if _support_index >= 0 else {}
	data.transport = []
	data.transport_grip_id = _transport_grip_id
	for point in _transport_targets: data.transport.append([point.x,point.y,point.z])
	data.touch_grips = []
	for id: int in _touch_grips:
		var grip := _touch_grips[id]
		data.touch_grips.append({"id": id, "u": get_grip_u(id), "target": [grip.target.x, grip.target.y, grip.target.z]})
	return data


static func restore_state(data: Dictionary) -> RopeSimulation:
	var state := RopeState.decode(data)
	if state.is_empty():
		return null
	var simulation := RopeSimulation.new(state.config, state.positions)
	simulation._previous = state.previous
	simulation._inverse_mass = state.inverse_mass
	simulation._last_substep = state.last_substep
	simulation._drag_index = state.drag_index
	simulation._drag_target = state.drag_target
	simulation._drag_fraction = state.drag_fraction
	simulation._release_u = state.release_u
	simulation._release_remaining = state.release_remaining
	if not state.support.is_empty():
		simulation.begin_support(state.support.u)
		simulation._support_target = state.support.target
	for grip: Dictionary in state.touch_grips:
		simulation.begin_grip(grip.u, grip.id)
		simulation._touch_grips[grip.id].target = grip.target
	simulation.set_transport_targets(state.transport, state.transport_grip_id)
	return simulation


func begin_drag(index: int) -> bool:
	if index < 0 or index >= _positions.size() or is_pinned(index):
		return false
	return begin_grip(float(index) / float(_positions.size() - 1))


func begin_grip(material_u: float, grip_id := -1) -> bool:
	if grip_id < -1 or grip_id > 2147483647 or (grip_id >= 0 and (_touch_grips.has(grip_id) or _touch_grips.size() >= 32)):
		return false
	if not is_finite(material_u) or material_u < 0.0 or material_u > 1.0:
		return false
	var coordinate := material_u * float(_positions.size() - 1)
	if absf(coordinate - roundf(coordinate)) < 1e-8:
		coordinate = roundf(coordinate)
	var index := floori(coordinate)
	var fraction := coordinate - index
	var other := mini(index + 1, _positions.size() - 1)
	if _inverse_mass[index] * (1.0 - fraction) + _inverse_mass[other] * fraction <= 0.0:
		return false
	if grip_id >= 0:
		var grip := TouchGrip.new()
		grip.index = index
		grip.fraction = fraction
		grip.target = _positions[index].lerp(_positions[other], fraction)
		_touch_grips[grip_id] = grip
		_release_remaining = 0.0
		return true
	_drag_index = index
	_drag_fraction = fraction
	_drag_target = get_grip_position()
	_drag_lambda = Vector3.ZERO
	_release_remaining = 0.0
	return true


func get_grip_position(grip_id := -1) -> Vector3:
	if grip_id >= 0:
		if not _touch_grips.has(grip_id): return Vector3.ZERO
		var grip := _touch_grips[grip_id]
		return _positions[grip.index].lerp(_positions[mini(grip.index + 1, _positions.size() - 1)], grip.fraction)
	if _drag_index < 0:
		return Vector3.ZERO
	return _positions[_drag_index].lerp(_positions[mini(_drag_index + 1, _positions.size() - 1)], _drag_fraction)


func get_grip_u(grip_id := -1) -> float:
	if grip_id >= 0:
		if not _touch_grips.has(grip_id): return -1.0
		var grip := _touch_grips[grip_id]
		return (float(grip.index) + grip.fraction) / float(_positions.size() - 1)
	return (float(_drag_index) + _drag_fraction) / float(_positions.size() - 1) if _drag_index >= 0 else -1.0


func get_grip_ids() -> Array[int]:
	var ids: Array[int] = []
	if _drag_index >= 0: ids.append(-1)
	ids.append_array(_touch_grips.keys())
	return ids


func get_grip_count() -> int:
	return _touch_grips.size() + (1 if _drag_index >= 0 else 0)


func begin_support(u: float) -> bool:
	if _support_index >= 0 or not is_finite(u) or u < 0 or u > 1:
		return false
	for id in get_grip_ids():
		if absf(u - get_grip_u(id)) * (_positions.size() - 1) < 2.0:
			return false
	var coordinate := u * (_positions.size() - 1)
	if absf(coordinate - roundf(coordinate)) < 1e-8:
		coordinate = roundf(coordinate)
	var index := floori(coordinate)
	var fraction := coordinate - index
	if _inverse_mass[index] * (1.0 - fraction) + _inverse_mass[mini(index + 1, _positions.size() - 1)] * fraction <= 0:
		return false
	_support_index = index
	_support_fraction = fraction
	_support_target = get_support_position()
	return true


func get_support_u() -> float:
	return (float(_support_index) + _support_fraction) / float(_positions.size() - 1) if _support_index >= 0 else -1.0


func get_support_position() -> Vector3:
	return _positions[_support_index].lerp(_positions[mini(_support_index + 1, _positions.size() - 1)], _support_fraction) if _support_index >= 0 else Vector3.ZERO


func update_support_target(target: Vector3) -> void:
	if _support_index >= 0 and target.is_finite():
		_support_target = target


func release_support() -> void:
	if _support_index >= 0:
		_stabilize_release(_support_index, _support_fraction)
	_support_index = -1
	_support_fraction = 0.0
	_support_lambda = Vector3.ZERO


func update_drag_target(target: Vector3, grip_id := -1) -> void:
	var index := get_drag_index(grip_id)
	if index < 0 or not target.is_finite():
		return
	var fraction := _drag_fraction if grip_id < 0 else _touch_grips[grip_id].fraction
	# Intersect reachable spheres around attachments; extra path around the
	# mannequin is still handled by the soft constraint rather than stretching.
	for pass_index in 8:
		for i in _positions.size():
			if is_pinned(i):
				var reach := absf(float(i - index) - fraction) * _config.get_rest_length()
				target = _positions[i] + (target - _positions[i]).limit_length(reach)
	if grip_id < 0:
		_drag_target = target
	else:
		_touch_grips[grip_id].target = target


func end_drag(grip_id := -1) -> void:
	if _transport_grip_id == grip_id:
		set_transport_targets(PackedVector3Array())
	if grip_id >= 0:
		_touch_grips.erase(grip_id)
		return
	_drag_index = -1
	_drag_fraction = 0.0
	_drag_lambda = Vector3.ZERO


func get_drag_index(grip_id := -1) -> int:
	if grip_id >= 0:
		return _touch_grips[grip_id].index if _touch_grips.has(grip_id) else -1
	return _drag_index


func get_drag_target(grip_id := -1) -> Vector3:
	if grip_id >= 0:
		return _touch_grips[grip_id].target if _touch_grips.has(grip_id) else Vector3.ZERO
	return _drag_target


func stop_motion() -> void:
	_previous = _positions.duplicate()
	_last_substep = 0.0
	_release_remaining = 0.0


## Natural release: only the gripped neighborhood gets a brief damping pulse.
## Distant particles keep moving; collision and length constraints remain active.
func release_grip(grip_id := -1) -> void:
	if grip_id >= 0:
		if _touch_grips.has(grip_id):
			var grip := _touch_grips[grip_id]
			_stabilize_release(grip.index, grip.fraction)
			end_drag(grip_id)
		return
	if _drag_index < 0:
		return
	_stabilize_release(_drag_index, _drag_fraction)
	end_drag()


func _stabilize_release(index: int, fraction: float) -> void:
	_release_u = (float(index) + fraction) / float(_positions.size() - 1)
	_release_remaining = 0.12
	for i in range(maxi(0, index - 3), mini(_positions.size(), index + 5)):
		if _inverse_mass[i] > 0.0 and _last_substep > 0.0:
			_previous[i] = _positions[i] - (_positions[i] - _previous[i]).limit_length(0.8 * _last_substep)


func _solve_drag(dt: float) -> void:
	for i in _transport_targets.size():
		_transport_lambdas[i] = _solve_grip(i,0,_transport_targets[i],_transport_lambdas[i],dt)
	if _support_index >= 0:
		_support_lambda = _solve_grip(_support_index, _support_fraction, _support_target, _support_lambda, dt)
	if _drag_index >= 0:
		_drag_lambda = _solve_grip(_drag_index, _drag_fraction, _drag_target, _drag_lambda, dt)
	for grip: TouchGrip in _touch_grips.values():
		grip.multiplier = _solve_grip(grip.index, grip.fraction, grip.target, grip.multiplier, dt)

func set_transport_targets(targets: PackedVector3Array, grip_id := -1) -> bool:
	if not targets.is_empty() and (targets.size() != _positions.size() or get_drag_index(grip_id) < 0): return false
	for target in targets:
		if not target.is_finite(): return false
	_transport_targets = targets.duplicate()
	_transport_grip_id = grip_id if not targets.is_empty() else -1
	_transport_lambdas.resize(targets.size())
	return true

func has_transport_targets() -> bool:
	return not _transport_targets.is_empty()


func _solve_grip(index: int, fraction: float, target: Vector3, multiplier: Vector3, dt: float) -> Vector3:
	var alpha := _config.drag_compliance / (dt * dt)
	var other := mini(index + 1, _positions.size() - 1)
	var a := 1.0 - fraction
	var b := fraction
	var weight := a * a * _inverse_mass[index] + b * b * _inverse_mass[other]
	if weight <= 0.0:
		return multiplier
	var current := _positions[index].lerp(_positions[other], fraction)
	var correction := (target - current - multiplier * alpha) / (weight + alpha)
	correction = correction.limit_length(_config.drag_speed * dt / weight)
	_positions[index] += correction * a * _inverse_mass[index]
	_positions[other] += correction * b * _inverse_mass[other]
	return multiplier + correction


## Pins a particle at a world position. Moving a pinned particle is how
## kinematic attachments (anchors, fingers) drive the rope.
func pin(index: int, position: Vector3) -> void:
	_inverse_mass[index] = 0.0
	_positions[index] = position
	_previous[index] = position


func unpin(index: int) -> void:
	_inverse_mass[index] = 1.0


func is_pinned(index: int) -> bool:
	return _inverse_mass[index] == 0.0


func get_point_count() -> int:
	return _positions.size()


func get_point(index: int) -> Vector3:
	return _positions[index]


## World position of a material coordinate, the same 0..1 parameter begin_grip
## takes. Lets a caller holding a material coordinate ask where that material is
## without claiming a grip for it.
func get_material_position(material_u: float) -> Vector3:
	if not is_finite(material_u) or material_u < 0.0 or material_u > 1.0:
		return Vector3.ZERO
	var coordinate := material_u * float(_positions.size() - 1)
	if absf(coordinate - roundf(coordinate)) < 1e-8:
		coordinate = roundf(coordinate)
	var index := floori(coordinate)
	return _positions[index].lerp(_positions[mini(index + 1, _positions.size() - 1)], coordinate - index)


## Copy-on-write snapshot. Do not keep it across steps, or every step pays
## for a copy.
func get_positions() -> PackedVector3Array:
	return _positions


func get_length() -> float:
	return RopeLayout.polyline_length(_positions)


func get_max_segment_stretch() -> float:
	var rest := _config.get_rest_length()
	var worst := 0.0
	for i in _positions.size() - 1:
		worst = maxf(worst, absf(_positions[i].distance_to(_positions[i + 1]) - rest) / rest)
	return worst


## Highest particle speed over the last substep. 0 before the first step.
func get_max_speed() -> float:
	if _last_substep <= 0.0:
		return 0.0
	var fastest := 0.0
	for i in _positions.size():
		fastest = maxf(fastest, _positions[i].distance_to(_previous[i]))
	return fastest / _last_substep


func _integrate(dt: float) -> void:
	var retain := exp(-_config.damping * dt)
	var gravity_step := _config.gravity * (dt * dt)
	for i in _positions.size():
		var current := _positions[i]
		if _inverse_mass[i] == 0.0:
			_previous[i] = current
			continue
		var local_retain := retain
		if _release_remaining > 0.0:
			var distance := absf(float(i) - _release_u * float(_positions.size() - 1))
			local_retain *= exp(-12.0 * dt * clampf(1.0 - distance / 4.0, 0.0, 1.0) * (_release_remaining / 0.12))
		var predicted := current + (current - _previous[i]) * local_retain + gravity_step
		_positions[i] = predicted
		_previous[i] = current
		if _collision != null:
			var constrained := _collision.constrain_motion(current, predicted, _config.radius)
			# Apply sweep response to Verlet history as well as position. Otherwise
			# a resting particle would keep its sliding velocity indefinitely.
			RopeCollision.apply_contact(_positions, _previous, i, constrained - predicted, _config.friction)


func _solve_distances(alpha: float, reverse: bool) -> void:
	var rest := _config.get_rest_length()
	var count := _positions.size() - 1
	for k in count:
		var i := count - 1 - k if reverse else k
		var w0 := _inverse_mass[i]
		var w1 := _inverse_mass[i + 1]
		var weight := w0 + w1
		if weight == 0.0:
			continue
		var delta := _positions[i + 1] - _positions[i]
		var distance := delta.length()
		if distance < 1e-9:
			continue
		var d_lambda := (rest - distance - alpha * _lambdas[i]) / (weight + alpha)
		_lambdas[i] += d_lambda
		var correction := delta * (d_lambda / distance)
		_positions[i] -= correction * w0
		_positions[i + 1] += correction * w1
