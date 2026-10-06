class_name RopePassCandidates
extends RefCounted
## Detects small, nearly planar apertures closed by nonlocal rope contact.
## These are local geometric affordances, not mathematical knot recognition.
var config := PassAssistConfig.new()
var _minimum := PackedVector3Array()
var _maximum := PackedVector3Array()


func find(points: PackedVector3Array, radius: float, grip_u: float, collision: RopeCollision) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if points.size() < 12 or (grip_u > 0.02 and grip_u < 0.98):
		return result
	var endpoint := 0 if grip_u < 0.5 else points.size() - 1
	var first := 3 if endpoint == 0 else 0
	var last := points.size() - 2 if endpoint == 0 else points.size() - 5
	_minimum.resize(points.size() - 1)
	_maximum.resize(points.size() - 1)
	for k in points.size() - 1:
		_minimum[k] = points[k].min(points[k + 1])
		_maximum[k] = points[k].max(points[k + 1])
	for i in range(first, last):
		var low := _minimum[i] - Vector3.ONE * radius * config.closure_radii
		var high := _maximum[i] + Vector3.ONE * radius * config.closure_radii
		for j in range(i + config.minimum_loop_segments, last + 1):
			if _minimum[j].x > high.x or _maximum[j].x < low.x or _minimum[j].y > high.y or _maximum[j].y < low.y or _minimum[j].z > high.z or _maximum[j].z < low.z:
				continue
			if points[i].distance_to(points[endpoint]) > config.search_distance + 0.5:
				continue
			var loop := _build_loop(points, radius, Vector3i(i, j, 0), endpoint)
			if loop.is_empty():
				continue
			for slot in 9:
				var candidate := _portal(loop, slot, points, radius, collision, endpoint)
				if candidate.is_empty() or candidate.center.distance_to(points[endpoint]) > config.search_distance:
					continue
				var duplicate := false
				for existing in result:
					if existing.center.distance_to(candidate.center) < radius * 3 and absf(existing.normal.dot(candidate.normal)) > 0.9:
						duplicate = true
						break
				if not duplicate:
					result.append(candidate)
					if result.size() > config.maximum_candidates:
						return [] # Too ambiguous: never pick paths by array order.
				if slot == 0:
					break # Side entrances are only needed when the center is blocked.
	return result


func refresh(points: PackedVector3Array, radius: float, id: Vector3i, collision: RopeCollision, endpoint: int) -> Dictionary:
	var loop := _build_loop(points, radius, id, endpoint)
	return {} if loop.is_empty() else _portal(loop, id.z, points, radius, collision, endpoint)


func _build_loop(points: PackedVector3Array, radius: float, id: Vector3i, endpoint: int) -> Dictionary:
	var i := id.x
	var j := id.y
	if i < 0 or j + 1 >= points.size() or j - i < config.minimum_loop_segments or (endpoint >= i - 2 and endpoint <= j + 3):
		return {}
	var closure := RopeGeometry.closest_segment_points(points[i], points[i + 1], points[j], points[j + 1])
	if closure[0].distance_to(closure[1]) > radius * config.closure_radii:
		return {}
	var boundary := PackedVector3Array([closure[0]])
	for index in range(i + 1, j + 1):
		if boundary[-1].distance_squared_to(points[index]) > 1e-12:
			boundary.append(points[index])
	if boundary[-1].distance_squared_to(closure[1]) > 1e-12:
		boundary.append(closure[1])
	if boundary.size() > 2 and boundary[0].distance_squared_to(boundary[-1]) <= 1e-12:
		boundary.remove_at(boundary.size() - 1)
	var center := Vector3.ZERO
	for point in boundary:
		center += point
	center /= boundary.size()
	var area_vector := Vector3.ZERO
	for k in boundary.size():
		area_vector += (boundary[k] - center).cross(boundary[(k + 1) % boundary.size()] - center)
	if area_vector.length() * 0.5 < PI * pow(radius * 3, 2):
		return {}
	var normal := area_vector.normalized()
	var x := normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
	var y := normal.cross(x)
	var polygon := PackedVector2Array()
	for point in boundary:
		var offset := point - center
		if absf(offset.dot(normal)) > radius * 1.5:
			return {}
		polygon.append(Vector2(offset.dot(x), offset.dot(y)))
	if not Geometry2D.is_point_in_polygon(Vector2.ZERO, polygon) or not is_simple_polygon(polygon):
		return {}
	var half_length := radius * config.corridor_radii
	return {"id": id, "origin": center, "center": center, "normal": normal, "half_length": half_length,
		"axis_x": x, "axis_y": y, "polygon": polygon, "boundary": boundary}


