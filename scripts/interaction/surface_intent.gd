class_name SurfaceIntent
extends RefCounted
## Pointer trajectories may follow the mannequin's visible surface. Near a
## silhouette, reversal may continue around the rear surface. Physics still
## decides reachable motion; this class only proposes a bounded grip target.
var active := false
var rear := false
var _target := Vector3.ZERO
var _last_screen := Vector2.ZERO
var _direction := Vector2.ZERO
var _rim_direction := Vector2.ZERO
var _rim := false
var _reverse_travel := 0.0

func begin(point: Vector3,screen: Vector2) -> void:
	active = false
	rear = false
	_target = point
	_last_screen = screen
	_direction = Vector2.ZERO
	_rim = false
	_rim_direction = Vector2.ZERO
	_reverse_travel = 0

func update(screen: Vector2,camera: Camera3D,raw: Vector3,radius: float,collision: RopeCollision,actual: Vector3) -> Vector3:
	var movement := screen-_last_screen
	_last_screen = screen
	if movement.length_squared() < 0.01: return _target if active else raw
	var meters_per_pixel := 2*camera.global_position.distance_to(actual)*tan(deg_to_rad(camera.fov)*0.5)/maxf(camera.get_viewport().get_visible_rect().size.y,1)
	var budget := minf(movement.length()*meters_per_pixel*4,0.15)
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var front := collision.trace_surface(origin,direction,camera.far,radius+0.002)
	if front.is_empty():
		if active:
			_rim = true
			_rim_direction = _direction
			_target += (raw-_target).limit_length(budget)
			_target = collision.project_point(_target,radius)
			return _target
		return raw
	# Floor drags become a lift only when the cursor actually reaches the figure.
	var back := collision.trace_surface(origin+direction*camera.far,-direction,camera.far,radius+0.002)
	var front_point: Vector3 = front.position
	var rim_now := absf((front.normal as Vector3).dot(direction)) < 0.45
	if active and _rim and movement.normalized().dot(_rim_direction) < -0.5:
		_reverse_travel += movement.length()
		if _reverse_travel >= camera.get_viewport().get_visible_rect().size.y*0.0075:
			rear = not rear
			_rim = false
			_reverse_travel = 0
	else:
		_reverse_travel = 0
	if rim_now and not _rim:
		_rim = true
		_rim_direction = movement.normalized()
	var candidate := front_point
	if rear and not back.is_empty(): candidate = back.position
	if not active:
		_target = actual
		active = true
	_direction = _direction.lerp(movement.normalized(),0.4).normalized()
	_target += (candidate-_target).limit_length(budget)
	_target = collision.project_point(_target,radius)
	return _target
