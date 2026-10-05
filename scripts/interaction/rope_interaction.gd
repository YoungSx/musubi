class_name RopeInteraction
extends RefCounted
## Picks the visible centerline and translates pointer motion into a temporary
## solver target. Rope positions and renderer geometry are never edited here.

var pick_radius_pixels := 24.0
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
	_drag_plane = Plane(_camera.global_basis.z.normalized(), point)
	var intersection: Variant = _project_on_plane(screen_position)
	if intersection == null or not _rope.begin_grip(_picked_u):
		return false
	_selected_index = index
	_grab_offset = point - (intersection as Vector3)
	_last_screen_position = screen_position
	_drag_origin = _camera.global_position
	_drag_depth = _drag_plane.normal.dot(_drag_origin - point)
	_min_depth = maxf(_camera.near + 0.05, _drag_depth - _rope.config.length * 2.0)
	_max_depth = minf(_camera.far * 0.9, _drag_depth + _rope.config.length * 2.0)
	_camera_reference = _camera.global_transform
	return true


func move(screen_position: Vector2) -> void:
	if _selected_index < 0:
		return
	if not _camera_reference.is_equal_approx(_camera.global_transform):
		rebase(_last_screen_position)
	_last_screen_position = screen_position
	var intersection: Variant = _project_on_plane(screen_position)
	if intersection != null:
		_rope.update_drag_target((intersection as Vector3) + _grab_offset)


## A camera move must not be interpreted as a hand move. Keep the requested
## world position, then rebuild the pointer offset in the new view.
func rebase(screen_position: Vector2) -> void:
	if _selected_index < 0:
		return
	var target := _rope.get_simulation().get_drag_target()
	_drag_plane = Plane(_camera.global_basis.z.normalized(), target)
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


## Wheel-up moves the active plane toward the viewer. Reachability and soft
## collision response remain solver responsibilities, including free ends.
func adjust_depth(factor: float) -> void:
	if _selected_index < 0 or not is_finite(factor) or factor <= 0.0:
		return
	if not _camera_reference.is_equal_approx(_camera.global_transform):
		rebase(_last_screen_position)
	_drag_depth = clampf(_drag_depth / factor, _min_depth, _max_depth)
	_drag_plane = Plane(_drag_plane.normal, _drag_origin - _drag_plane.normal * _drag_depth)
	move(_last_screen_position)


func get_drag_depth() -> float:
	return _drag_depth


func end() -> void:
	if _selected_index >= 0 and is_instance_valid(_rope):
		_rope.end_drag()
	_selected_index = -1


func get_selected_index() -> int:
	return _selected_index


func cancel() -> void:
	_rope.cancel_drag()
	_selected_index = -1


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
