class_name RopeSelfCollision
extends RefCounted
## Capsule-segment contacts within one rope. No nodes or physics-server state.
## Sweep-and-prune bounds include the start of the substep. Bounded conservative
## advancement catches crossings between separated end positions; it is not a
## guarantee for arbitrary deformation, impossible pins or dense knot topology.

const SKIN := 0.00002
const SWEEP_STEPS := 16
var _minimum := PackedVector3Array()
var _maximum := PackedVector3Array()
var _order := PackedInt32Array()
var contacts := 0
var candidates := 0


func solve(p: PackedVector3Array, previous: PackedVector3Array, mass: PackedFloat32Array,
		start: PackedVector3Array, radius: float, rest: float, friction: float) -> void:
	contacts = 0
	candidates = 0
	var count := p.size() - 1
	_minimum.resize(count)
	_maximum.resize(count)
	if _order.size() != count:
		_order.resize(count)
		for i in count:
			_order[i] = i
	var diameter := radius * 2.0 + SKIN
	# Nearby material belongs to the same continuous tube. At fine resolution,
	# exclude enough neighbors to avoid inflating a straight rope against itself.
	var excluded := maxi(1, ceili(diameter / rest))
	for i in count:
		_minimum[i] = p[i].min(p[i + 1]).min(start[i]).min(start[i + 1]) - Vector3.ONE * radius
		_maximum[i] = p[i].max(p[i + 1]).max(start[i]).max(start[i + 1]) + Vector3.ONE * (radius + SKIN)
	# Keep temporal ordering: neighboring substeps barely move the bounds.
	# Index tie-breaking makes the result independent of cache/restore history.
	for i in count:
		var segment := _order[i]
		var k := i
		while k > 0 and (_minimum[_order[k - 1]].x > _minimum[segment].x or (_minimum[_order[k - 1]].x == _minimum[segment].x and _order[k - 1] > segment)):
			_order[k] = _order[k - 1]
			k -= 1
		_order[k] = segment
	for a in count:
		var i := _order[a]
		for b in range(a + 1, count):
			var j := _order[b]
			if _minimum[j].x > _maximum[i].x:
				break
			if absi(i - j) <= excluded:
				continue
			if _minimum[j].y > _maximum[i].y or _maximum[j].y < _minimum[i].y or _minimum[j].z > _maximum[i].z or _maximum[j].z < _minimum[i].z:
				continue
			candidates += 1
			_solve_pair(p, previous, mass, start, mini(i, j), maxi(i, j), diameter, friction)
	# Corrections can create additional pairs outside cached bounds. The next
	# solver iteration rebuilds bounds, rather than trusting a persistent cache.


func _solve_pair(p: PackedVector3Array, previous: PackedVector3Array, mass: PackedFloat32Array,
		start: PackedVector3Array, i: int, j: int, diameter: float, friction: float) -> void:
	var a := p[i]
	var b := p[i + 1]
	var c := p[j]
	var d := p[j + 1]
	var pair := RopeGeometry.closest_segment_points(a, b, c, d)
	var delta := pair[0] - pair[1]
	var s := _parameter(pair[0], a, b)
	var t := _parameter(pair[1], c, d)
	var normal := delta.normalized()
	# Use the first swept contact when present, preserving the incident side.
	var speed := maxf(a.distance_to(start[i]), b.distance_to(start[i + 1])) + maxf(c.distance_to(start[j]), d.distance_to(start[j + 1]))
	if speed > diameter * 0.25:
		var time := 0.0
		for sample in SWEEP_STEPS:
			var sa := start[i].lerp(a, time)
			var sb := start[i + 1].lerp(b, time)
			var sc := start[j].lerp(c, time)
			var sd := start[j + 1].lerp(d, time)
			var swept := RopeGeometry.closest_segment_points(sa, sb, sc, sd)
			var separation := swept[0] - swept[1]
			var gap := separation.length() - diameter
			if gap <= SKIN:
				if separation.length_squared() > 1e-16:
					normal = separation.normalized()
					s = _parameter(swept[0], sa, sb)
					t = _parameter(swept[1], sc, sd)
				break
			time += gap / speed
			if time > 1.0:
				break
	if normal.length_squared() < 0.5:
		var old_delta := start[i].lerp(start[i + 1], s) - start[j].lerp(start[j + 1], t)
		normal = old_delta.normalized()
		if normal.length_squared() < 0.5:
			normal = (b - a).cross(d - c).normalized()
		if normal.length_squared() < 0.5:
			var axis := (b - a).normalized()
			normal = axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
		if normal.length_squared() < 0.5:
			normal = Vector3.UP
	var depth := diameter - (a.lerp(b, s) - c.lerp(d, t)).dot(normal)
	if depth <= 0.0:
		return
	var weights := Vector4(1.0 - s, s, -(1.0 - t), -t)
	var inverse := Vector4(mass[i], mass[i + 1], mass[j], mass[j + 1])
	var denominator := weights.dot(weights * inverse)
	if denominator < 1e-10:
		return
	contacts += 1
	var relative := (a - previous[i]) * weights.x + (b - previous[i + 1]) * weights.y + (c - previous[j]) * weights.z + (d - previous[j + 1]) * weights.w
	var inward := minf(relative.dot(normal), 0.0)
	var tangent := relative - normal * relative.dot(normal)
	# Coulomb-style bound on tangential displacement; no friction in free flight.
	var removed := normal * inward + tangent.limit_length(friction * maxf(depth, -inward))
	for k in 4:
		var index := i + k if k < 2 else j + k - 2
		var factor := weights[k] * inverse[k] / denominator
		var correction := normal * depth * factor
		p[index] += correction
		previous[index] += correction + removed * factor


static func _parameter(point: Vector3, a: Vector3, b: Vector3) -> float:
	var length_squared := a.distance_squared_to(b)
	return clampf((point - a).dot(b - a) / length_squared, 0.0, 1.0) if length_squared > 1e-16 else 0.0
