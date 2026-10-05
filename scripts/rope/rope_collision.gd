class_name RopeCollision
extends RefCounted
## Static world-space contacts derived from the mannequin's visual primitives.
## No physics server or scene nodes. Reconfigure after moving the mannequin.
## Supports rigid transforms and uniform positive scale. This is not rope/rope
## collision or continuous collision detection for arbitrarily fast motion.

const SKIN := 0.00005
const MAX_MOTION_SAMPLES := 64

var floor_enabled := true
var floor_height := 0.0
var _parts: Array[Collider] = []


class Collider:
	extends RefCounted
	var primitive: MannequinPart.Primitive
	var transform: Transform3D
	var inverse: Transform3D
	var radius: float
	var half_axis: float
	var half_box: Vector3
	var bounds: AABB

	func clearance(point: Vector3) -> float:
		var local := inverse * point
		if primitive == MannequinPart.Primitive.BOX:
			var q := local.abs() - half_box
			return q.max(Vector3.ZERO).length() + minf(maxf(q.x, maxf(q.y, q.z)), 0.0)
		var closest := Vector3(0.0, clampf(local.y, -half_axis, half_axis), 0.0)
		return local.distance_to(closest) - radius

	func correction(point: Vector3, rope_radius: float) -> Vector3:
		var local := inverse * point
		var offset: Vector3
		if primitive == MannequinPart.Primitive.BOX:
			var closest := local.clamp(-half_box, half_box)
			offset = local - closest
			if offset.length_squared() < 1e-16:
				var to_face := half_box - local.abs()
				var axis := 0 if to_face.x <= to_face.y and to_face.x <= to_face.z else (1 if to_face.y <= to_face.z else 2)
				var normal := Vector3.ZERO
				normal[axis] = -1.0 if local[axis] < 0.0 else 1.0
				return transform.basis * normal * (to_face[axis] + rope_radius)
			var distance := offset.length()
			return transform.basis * offset * (maxf(rope_radius - distance, 0.0) / distance)
		var closest := Vector3(0.0, clampf(local.y, -half_axis, half_axis), 0.0)
		offset = local - closest
		var distance := offset.length()
		var normal := offset / distance if distance > 1e-8 else Vector3.RIGHT
		return transform.basis * normal * maxf(radius + rope_radius - distance, 0.0)

	## Contact at the closest point of the rope segment, including its interior.
	## xyz is a world-space correction; w is the segment interpolation parameter.
	func segment_contact(a: Vector3, b: Vector3, rope_radius: float) -> Vector4:
		var t := 0.0
		var delta := b - a
		if delta.length_squared() < 1e-16:
			return Vector4.ZERO
		if primitive == MannequinPart.Primitive.SPHERE:
			t = clampf((transform.origin - a).dot(delta) / delta.length_squared(), 0.0, 1.0)
		elif primitive == MannequinPart.Primitive.CAPSULE:
			var axis := transform.basis.y * half_axis
			var pair := Geometry3D.get_closest_points_between_segments(a, b, transform.origin - axis, transform.origin + axis)
			t = clampf((pair[0] - a).dot(delta) / delta.length_squared(), 0.0, 1.0)
		else:
			# The box signed distance is convex along a segment. A bounded search
			# covers intersections whose endpoints are both outside the box.
			var lo := 0.0
			var hi := 1.0
			for iteration in 16:
				var left := lerpf(lo, hi, 1.0 / 3.0)
				var right := lerpf(lo, hi, 2.0 / 3.0)
				if clearance(a + delta * left) < clearance(a + delta * right):
					hi = right
				else:
					lo = left
			t = (lo + hi) * 0.5
		var push := correction(a + delta * t, rope_radius)
		return Vector4(push.x, push.y, push.z, t)


