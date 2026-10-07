class_name RopeInteraction
extends RefCounted
## Picks the visible centerline and translates pointer motion into a temporary
## solver target. Rope positions and renderer geometry are never edited here.

var pick_radius_pixels := 24.0
var grip_id := -1
var _multi_grip := false
var _rope: Rope
var _camera: Camera3D
var _selected_index := -1
var _drag_plane := Plane()
var _grab_offset := Vector3.ZERO
var _last_screen_position := Vector2.ZERO
var _drag_origin := Vector3.ZERO
var _drag_depth := 0.0
var _min_depth := 0.1
var _max_depth := 10.0
var _picked_u := 0.0
var _camera_reference := Transform3D.IDENTITY
var _pass_assist := RopePassAssist.new()
var _assist_enabled := false
var _last_intent_usec := 0
var _manual_depth_until_usec := 0
var _validation_time := 0.0
var _ground_hand := GroundHand.new()
var _ground_intent := GroundPassIntent.new()
var _owns_support := false
var _ground_simulation_id := 0
var _ground_validation_time := 0.0
var _surface_intent := SurfaceIntent.new()
var _transport := RopeTransport.new()
var _returning_control := false


func set_pass_assist_enabled(enabled: bool) -> void:
	_assist_enabled = enabled
	_pass_assist.begin(Vector3.ZERO)


func configure_pass_assistance(config: PassAssistConfig) -> void:
	if config != null:
		_pass_assist.config = config.duplicate() as PassAssistConfig


## Shared automatic support/transport belongs to single-hand interaction only.
## Once another hand joins, keep explicit hand control until this grip ends.
func use_multiple_hands() -> void:
	_multi_grip = true
	_stop_support()
	_transport.stop()
	_rope.get_simulation().set_transport_targets(PackedVector3Array())
	_ground_hand.active = false
	_ground_intent.clear()
	_surface_intent.begin(Vector3.ZERO, Vector2.ZERO)
	rebase(_last_screen_position)


func get_pass_state() -> RopePassAssist.State:
	return _pass_assist.state


func tick(delta: float) -> void:
	if _selected_index >= 0 and _ground_hand.active:
		var sim := _rope.get_simulation()
		_ground_intent.observe_actual(sim.get_grip_position(grip_id), sim.get_positions(), _rope.config.radius)
		_ground_validation_time -= delta
		if _owns_support and _ground_intent.support_u < 0:
			_stop_support()
		elif _owns_support and _ground_validation_time <= 0:
			_ground_validation_time = 0.05
			if not _ground_intent.validate_active(sim.get_positions(),_rope.config.radius): _stop_support()
	if not _assist_enabled or _multi_grip or _selected_index < 0 or _pass_assist.state == RopePassAssist.State.FREE:
		return
	_validation_time -= delta
	if _validation_time > 0.0:
		return
	_validation_time = 0.05
	if not _pass_assist.validate_active(_rope.get_simulation().get_positions(), _rope.config.radius, _picked_u, _rope.get_collision()):
		_surface_intent.rebase_target(_rope.get_simulation().get_drag_target(grip_id),_last_screen_position)
		rebase(_last_screen_position) # Keep the hand target fixed; only discard the path.


func configure(rope: Rope, camera: Camera3D) -> void:
	end()
	_rope = rope
	_camera = camera


func begin(screen_position: Vector2) -> bool:
	end()
	if _rope == null or _camera == null:
		return false
	var index := _pick(screen_position)
	if index < 0:
		return false
	var coordinate := _picked_u * (_rope.get_simulation().get_point_count() - 1)
	var base := floori(coordinate)
	var point := _rope.get_simulation().get_point(base).lerp(_rope.get_simulation().get_point(mini(base + 1, _rope.get_simulation().get_point_count() - 1)), coordinate - base)
	var floor_height := _rope.get_collision().floor_height if _rope.get_collision() != null else 0.0
	_ground_hand.begin(point, floor_height)
	_ground_hand.active = _ground_hand.active and _assist_enabled and not _multi_grip and _rope.initial_layout == Rope.InitialLayout.FLOOR
	_drag_plane = Plane(Vector3.UP if _ground_hand.active else _camera.global_basis.z.normalized(), point)
	var intersection: Variant = _project_on_plane(screen_position)
	if intersection == null or not _rope.begin_grip(_picked_u, grip_id):
		return false
	_selected_index = index
	_returning_control = false
	_grab_offset = point - (intersection as Vector3)
	_last_screen_position = screen_position
	_drag_origin = _camera.global_position
	_drag_depth = _drag_plane.normal.dot(_drag_origin - point)
	_min_depth = maxf(_camera.near + 0.05, _drag_depth - _rope.config.length * 2.0)
	_max_depth = minf(_camera.far * 0.9, _drag_depth + _rope.config.length * 2.0)
	_camera_reference = _camera.global_transform
	var simulation_id := _rope.get_simulation().get_instance_id()
	if simulation_id != _ground_simulation_id:
		_ground_intent.clear()
		_ground_simulation_id = simulation_id
	_ground_intent.begin(point)
	_transport.begin(_rope.get_simulation().get_positions(),_picked_u,_rope.config.radius,floor_height,_rope.get_collision())
	if _rope.is_start_attached() or _rope.is_end_attached(): _transport.eligible = false
	_surface_intent.begin(point,screen_position)
	_pass_assist.begin(point)
	_last_intent_usec = Time.get_ticks_usec()
	_manual_depth_until_usec = 0
	return true


