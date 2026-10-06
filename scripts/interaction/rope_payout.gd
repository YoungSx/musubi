class_name RopePayout
extends RefCounted
## Incremental floor path for material emerging from the passive end. Queries
## original rope/body clearance; it supplies soft targets, never edits particles.
var _rope := PackedVector3Array()
var _path := PackedVector3Array()
var _heading := Vector3.ZERO
var _radius := 0.012
var _step := 0.018
var _end := 0
var _collision: RopeCollision
var _blocked := false

func configure(points: PackedVector3Array,end: int,radius: float,floor_y: float,collision: RopeCollision) -> void:
	_rope = points
	_end = end
	_radius = radius
	_step = radius*1.5
	_collision = collision
	var adjacent := 1 if end == 0 else points.size()-2
	_heading = points[end]-points[adjacent]
	_heading.y = 0
	_heading = _heading.normalized()
	var origin := points[end]
	origin.y = maxf(origin.y,floor_y)
	_path = PackedVector3Array([origin])
	_blocked = false

func sample(distance: float) -> Vector3:
	while (_path.size()-1)*_step < distance and not _blocked:
		var best := -INF
		var direction := Vector3.ZERO
		for angle in [0.0,-0.26,0.26,-0.52,0.52,-0.78,0.78,-1.05,1.05]:
			var candidate := _heading.rotated(Vector3.UP,angle)
			var target := _path[-1]+candidate*_step
			if _clearance(target) < _radius*1.9 or _clearance(_path[-1].lerp(target,0.5)) < _radius*1.9: continue
			var ahead := _clearance(_path[-1]+candidate*_radius*10)
			var score := candidate.dot(_heading)*0.8+clampf(ahead/(_radius*8),0,1)*2
			if score > best:
				best = score
				direction = candidate
		if direction == Vector3.ZERO:
			_blocked = true
			break
		_heading = direction
		_path.append(_path[-1]+direction*_step)
	var coordinate := minf(distance/_step,_path.size()-1)
	var index := floori(coordinate)
	return _path[index].lerp(_path[mini(index+1,_path.size()-1)],coordinate-index)

func _clearance(point: Vector3) -> float:
	var result := INF
	for i in _rope.size()-1:
		if mini(absi(i-_end),absi(i+1-_end)) <= 3: continue
		result = minf(result,_segment_distance(point,_rope[i],_rope[i+1]))
	for i in maxi(0,_path.size()-4):
		result = minf(result,_segment_distance(point,_path[i],_path[i+1]))
	if _collision != null:
		# Floor is already satisfied; body-only ray/part distances are separate.
		result = minf(result,_collision.get_body_clearance(point)+_radius)
	return result

static func _segment_distance(point: Vector3,a: Vector3,b: Vector3) -> float:
	var edge := b-a
	return point.distance_to(a+edge*clampf((point-a).dot(edge)/maxf(edge.length_squared(),1e-12),0,1))