func _portal(loop: Dictionary, slot: int, points: PackedVector3Array, radius: float, collision: RopeCollision, endpoint: int) -> Dictionary:
	if slot < 0 or slot > 8:
		return {}
	# The old single 75%-radius sample could sit inside a torso while a real
	# passage existed nearer the same boundary. Search the radial strip, keeping
	# each accepted corridor subject to full body and standing-rope clearance.
	for sample in (1 if slot == 0 else 32):
		var offset := 0 if sample == 0 else ceili(sample/2.0)*(1 if sample%2 else -1)
		var fraction := config.side_portal_fraction+float(offset)/32.0
		if fraction <= 0 or fraction >= 1: continue
		var candidate := _portal_at(loop,slot,fraction,points,radius,collision,endpoint)
		if not candidate.is_empty(): return candidate
	return {}


func _portal_at(loop: Dictionary, slot: int, fraction: float, points: PackedVector3Array, radius: float, collision: RopeCollision, endpoint: int) -> Dictionary:
	var center: Vector3 = loop.origin
	if slot > 0:
		var boundary: PackedVector3Array = loop.boundary
		var offset: Vector3 = (boundary[floori(float(slot - 1) * boundary.size() / 8.0)] - center) * fraction
		center += offset - loop.normal * offset.dot(loop.normal)
	if not contains_clear_point(loop, center, radius) or not corridor_clear(points, radius, center, loop.normal, loop.half_length, collision, endpoint):
		return {}
	var result := loop.duplicate()
	result.center = center
	result.id = Vector3i(loop.id.x, loop.id.y, slot)
	return result


## Geometric crossing evidence, not a knot-success judgment. Both sides and
## clearance inside the aperture must be observed, not merely a changed Z value.
static func crosses_aperture(a: Vector3, b: Vector3, aperture: Dictionary, radius: float) -> bool:
	var normal: Vector3 = aperture.normal
	var center: Vector3 = aperture.center
	var before := (a - center).dot(normal)
	var after := (b - center).dot(normal)
	if before * after >= 0.0:
		return false
	var point := a.lerp(b, before / (before - after))
	return contains_clear_point(aperture, point, radius)


static func contains_clear_point(aperture: Dictionary, point: Vector3, radius: float) -> bool:
	var offset: Vector3 = point - aperture.origin
	if not Geometry2D.is_point_in_polygon(Vector2(offset.dot(aperture.axis_x), offset.dot(aperture.axis_y)), aperture.polygon):
		return false
	var projected: Vector3 = point - aperture.normal * offset.dot(aperture.normal)
	var boundary: PackedVector3Array = aperture.boundary
	for k in boundary.size():
		var pair := RopeGeometry.closest_segment_points(projected, projected, boundary[k], boundary[(k + 1) % boundary.size()])
		if pair[0].distance_to(pair[1]) < radius * 2.0:
			return false
	return true


func corridor_clear(points: PackedVector3Array, radius: float, center: Vector3, normal: Vector3,
		half_length: float, collision: RopeCollision, endpoint: int) -> bool:
	var a := center + normal * half_length
	var b := center - normal * half_length
	# The immediate incoming tail occupies the corridor behind its tip during a
	# pass. Exclude a bounded material length, independent of sampling density;
	# split the boundary segment so a coarse sample cannot hide a distant return.
	var remaining := half_length*2+radius*config.clearance_radii if endpoint == 0 or endpoint == points.size()-1 else 0.0
	for step in points.size() - 1:
		var k := points.size()-2-step if endpoint == points.size()-1 else step
		var first := points[k+1] if endpoint == points.size()-1 else points[k]
		var last := points[k] if endpoint == points.size()-1 else points[k+1]
		if remaining > 0:
			var length := first.distance_to(last)
			if length <= remaining:
				remaining -= length
				continue
			first = first.lerp(last,remaining/length)
			remaining = 0
		var pair := RopeGeometry.closest_segment_points(a, b, first, last)
		if pair[0].distance_to(pair[1]) < radius * config.clearance_radii:
			return false
	if collision != null:
		# SDF clearance with bounded conservative stepping, including the floor.
		var length := a.distance_to(b)
		var travelled := 0.0
		for step in 64:
			var clearance := collision.get_clearance(a.lerp(b, travelled / maxf(length, 1e-8))) - radius
			if clearance <= 0.0:
				return false
			if travelled >= length:
				return true
			travelled = minf(length, travelled + maxf(clearance * 0.8, 0.00001))
		return false
	return true


static func is_simple_polygon(polygon: PackedVector2Array) -> bool:
	for i in polygon.size():
		var next_i := (i + 1) % polygon.size()
		if polygon[i].distance_squared_to(polygon[next_i]) < 1e-12:
			continue
		for j in range(i + 2, polygon.size()):
			var next_j := (j + 1) % polygon.size()
			if next_j == i or polygon[j].distance_squared_to(polygon[next_j]) < 1e-12:
				continue
			if Geometry2D.segment_intersects_segment(polygon[i], polygon[next_i], polygon[j], polygon[next_j]) != null:
				return false
	return true
