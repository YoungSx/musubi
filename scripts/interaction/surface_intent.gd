class_name SurfaceIntent
extends RefCounted
## Pointer trajectories may follow the mannequin's visible surface. Near a
## silhouette, reversal may continue around the rear surface. Physics still
## decides reachable motion; this class only proposes a bounded grip target.
var active := false
var rear := false
var _target := Vector3.ZERO
var _last_screen := Vector2.ZERO
var _rim_direction := Vector2.ZERO
var _rim := false
var _reverse_travel := 0.0
var route := SurfaceRoute.new()
var requested_goal := Vector3.ZERO
var confidence := 0.0
var _entry_time := 0.0
var _entry_travel := 0.0
var _entry_origin := Vector2.ZERO
var _outside_travel := 0.0
var _outside_origin := Vector2.ZERO
var _outside := false
var _rim_point := Vector3.ZERO
var _via := Vector3.ZERO
var _via_pending := false
var _wrap_direction := Vector2.ZERO
var _withdraw_travel := 0.0
var _rim_exit_seen := false

func begin(point: Vector3,screen: Vector2) -> void:
	active = false
	rear = false
	_target = point
	requested_goal = point
	_last_screen = screen
	_rim = false
	_rim_direction = Vector2.ZERO
	_reverse_travel = 0
	_entry_time = 0
	_entry_travel = 0
	_outside_travel = 0
	_outside = false
	confidence = 0
	_entry_origin = screen
	_rim_point = point
	_via = point
	_via_pending = false
	_withdraw_travel = 0
	_rim_exit_seen = false

func update(screen: Vector2,camera: Camera3D,raw: Vector3,radius: float,collision: RopeCollision,actual: Vector3,points := PackedVector3Array(),grip_u := -1.0,delta := 1.0/60.0) -> Vector3:
	var previous_screen := _last_screen
	var movement := screen-_last_screen
	_last_screen = screen
	if movement.length_squared() < 0.01: return _target if active else raw
	if _via_pending:
		if movement.normalized().dot(_wrap_direction) < 0.35:
			_withdraw_travel += movement.length()
			if _withdraw_travel < camera.get_viewport().get_visible_rect().size.y*0.0075:
				return _target
			_via_pending = false
			rear = not rear
			_rim = false
			_rim_exit_seen = false
			_withdraw_travel = 0
		else:
			_withdraw_travel = 0
	var meters_per_pixel := 2*camera.global_position.distance_to(actual)*tan(deg_to_rad(camera.fov)*0.5)/maxf(camera.get_viewport().get_visible_rect().size.y,1)
	var budget := minf(movement.length()*meters_per_pixel*4,0.15)
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var front := collision.trace_surface(origin,direction,camera.far,radius+0.002)
	if front.is_empty():
		_entry_time = 0
		_entry_travel = 0
		if active:
			if _rim: _rim_exit_seen = true
			if not _outside:
				_outside_origin = previous_screen
				_outside = true
			# Returning toward the edge is not a withdrawal. Measure excursion,
			# not total travel: an out-and-back stroke must retain its wrap evidence.
			_outside_travel = screen.distance_to(_outside_origin)
			if _outside_travel >= camera.get_viewport().get_visible_rect().size.y*0.025:
				begin(raw,screen)
				return raw
			requested_goal = collision.project_point(raw,radius)
			return _advance(actual,radius,collision,budget,points,grip_u)
		return raw
	_outside_travel = 0
	_outside = false
	if not active:
		if delta >= 0.099: _entry_time = 0
		if _entry_time <= 0: _entry_origin = screen-movement
		_entry_time += clampf(delta,0,0.04)
		_entry_travel = screen.distance_to(_entry_origin)
		confidence = clampf(_entry_time/0.12,0,1)
		if confidence < 1 or _entry_travel < camera.get_viewport().get_visible_rect().size.y*0.005:
			_target = raw
			requested_goal = raw
			return raw
		_target = collision.project_point(raw,radius)
		active = true
	# Floor drags become a lift only when the cursor actually reaches the figure.
	var back := collision.trace_surface(origin+direction*camera.far,-direction,camera.far,radius+0.002)
	var front_point: Vector3 = front.position
	var rim_now := absf((front.normal as Vector3).dot(direction)) < 0.45
	if active and _rim and _rim_exit_seen and movement.normalized().dot(_rim_direction) < -0.5:
		_reverse_travel += movement.length()
		if _reverse_travel >= camera.get_viewport().get_visible_rect().size.y*0.0075:
			rear = not rear
			_via = _rim_point
			_via_pending = true
			_wrap_direction = movement.normalized()
			_withdraw_travel = 0
			_rim = false
			_rim_exit_seen = false
			_reverse_travel = 0
	else:
		_reverse_travel = 0
	if _rim and camera.unproject_position(_rim_point).distance_to(screen) > camera.get_viewport().get_visible_rect().size.y*0.025:
		_rim = false
		_rim_exit_seen = false
	var outward := camera.unproject_position(front_point+(front.normal as Vector3)*0.02)-camera.unproject_position(front_point)
	if rim_now and not _rim and not _via_pending and movement.normalized().dot(outward.normalized()) > 0.5:
		_rim = true
		_rim_exit_seen = false
		_rim_direction = movement.normalized()
		_rim_point = front_point
	var candidate := front_point
	if rear and not back.is_empty(): candidate = back.position
	requested_goal = candidate
	return _advance(actual,radius,collision,budget,points,grip_u)

func rebase_target(target: Vector3,screen: Vector2) -> void:
	_target = target
	requested_goal = target
	_last_screen = screen
	_via_pending = false
	_rim = false
	_rim_exit_seen = false

func _advance(actual: Vector3,radius: float,collision: RopeCollision,budget: float,points: PackedVector3Array,grip_u: float) -> Vector3:
	# Complete only the destination already expressed by the pointer. A leading
	# waypoint stays close to the actual grip, so it cannot cut a body corner.
	if _via_pending and _target.distance_to(_via) < radius*2 and actual.distance_to(_via) < radius*4:
		_via_pending = false
	if budget > 0:
		var goal := _via if _via_pending else requested_goal
		var proposed := route.advance(_target,goal,minf(budget,radius*2),radius,collision)
		proposed = SurfaceClearance.over_target(proposed,points,grip_u,radius,collision)
		proposed = _target.move_toward(proposed,budget)
		# A saturated hand gap limits outward lead, not steering authority.
		# Subtracting the old gap from the movement budget also prevented turning
		# or backing out while the solver lagged under load.
		var lead := maxf(radius*4,_target.distance_to(actual))
		proposed = actual+(proposed-actual).limit_length(lead)
		if collision.is_body_segment_clear(_target,proposed,radius):
			_target = proposed
	_target = collision.project_point(_target,radius)
	return _target
