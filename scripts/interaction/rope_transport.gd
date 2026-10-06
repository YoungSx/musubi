class_name RopeTransport
extends RefCounted
## Input-driven material transport along the CURRENT centerline, not an undo
## recording. Targets are soft constraints; length and contact stay authoritative.
var active := false
var eligible := false
var progress := 0.0
var _curve := PackedVector3Array()
var _arc := PackedFloat64Array()
var _end := 0
var _dwell := 0.0
var _travel := 0.0
var _screen_travel := 0.0
var _velocity := Vector2.ZERO
var _abandoned := false
var _screen_axis := Vector2.ZERO
var _meters_per_pixel := 0.0
var _ground_height := 0.0
var _payout := RopePayout.new()
var _radius := 0.012
var _collision: RopeCollision

func begin(points: PackedVector3Array,u: float,radius: float,floor_y: float,collision: RopeCollision = null) -> void:
	active = false
	eligible = false
	progress = 0
	_dwell = 0
	_travel = 0
	_screen_travel = 0
	_velocity = Vector2.ZERO
	_abandoned = false
	_curve = points.duplicate()
	_ground_height = floor_y+radius+0.00005
	_radius = radius
	_collision = collision
	_arc.resize(points.size())
	_arc[0] = 0
	for i in range(1,points.size()): _arc[i] = _arc[i-1]+points[i-1].distance_to(points[i])
	_end = points.size()-1 if u >= 0.975 else 0
	_payout.configure(_curve,points.size()-1-_end,radius,_ground_height,collision)
	if u > 0.025 and u < 0.975: return
	for point in points:
		if point.y > floor_y+0.3: return
	if Vector2(points[1].x-points[0].x,points[1].z-points[0].z).length_squared() < 1e-10: return
	if Vector2(points[-1].x-points[-2].x,points[-1].z-points[-2].z).length_squared() < 1e-10: return
	eligible = crossing_word(points,radius).size() >= 6

func update(delta: Vector2,camera: Camera3D,points: PackedVector3Array,radius: float,dt: float) -> PackedVector3Array:
	if not eligible or _abandoned or delta.length_squared() < 1e-10: return targets() if active else PackedVector3Array()
	var sign_arc := 1.0 if _end == 0 else -1.0
	var position := _arc[_end]+sign_arc*progress
	var here := _sample(position)
	var next := _sample(position+sign_arc*0.03)
	var projected := camera.unproject_position(next)-camera.unproject_position(here)
	if not active and projected.length() < 1.0:
		stop()
		return PackedVector3Array()
	_velocity = _velocity.lerp(delta/maxf(dt,0.001),1-exp(-dt/0.075))
	var direction := _screen_axis if active else projected.normalized()
	var alignment := _velocity.normalized().dot(direction)
	if not active:
		if dt >= 0.099:
			_dwell = 0
			_travel = 0
			_screen_travel = 0
		if alignment < 0.8:
			_dwell = 0
			_travel = 0
			_screen_travel = 0
			return PackedVector3Array()
		_dwell += minf(dt,0.04)
		_travel += maxf(0,delta.dot(direction))*0.03/projected.length()
		_screen_travel += maxf(0,delta.dot(direction))
		if _dwell < 0.12 or _travel < radius*6 or _screen_travel < camera.get_viewport().get_visible_rect().size.y*0.015: return PackedVector3Array()
		if crossing_word(points,radius).size() < 6:
			eligible = false
			return PackedVector3Array()
		# Refresh the guide at commitment; free approach may have moved the rope.
		_curve = points.duplicate()
		_payout.configure(_curve,points.size()-1-_end,_radius,_ground_height,_collision)
		for i in range(1,points.size()): _arc[i] = _arc[i-1]+points[i-1].distance_to(points[i])
		active = true
		_screen_axis = direction
		_meters_per_pixel = 0.03/projected.length()
	if absf(alignment) < 0.35 and _velocity.length() > 5:
		stop()
		return PackedVector3Array()
	var previous_targets := targets()
	for i in points.size():
		if points[i].distance_to(previous_targets[i]) > radius*5:
			return previous_targets # Resistance, not unlimited hidden progress.
	var limit := minf(radius*0.8,maxf(dt,0)*0.3)
	var amount := clampf(delta.dot(_screen_axis)*_meters_per_pixel,-limit,limit)
	progress = clampf(progress+amount,0,_arc[-1])
	return targets()

func targets() -> PackedVector3Array:
	var result := PackedVector3Array()
	if not active: return result
	var shift := progress if _end == 0 else -progress
	for distance in _arc: result.append(_sample(distance+shift))
	return result

func stop() -> void:
	active = false
	_abandoned = true

func _sample(distance: float) -> Vector3:
	if distance <= 0:
		return _payout.sample(-distance) if _end != 0 else _curve[0]
	if distance >= _arc[-1]:
		return _payout.sample(distance-_arc[-1]) if _end == 0 else _curve[-1]
	var left := 0
	var right := _arc.size()-1
	while right-left > 1:
		var middle := (left+right)/2
		if _arc[middle] < distance: left = middle
		else: right = middle
	return _curve[left].lerp(_curve[right],(distance-_arc[left])/maxf(_arc[right]-_arc[left],1e-9))

static func crossing_word(points: PackedVector3Array,radius: float,reduce_trivial := true) -> Array[int]:
	var encounters: Array[Vector2] = []
	var id := 0
	for i in points.size()-1:
		for j in range(i+3,points.size()-1):
			var a := Vector2(points[i].x,points[i].z)
			var b := Vector2(points[i+1].x,points[i+1].z)
			var c := Vector2(points[j].x,points[j].z)
			var d := Vector2(points[j+1].x,points[j+1].z)
			var hit: Variant = Geometry2D.segment_intersects_segment(a,b,c,d)
			if hit == null: continue
			var s := clampf(((hit as Vector2)-a).dot(b-a)/maxf(a.distance_squared_to(b),1e-10),0,1)
			var t := clampf(((hit as Vector2)-c).dot(d-c)/maxf(c.distance_squared_to(d),1e-10),0,1)
			var height := lerpf(points[i].y,points[i+1].y,s)-lerpf(points[j].y,points[j+1].y,t)
			if absf(height) < radius*1.5: continue
			id += 1
			encounters.append(Vector2(i+s,id*signf(height)))
			encounters.append(Vector2(j+t,-id*signf(height)))
	encounters.sort_custom(func(a: Vector2,b: Vector2): return a.x < b.x)
	var word: Array[int] = []
	for encounter in encounters:
		var value := int(encounter.y)
		if reduce_trivial and not word.is_empty() and word[-1] == -value: word.pop_back()
		else: word.append(value)
	return word
