class_name TorsoLoopEvidence
extends RefCounted
## Read-only acceptance observer for the default mannequin. A near-closed arc
## must really encircle the torso in XZ and stay at torso height. Not knot ID.
static func observe(points: PackedVector3Array,radius: float) -> Dictionary:
	for i in points.size()-1:
		if not _torso_height(points[i]): continue
		for j in range(i+6,points.size()-1):
			if not _torso_height(points[j]): continue
			if not AABB(points[i].min(points[i+1]),(points[i+1]-points[i]).abs()).grow(radius*2.2).intersects(AABB(points[j].min(points[j+1]),(points[j+1]-points[j]).abs()).grow(0.00001)): continue
			var pair := RopeGeometry.closest_segment_points(points[i],points[i+1],points[j],points[j+1])
			if pair[0].distance_to(pair[1]) > radius*2.2: continue
			var path := PackedVector3Array([pair[0]])
			var height_ok := true
			for k in range(i+1,j+1):
				path.append(points[k])
				if not _torso_height(points[k]): height_ok = false
			if not height_ok: continue
			path.append(pair[1])
			var winding := 0.0
			var length := 0.0
			for k in path.size():
				var a := Vector2(path[k].x,path[k].z)
				var b := Vector2(path[(k+1)%path.size()].x,path[(k+1)%path.size()].z)
				if minf(a.length(),b.length()) < 0.1:
					height_ok = false
					break
				winding += atan2(a.cross(b),a.dot(b))
				length += path[k].distance_to(path[(k+1)%path.size()])
			if height_ok and absf(winding) > TAU-0.1:
				return {"first_segment":i,"last_segment":j,"closure_distance":pair[0].distance_to(pair[1]),"winding":winding/TAU,"arc_length":length}
	return {}

static func _torso_height(point: Vector3) -> bool:
	return point.y >= 0.9 and point.y <= 1.43
