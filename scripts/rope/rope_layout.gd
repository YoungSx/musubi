class_name RopeLayout
extends RefCounted
## Pure geometry helpers for rope centerlines. Layout functions return
## segment_count + 1 evenly spaced points.

const _FINE_SAMPLES := 256
const _SAG_ITERATIONS := 40


## A rope of the given length hanging between two anchors, approximated by a
## parabola sagging along gravity. When the anchors are at least `length` apart
## the rope is laid straight from `a` toward `b` at its full length instead.
static func hanging(a: Vector3, b: Vector3, length: float, segment_count: int) -> PackedVector3Array:
	var span := b - a
	var span_length := span.length()
	if span_length < 1e-6:
		return straight(a, Vector3.DOWN, length, segment_count)
	var span_dir := span / span_length
	if span_length >= length:
		return straight(a, span_dir, length, segment_count)

	var sag_dir := Vector3.DOWN - span_dir * Vector3.DOWN.dot(span_dir)
	if sag_dir.length_squared() < 1e-8:
		sag_dir = span_dir.cross(Vector3.RIGHT)
		if sag_dir.length_squared() < 1e-8:
			sag_dir = span_dir.cross(Vector3.FORWARD)
	sag_dir = sag_dir.normalized()

	# Arc length grows monotonically with sag depth, so bisection converges.
	var low := 0.0
	var high := length * 0.5
	for i in _SAG_ITERATIONS:
		var mid := (low + high) * 0.5
		if polyline_length(_parabola(a, span, sag_dir, mid)) < length:
			low = mid
		else:
			high = mid
	return resample(_parabola(a, span, sag_dir, (low + high) * 0.5), segment_count)


static func straight(start: Vector3, direction: Vector3, length: float, segment_count: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	points.resize(segment_count + 1)
	var step := direction.normalized() * (length / float(segment_count))
	for i in points.size():
		points[i] = start + step * float(i)
	return points


## Redistributes points evenly by arc length.
static func resample(points: PackedVector3Array, segment_count: int) -> PackedVector3Array:
	var result := PackedVector3Array()
	result.resize(segment_count + 1)
	var total := polyline_length(points)
	var source := 0
	var travelled := 0.0
	for k in result.size():
		var target := total * float(k) / float(segment_count)
		while source < points.size() - 2:
			var piece := points[source].distance_to(points[source + 1])
			if travelled + piece >= target:
				break
			travelled += piece
			source += 1
		var piece_length := points[source].distance_to(points[source + 1])
		var weight := clampf((target - travelled) / piece_length, 0.0, 1.0) if piece_length > 0.0 else 0.0
		result[k] = points[source].lerp(points[source + 1], weight)
	return result


static func polyline_length(points: PackedVector3Array) -> float:
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	return total


static func shoulder_drape(length: float, segment_count: int) -> PackedVector3Array:
	var arch := PackedVector3Array([
		Vector3(-0.30, 1.15, 0.1), Vector3(-0.23, 1.48, 0.03),
		Vector3(-0.1, 1.48, -0.08), Vector3(0, 1.48, -0.09),
		Vector3(0.1, 1.48, -0.08), Vector3(0.23, 1.48, 0.03), Vector3(0.30, 1.15, 0.1)])
	var tail := maxf((length - polyline_length(arch)) * 0.5, 0.02)
	if tail > 1.12:
		var left := _ground_tail(arch[0],tail,-1)
		left.reverse()
		left.append_array(arch)
		left.append_array(_ground_tail(arch[-1],tail,1))
		return resample(left,segment_count)
	var points := PackedVector3Array([arch[0] + Vector3.DOWN * tail])
	points.append_array(arch)
	points.append(arch[-1] + Vector3.DOWN * tail)
	return resample(points, segment_count)


static func _ground_tail(origin: Vector3,length: float,side: float) -> PackedVector3Array:
	var floor_y := 0.015
	var slack := maxf(0,length-(origin.y-floor_y))
	var points := PackedVector3Array([origin,Vector3(origin.x,floor_y,origin.z)])
	var radius := 0.45
	for i in range(1,65):
		var angle := slack/radius*float(i)/64.0
		points.append(Vector3(origin.x+side*radius*sin(angle),floor_y,origin.z+radius*(1-cos(angle))))
	return points


static func floor_curve(length: float, segment_count: int, radius: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in segment_count + 1:
		var angle := PI * float(i) / segment_count
		points.append(Vector3(-cos(angle) * length / PI, radius + 0.002, 0.45 + sin(angle) * length / PI))
	return points


static func _parabola(a: Vector3, span: Vector3, sag_dir: Vector3, depth: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	points.resize(_FINE_SAMPLES + 1)
	for i in points.size():
		var t := float(i) / float(_FINE_SAMPLES)
		points[i] = a + span * t + sag_dir * (4.0 * depth * t * (1.0 - t))
	return points
