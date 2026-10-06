class_name SurfaceClearance
extends RefCounted
## Ordinary Wrap goes over nearby standing strands. Pass constraints take
## priority in RopeInteraction and may deliberately follow a different corridor.
static func over_target(point: Vector3,points: PackedVector3Array,u: float,radius: float,collision: RopeCollision) -> Vector3:
	if points.is_empty() or u < 0 or collision.get_body_clearance(point) > radius*8: return point
	var near := false
	var coordinate := u*(points.size()-1)
	for i in points.size()-1:
		if minf(absf(i-coordinate),absf(i+1-coordinate)) < 4: continue
		if _closest(point,points[i],points[i+1]).distance_squared_to(point) < radius*radius*64:
			near = true
			break
	if not near: return point
	var normal := collision.get_body_normal(point)
	if normal == Vector3.ZERO: return point
	var lift := 0.0
	for i in points.size()-1:
		if minf(absf(i-coordinate),absf(i+1-coordinate)) < 4: continue
		var other := _closest(point,points[i],points[i+1])
		if other.distance_squared_to(point) > radius*radius*100: continue
		if collision.get_body_clearance(other) > radius*6: continue
		var offset := other-point
		var height := offset.dot(normal)
		var tangent_distance := (offset-normal*height).length()
		if tangent_distance >= radius*5: continue
		var influence := clampf((radius*5-tangent_distance)/(radius*3),0,1)
		lift = maxf(lift,maxf(0,height+radius*2.2)*influence)
	var lifted := point+normal*minf(lift,radius*8)
	# A second layer may not fit between arm and torso. Do not manufacture an
	# impossible target inside the neighboring body part; leave that ambiguity
	# for a different passage/approach rather than pressing into the obstacle.
	if not collision.is_body_segment_clear(point,lifted,radius): return point
	return lifted

static func _closest(point: Vector3,a: Vector3,b: Vector3) -> Vector3:
	var edge := b-a
	return a+edge*clampf((point-a).dot(edge)/maxf(edge.length_squared(),1e-12),0,1)
