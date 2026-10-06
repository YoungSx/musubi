class_name GroundLoopTopology
extends RefCounted
## Local floor-loop observations. Crossings retain material coordinates and
## actual height order. A projected crossing alone is not a valid pass event.

func observe(points: PackedVector3Array, radius: float, floor_height: float) -> Array[Dictionary]:
	var loops: Array[Dictionary] = []
	for i in points.size() - 1:
		for j in range(i + 6, points.size() - 1):
			var a := Vector2(points[i].x, points[i].z)
			var b := Vector2(points[i + 1].x, points[i + 1].z)
			var c := Vector2(points[j].x, points[j].z)
			var d := Vector2(points[j + 1].x, points[j + 1].z)
			var hit: Variant = Geometry2D.segment_intersects_segment(a, b, c, d)
			if hit == null:
				continue
			var p: Vector2 = hit
			var t := clampf((p - a).dot(b - a) / maxf(a.distance_squared_to(b), 1e-10), 0, 1)
			var u := clampf((p - c).dot(d - c) / maxf(c.distance_squared_to(d), 1e-10), 0, 1)
			var first_y := lerpf(points[i].y, points[i + 1].y, t)
			var last_y := lerpf(points[j].y, points[j + 1].y, u)
			if absf(first_y - last_y) > radius * 5 or maxf(first_y, last_y) > floor_height + 0.25:
				continue
			var polygon := PackedVector2Array([p])
			var height_ok := true
			for k in range(i + 1, j + 1):
				var vertex := Vector2(points[k].x, points[k].z)
				if polygon[-1].distance_squared_to(vertex) > 1e-10:
					polygon.append(vertex)
				if points[k].y > floor_height + 0.3:
					height_ok = false
			if polygon.size() > 2 and polygon[-1].distance_squared_to(p) < 1e-10:
				polygon.remove_at(polygon.size() - 1)
			if not height_ok or polygon.size() < 4:
				continue
			var area := 0.0
			var center := Vector2.ZERO
			for k in polygon.size():
				area += polygon[k].cross(polygon[(k + 1) % polygon.size()])
				center += polygon[k]
			center /= polygon.size()
			if absf(area) * 0.5 < radius * radius * 20 or not Geometry2D.is_point_in_polygon(center, polygon):
				continue
			# Reuse the existing simple-polygon rejection (no figure-eight as one hole).
			if not RopePassCandidates.is_simple_polygon(polygon):
				continue
			loops.append({"id": Vector2i(i, j), "first": i + t, "last": j + u,
				"polygon": polygon, "center": center, "over": i + t if first_y > last_y else j + u})
			if loops.size() > 8:
				return [] # Ambiguous dense geometry is not assigned an arbitrary loop.
	# Mixed-arc cells in a tightened knot are not necessarily one simple
	# material loop. Add bounded faces while retaining stable existing IDs.
	for face in GroundFaces.new().observe(points,radius,floor_height):
		var duplicate := false
		for loop in loops:
			if loop.center.distance_to(face.center) < radius*3: duplicate = true
		if not duplicate: loops.append(face)
	return loops


func entries(loops: Array[Dictionary], points: PackedVector3Array, tip: Vector3,
		direction: Vector2, grip_u: float, radius: float, collision: RopeCollision) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var start := Vector2(tip.x, tip.z)
	var coordinate := grip_u * (points.size() - 1)
	if grip_u > 0.025 and grip_u < 0.975:
		return result
	for loop in loops:
		if not loop.get("face",false) and coordinate >= loop.first - 0.5 and coordinate <= loop.last + 0.5:
			continue
		var exiting := Geometry2D.is_point_in_polygon(start,loop.polygon)
		for k in range(floori(loop.first), mini(ceili(loop.last), points.size() - 1)):
			if absf(k - coordinate) < 4:
				continue
			var a := Vector2(points[k].x, points[k].z)
			var b := Vector2(points[k + 1].x, points[k + 1].z)
			var hit: Variant = Geometry2D.segment_intersects_segment(start, start + direction * 0.18, a, b)
			if hit == null:
				continue
			var entry: Vector2 = hit
			if Geometry2D.is_point_in_polygon(entry + direction * radius * 1.5, loop.polygon) == exiting:
				continue
			var t := clampf((entry - a).dot(b - a) / maxf(a.distance_squared_to(b), 1e-10), 0, 1)
			var world := points[k].lerp(points[k + 1], t)
			var lift_target := world + Vector3.UP * 0.12
			if collision != null and collision.get_clearance(lift_target) < radius:
				continue
			var normal := Vector2(-(b - a).y, (b - a).x).normalized()
			if normal.dot(direction) < 0: normal = -normal
			var distance := start.distance_to(entry)
			var candidate := {"loop": loop, "edge": k, "u": (k + t) / float(points.size() - 1),
				"exiting":exiting,
				"entry": entry, "world": world, "normal": normal,
				"alignment": direction.dot(normal), "distance": distance}
			var duplicate := false
			for index in result.size():
				if absf(float(result[index].u)-float(candidate.u))*(points.size()-1) < 1.5 and result[index].entry.distance_to(entry) < radius * 2 and result[index].normal.dot(normal) > 0.9:
					if candidate.alignment > result[index].alignment: result[index] = candidate
					duplicate = true
					break
			if not duplicate: result.append(candidate)
	return result
