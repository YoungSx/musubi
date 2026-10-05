class_name RopeGeometry
extends RefCounted
## Closest finite-segment points using a relative parallelism threshold.
## Godot 4.7.2 Geometry3D uses an absolute determinant threshold, which treats
## centimeter-scale perpendicular rope segments as parallel.

static func closest_segment_points(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> PackedVector3Array:
	var u := b - a
	var v := d - c
	var offset := a - c
	var uu := u.dot(u)
	var vv := v.dot(v)
	var uv := u.dot(v)
	var uw := u.dot(offset)
	var vw := v.dot(offset)
	var s := 0.0
	var t := 0.0
	if uu <= 1e-20:
		t = clampf(vw / vv, 0.0, 1.0) if vv > 1e-20 else 0.0
	elif vv <= 1e-20:
		s = clampf(-uw / uu, 0.0, 1.0)
	else:
		var determinant := uu * vv - uv * uv
		if determinant > 1e-7 * uu * vv:
			s = clampf((uv * vw - uw * vv) / determinant, 0.0, 1.0)
		t = (uv * s + vw) / vv
		if t < 0.0:
			t = 0.0
			s = clampf(-uw / uu, 0.0, 1.0)
		elif t > 1.0:
			t = 1.0
			s = clampf((uv - uw) / uu, 0.0, 1.0)
	return PackedVector3Array([a + u * s, c + v * t])
