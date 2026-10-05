class_name SelfCollisionFixture
extends RefCounted
## Uniformly sampled open figure-eight, with a close over/under crossing.

static func points(count: int = 48) -> PackedVector3Array:
	var dense := PackedVector3Array()
	var arc := PackedFloat32Array([0.0])
	for i in 1001:
		var angle := lerpf(-0.5, TAU - 0.8, float(i) / 1000.0)
		dense.append(Vector3(0.35 * sin(angle), 1.1 + 0.25 * sin(2.0 * angle), 0.018 * cos(angle)))
		if i > 0:
			arc.append(arc[-1] + dense[i].distance_to(dense[i - 1]))
	var result := PackedVector3Array()
	var cursor := 1
	for i in count + 1:
		var distance := arc[-1] * float(i) / float(count)
		while cursor < arc.size() - 1 and arc[cursor] < distance:
			cursor += 1
		result.append(dense[cursor - 1].lerp(dense[cursor], (distance - arc[cursor - 1]) / (arc[cursor] - arc[cursor - 1])))
	return result


static func clearance(points: PackedVector3Array, config: RopeConfig) -> float:
	var excluded := maxi(1, ceili((config.radius * 2 + RopeSelfCollision.SKIN) / config.get_rest_length()))
	var result := INF
	for i in points.size() - 1:
		for j in range(i + excluded + 1, points.size() - 1):
			var pair := Geometry3D.get_closest_points_between_segments(points[i], points[i + 1], points[j], points[j + 1])
			result = minf(result, pair[0].distance_to(pair[1]))
	return result
