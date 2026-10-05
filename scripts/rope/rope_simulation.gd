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
var _drag_index := -1
var _drag_target := Vector3.ZERO
var _drag_lambda := Vector3.ZERO


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
		_integrate(h)
		_lambdas.fill(0.0)
		_drag_lambda = Vector3.ZERO
		for iteration in _config.solver_iterations:
			_solve_drag(h)
			# Alternating sweep direction avoids a bias toward one end.
			_solve_distances(alpha, sweep % 2 == 1)
			if _collision != null:
				for contact_pass in _config.collision_iterations:
					_collision.solve(_positions, _previous, _inverse_mass, _config.radius, _config.friction)
			sweep += 1
	_last_substep = h


func set_collision(collision: RopeCollision) -> void:
	_collision = collision


func capture_state() -> Dictionary:
	return RopeState.encode(_config, _positions, _previous, _inverse_mass,
		_last_substep, _drag_index, _drag_target)


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
	return simulation


func begin_drag(index: int) -> bool:
	if index < 0 or index >= _positions.size() or is_pinned(index):
		return false
	_drag_index = index
	_drag_target = _positions[index]
	return true


func update_drag_target(target: Vector3) -> void:
	if _drag_index < 0 or not target.is_finite():
		return
	# Intersect reachable spheres around attachments; extra path around the
	# mannequin is still handled by the soft constraint rather than stretching.
	for pass_index in 8:
		for i in _positions.size():
			if is_pinned(i):
				var reach := absf(float(i - _drag_index)) * _config.get_rest_length()
				target = _positions[i] + (target - _positions[i]).limit_length(reach)
	_drag_target = target


func end_drag() -> void:
	_drag_index = -1
	_drag_lambda = Vector3.ZERO


func get_drag_index() -> int:
	return _drag_index


func get_drag_target() -> Vector3:
	return _drag_target


func stop_motion() -> void:
	_previous = _positions.duplicate()
	_last_substep = 0.0


func _solve_drag(dt: float) -> void:
	if _drag_index < 0:
		return
	var alpha := _config.drag_compliance / (dt * dt)
	var current := _positions[_drag_index]
	var correction := (_drag_target - current - _drag_lambda * alpha) / (1.0 + alpha)
	correction = correction.limit_length(_config.drag_speed * dt)
	_drag_lambda += correction
	_positions[_drag_index] = current + correction


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
		var predicted := current + (current - _previous[i]) * retain + gravity_step
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