func move(screen_position: Vector2) -> void:
	if _selected_index < 0:
		return
	if not _camera_reference.is_equal_approx(_camera.global_transform):
		rebase(_last_screen_position, false)
	var screen_delta := screen_position - _last_screen_position
	_last_screen_position = screen_position
	if screen_delta.length_squared() < 1e-10 and Time.get_ticks_usec() >= _manual_depth_until_usec:
		return
	var intersection: Variant = _project_on_plane(screen_position)
	if intersection != null:
		if _returning_control:
			var previous: Variant = _project_on_plane(screen_position-screen_delta)
			if previous != null:
				_grab_offset = _grab_offset.move_toward(Vector3.ZERO,(intersection as Vector3).distance_to(previous)*0.5)
				_returning_control = _grab_offset.length_squared() > 1e-10
		var target := (intersection as Vector3) + _grab_offset
		var now := Time.get_ticks_usec()
		var dt := minf(float(now - _last_intent_usec) / 1000000.0, 0.1)
		var sim := _rope.get_simulation()
		var floor_height := _rope.get_collision().floor_height if _rope.get_collision() != null else 0.0
		var was_passing := _pass_assist.state != RopePassAssist.State.FREE
		if _assist_enabled and not _multi_grip and _ground_hand.active:
			var was_transporting := _transport.active
			var guide := _transport.update(screen_delta,_camera,sim.get_positions(),_rope.config.radius,dt)
			sim.set_transport_targets(guide, grip_id)
			if was_transporting and guide.is_empty():
				rebase(screen_position)
				_returning_control = true
				_surface_intent.begin(sim.get_grip_position(grip_id),screen_position)
				_last_intent_usec = now
				return
			if not guide.is_empty():
				_stop_support()
				_ground_intent.abort()
				_rope.update_drag_target(guide[0] if _picked_u < 0.5 else guide[-1], grip_id)
				_last_intent_usec = now
				return
		if _assist_enabled and not _multi_grip and not was_passing and (_picked_u <= 0.025 or _picked_u >= 0.975):
			var was_surface := _surface_intent.active
			target = _surface_intent.update(screen_position,_camera,target,_rope.config.radius,_rope.get_collision(),sim.get_grip_position(grip_id),sim.get_positions(),_picked_u,dt)
			if was_surface and not _surface_intent.active: _returning_control = true
		if _surface_intent.active:
			_returning_control = false
			_stop_support()
			if _ground_hand.active: _ground_intent.clear()
			_ground_hand.active = false
			_ground_intent.abort()
		elif _ground_hand.active:
			target = _ground_intent.update(target, sim.get_grip_position(grip_id), sim.get_positions(), _picked_u, _rope.config.radius, floor_height, _rope.get_collision(), dt)
			_sync_support()
			target = _ground_hand.resolve(target, sim.get_positions(), _picked_u, _rope.config.radius, floor_height, _ground_intent.prefer_under, dt)
		if _assist_enabled and not _multi_grip and not _ground_hand.active and now >= _manual_depth_until_usec:
			target = _pass_assist.update(target, sim.get_grip_position(grip_id), sim.get_positions(), _rope.config.radius,
				_picked_u, _camera.global_basis.z.normalized(), _rope.get_collision(), dt)
		else:
			_pass_assist.begin(target)
		_last_intent_usec = now
		_rope.update_drag_target(target, grip_id)
		if _surface_intent.active:
			rebase(screen_position,false)
		if _pass_assist.needs_rebase:
			_surface_intent.rebase_target(target,screen_position)
			rebase(screen_position,false)
		elif not was_passing and _pass_assist.state != RopePassAssist.State.FREE:
			rebase(screen_position,false)


## A camera move must not be interpreted as a hand move. Keep the requested
## world position, then rebuild the pointer offset in the new view.
func rebase(screen_position: Vector2, reset_assist := true) -> void:
	if _selected_index < 0:
		return
	if not _camera_reference.is_equal_approx(_camera.global_transform):
		_surface_intent.begin(_rope.get_simulation().get_drag_target(grip_id),screen_position)
	if _transport.active and not _camera_reference.is_equal_approx(_camera.global_transform):
		_transport.stop()
		_rope.get_simulation().set_transport_targets(PackedVector3Array())
	var target := _rope.get_simulation().get_drag_target(grip_id)
	_drag_plane = Plane(Vector3.UP if _ground_hand.active else _camera.global_basis.z.normalized(), target)
	var intersection: Variant = _project_on_plane(screen_position)
	if intersection == null:
		return
	_grab_offset = target - (intersection as Vector3)
	_last_screen_position = screen_position
	_drag_origin = _camera.global_position
	_drag_depth = _drag_plane.normal.dot(_drag_origin - target)
	_min_depth = maxf(_camera.near + 0.05, _drag_depth - _rope.config.length * 2.0)
	_max_depth = minf(_camera.far * 0.9, _drag_depth + _rope.config.length * 2.0)
	_camera_reference = _camera.global_transform
	_ground_intent.rebase(target)
	if reset_assist:
		_pass_assist.begin(target)
	else:
		_pass_assist.rebase_input(target)


