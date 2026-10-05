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
			var pair := RopeGeometry.closest_segment_points(points[i], points[i + 1], points[j], points[j + 1])
			result = minf(result, pair[0].distance_to(pair[1]))
	return result


## Open trefoil-shaped centerline: a stress fixture, not knot recognition.
static func trefoil(count: int = 72) -> PackedVector3Array:
	var dense := PackedVector3Array()
	var arc := PackedFloat32Array([0.0])
	for i in 1201:
		var angle := lerpf(0.25, TAU - 0.25, float(i) / 1200.0)
		var radius := 0.22 + 0.08 * cos(3.0 * angle)
		dense.append(Vector3(radius * cos(2.0 * angle), 1.1 + radius * sin(2.0 * angle), 0.08 * sin(3.0 * angle)))
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


static func rendered_clearance(points: PackedVector3Array, config: RopeConfig, subdivisions: int) -> float:
	var gap := INF
	var excluded := maxi(1, ceili((2 * config.radius + RopeSelfCollision.SKIN) / config.get_rest_length()))
	for i in points.size() - 1:
		for j in range(i + 1, points.size() - 1):
			if floori(float(j) / subdivisions) - floori(float(i) / subdivisions) <= excluded:
				continue
			var pair := RopeGeometry.closest_segment_points(points[i], points[i + 1], points[j], points[j + 1])
			gap = minf(gap, pair[0].distance_to(pair[1]))
	return gap
