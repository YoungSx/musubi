class_name GroundHand
extends RefCounted
## Ground-plane intent plus bounded over/under clearance. No simulation writes.
var active := false
var _height := 0.0

func begin(point: Vector3, floor_height: float) -> void:
	active = point.y - floor_height < 0.3
	_height = point.y

func resolve(raw: Vector3, points: PackedVector3Array, material_u: float, radius: float,
		floor_height: float, support_held: bool, dt: float) -> Vector3:
	if not active:
		return raw
	var base := floor_height + radius + 0.003
	var desired := base
	var coordinate := material_u * (points.size() - 1)
	if not support_held:
		for i in points.size() - 1:
			if minf(absf(i - coordinate), absf(i + 1 - coordinate)) < 3.0:
				continue
			var a := Vector2(points[i].x, points[i].z)
			var b := Vector2(points[i + 1].x, points[i + 1].z)
			var p := Vector2(raw.x, raw.z)
			var edge := b - a
			var t := clampf((p - a).dot(edge) / maxf(edge.length_squared(), 1e-10), 0.0, 1.0)
			var distance := p.distance_to(a.lerp(b, t))
			var height := lerpf(points[i].y, points[i + 1].y, t)
			# High bights already have room underneath. Low strands need a small lift.
			if distance < radius * 6.0 and height < base + radius * 5.0:
				var influence := clampf((radius * 6.0 - distance) / (radius * 3.0), 0.0, 1.0)
				desired = maxf(desired, lerpf(base, height + radius * 2.2, influence))
	desired = minf(desired, base + 0.18)
	_height = move_toward(_height, desired, maxf(dt, 0.0) * (1.2 if desired > _height else 0.6))
	return Vector3(raw.x, _height, raw.z)