## Wheel-up moves the active plane toward the viewer. Reachability and soft
## collision response remain solver responsibilities, including free ends.
func adjust_depth(factor: float) -> void:
	if _ground_hand.active:
		return
	if _selected_index < 0 or not is_finite(factor) or factor <= 0.0:
		return
	if not _camera_reference.is_equal_approx(_camera.global_transform):
		rebase(_last_screen_position)
	_manual_depth_until_usec = Time.get_ticks_usec() + 300000
	_drag_depth = clampf(_drag_depth / factor, _min_depth, _max_depth)
	_drag_plane = Plane(_drag_plane.normal, _drag_origin - _drag_plane.normal * _drag_depth)
	move(_last_screen_position)


func get_drag_depth() -> float:
	return _drag_depth


func end() -> void:
	_multi_grip = false
	_returning_control = false
	_transport.stop()
	_surface_intent.begin(Vector3.ZERO,Vector2.ZERO)
	if _selected_index >= 0 and is_instance_valid(_rope):
		_rope.end_drag(grip_id)
	_stop_support()
	_ground_intent.begin(Vector3.ZERO)
	_selected_index = -1
	_pass_assist.begin(Vector3.ZERO)


func get_selected_index() -> int:
	return _selected_index


func cancel() -> void:
	_returning_control = false
	_transport.stop()
	_surface_intent.begin(Vector3.ZERO,Vector2.ZERO)
	_rope.cancel_drag()
	_owns_support = false
	_ground_intent.clear()
	_selected_index = -1
	_pass_assist.begin(Vector3.ZERO)


func _sync_support() -> void:
	if _ground_intent.support_u < 0:
		_stop_support()
		return
	if _owns_support and absf(_rope.get_simulation().get_support_u()-_ground_intent.support_u) > 0.00001:
		_stop_support()
	if not _owns_support:
		_owns_support = _rope.begin_support(_ground_intent.support_u, 0.0)
		if not _owns_support:
			_ground_intent.abort()
			return
	_rope.get_simulation().update_support_target(_ground_intent.support_origin + Vector3.UP * 0.12 * _ground_intent.support_strength)


func _stop_support() -> void:
	if _owns_support and is_instance_valid(_rope):
		_rope.end_support()
	_owns_support = false


func pick(screen_position: Vector2) -> int:
	return _pick(screen_position)


func _project_on_plane(screen_position: Vector2) -> Variant:
	return _drag_plane.intersects_ray(_camera.project_ray_origin(screen_position), _camera.project_ray_normal(screen_position))


func _pick(screen_position: Vector2) -> int:
	var simulation := _rope.get_simulation()
	var points := simulation.get_positions()
	var best_distance := pick_radius_pixels * pick_radius_pixels
	var best_depth := INF
	var selected := -1
	for i in points.size() - 1:
		if _camera.is_position_behind(points[i]) or _camera.is_position_behind(points[i + 1]):
			continue
		var a := _camera.unproject_position(points[i])
		var b := _camera.unproject_position(points[i + 1])
		var segment := b - a
		var t := clampf((screen_position - a).dot(segment) / maxf(segment.length_squared(), 1e-8), 0.0, 1.0)
		var distance := screen_position.distance_squared_to(a + segment * t)
		if distance > best_distance + 0.01:
			continue
		var index := i if t < 0.5 else i + 1
		if not _rope.can_drag(index):
			continue
		var candidate := points[i].lerp(points[i + 1], t)
		var depth := _camera.global_position.distance_squared_to(candidate)
		if absf(distance - best_distance) < 0.01 and depth >= best_depth:
			continue
		if not _is_visible(candidate) or not _is_visible(points[index]):
			continue
		selected = index
		_picked_u = (float(i) + t) / float(points.size() - 1)
		# End caps remain easy to pick without snapping every interior grip to a node.
		if index == 0 and screen_position.distance_squared_to(a) < pick_radius_pixels * pick_radius_pixels * 0.25:
			_picked_u = 0.0
		elif index == points.size() - 1 and screen_position.distance_squared_to(b) < pick_radius_pixels * pick_radius_pixels * 0.25:
			_picked_u = 1.0
		best_distance = distance
		best_depth = depth
	return selected


## Sphere tracing the same primitive distances used by the solver avoids a
## physics-server query from an input callback. Trace toward the candidate,
## not the finger's center: the generous touch radius can be beside the rope.
func _is_visible(point: Vector3) -> bool:
	var origin := _camera.project_ray_origin(_camera.unproject_position(point))
	return RopeVisibility.is_visible(origin, point, _rope.get_collision())