func configure(config: MannequinConfig, world_transform := Transform3D.IDENTITY, ground_height := 0.0) -> void:
	_parts.clear()
	floor_height = ground_height
	if config == null:
		return
	var scale := world_transform.basis.get_scale()
	assert(scale.x > 0.0 and is_equal_approx(scale.x, scale.y) and is_equal_approx(scale.x, scale.z), "RopeCollision requires positive uniform mannequin scale.")
	for part in config.parts:
		if part == null or not part.is_valid():
			continue
		var collider := Collider.new()
		collider.primitive = part.primitive
		var combined := world_transform * part.get_local_transform()
		collider.transform = Transform3D(combined.basis.orthonormalized(), combined.origin)
		collider.inverse = collider.transform.affine_inverse()
		collider.radius = part.radius * scale.x
		collider.half_axis = maxf(part.height * 0.5 - part.radius, 0.0) * scale.x if part.primitive == MannequinPart.Primitive.CAPSULE else 0.0
		collider.half_box = part.box_size * scale.x * 0.5
		var extent := collider.half_box if part.primitive == MannequinPart.Primitive.BOX else Vector3(collider.radius, collider.half_axis + collider.radius, collider.radius)
		collider.bounds = collider.transform * AABB(-extent, extent * 2.0)
		_parts.append(collider)


## Signed distance to the nearest obstacle surface, before rope radius.
func get_clearance(point: Vector3) -> float:
	var result := point.y - floor_height if floor_enabled else INF
	for part in _parts:
		result = minf(result, part.clearance(point))
	return result


## Projects a point outside nearby primitives. Multiple passes handle unions
## at shoulders/hips. Deeply impossible overlapping contacts remain bounded.
func project_point(point: Vector3, rope_radius: float) -> Vector3:
	var result := point
	var contact_radius := rope_radius + SKIN
	for pass_index in 3:
		var before := result
		for part in _parts:
			if part.bounds.grow(contact_radius).has_point(result):
				result += part.correction(result, contact_radius)
		if floor_enabled:
			result.y = maxf(result.y, floor_height + contact_radius)
		if result.is_equal_approx(before):
			break
	return result


## Bounded sweep for integration/drag targets. Oversized jumps advance only
## the sampled distance, so an input hitch cannot teleport through a limb.
func constrain_motion(from: Vector3, to: Vector3, rope_radius: float) -> Vector3:
	var start := project_point(from, rope_radius)
	var motion := to - start
	var spacing := maxf(rope_radius * 0.5, 0.001)
	var samples := maxi(1, ceili(motion.length() / spacing))
	if samples > MAX_MOTION_SAMPLES:
		motion *= float(MAX_MOTION_SAMPLES) / float(samples)
		samples = MAX_MOTION_SAMPLES
	for i in range(1, samples + 1):
		var candidate := start + motion * (float(i) / float(samples))
		var projected := project_point(candidate, rope_radius)
		if candidate.distance_squared_to(projected) > 1e-14:
			return projected
	return start + motion


## Mutates only movable particles. Segment corrections are distributed by
## barycentric weights, preserving a pinned endpoint exactly.
func solve(positions: PackedVector3Array, previous: PackedVector3Array, inverse_mass: PackedFloat32Array, rope_radius: float, friction: float) -> void:
	for i in positions.size():
		if inverse_mass[i] > 0.0:
			apply_contact(positions, previous, i, project_point(positions[i], rope_radius) - positions[i], friction)
	for i in positions.size() - 1:
		if inverse_mass[i] + inverse_mass[i + 1] == 0.0:
			continue
		for part in _parts:
			var a := positions[i]
			var b := positions[i + 1]
			var segment_bounds := AABB(a.min(b), (b - a).abs()).grow(rope_radius + SKIN)
			if not segment_bounds.intersects(part.bounds):
				continue
			var contact := part.segment_contact(a, b, rope_radius + SKIN)
			var push := Vector3(contact.x, contact.y, contact.z)
			var w0 := (1.0 - contact.w) * inverse_mass[i]
			var w1 := contact.w * inverse_mass[i + 1]
			var weight := w0 * (1.0 - contact.w) + w1 * contact.w
			if weight < 1e-8 or push.length_squared() < 1e-16:
				continue
			apply_contact(positions, previous, i, push * (w0 / weight), friction)
			apply_contact(positions, previous, i + 1, push * (w1 / weight), friction)


static func apply_contact(positions: PackedVector3Array, previous: PackedVector3Array, index: int, push: Vector3, friction: float) -> void:
	if push.length_squared() < 1e-16:
		return
	var velocity := positions[index] - previous[index]
	var normal := push.normalized()
	var normal_speed := velocity.dot(normal)
	var tangent := velocity - normal * normal_speed
	positions[index] += push
	previous[index] = positions[index] - normal * maxf(normal_speed, 0.0) - tangent * (1.0 - friction)
