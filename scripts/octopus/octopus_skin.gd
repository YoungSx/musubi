class_name OctopusSkin
extends MeshInstance3D
## Procedural continuous mesh skin for the octopus reaching arm.
##
## Constructs an organic 3D tentacle with thick base, tapering shaft,
## hemispherical tip, and two-tone underbelly shading.

@export_range(6, 24, 2) var radial_segments: int = 12
@export_range(1, 4, 1) var subdivisions: int = 2
@export var top_level_arms: bool = true

var _config: OctopusConfig
var _mesh: ArrayMesh
var _surface: Array = []


func _ready() -> void:
	_mesh = ArrayMesh.new()
	mesh = _mesh
	_surface.resize(Mesh.ARRAY_MAX)


func configure(config: OctopusConfig) -> void:
	_config = config
	top_level = top_level_arms
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	_surface.resize(Mesh.ARRAY_MAX)


func update_arms(_body: Transform3D, reach_curve: PackedVector3Array) -> void:
	if _config == null or _mesh == null:
		return
	if reach_curve.size() < 2:
		_mesh.clear_surfaces()
		return
	_build_tentacle_mesh(reach_curve)


func _build_tentacle_mesh(raw_curve: PackedVector3Array) -> void:
	# Subdivide centerline using Godot's cubic interpolation for smooth curvature
	var curve := _subdivide_curve(raw_curve)
	var rings := curve.size()
	if rings < 2:
		_mesh.clear_surfaces()
		return

	# Precompute cumulative arc length along the centerline
	var arc_lengths := PackedFloat32Array()
	arc_lengths.resize(rings)
	arc_lengths[0] = 0.0
	for i in range(1, rings):
		arc_lengths[i] = arc_lengths[i - 1] + curve[i].distance_to(curve[i - 1])
	var total_span: float = arc_lengths[rings - 1]

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	# Proportions calibrated to the pink octopus toy model:
	# - Natural leg base: ~6.0mm radius (12mm diameter)
	# - Elastic main trunk: slender ~2.0-2.6mm radius, thinning slightly with stretch
	# - Tip: ~1.4mm radius (2.8mm diameter)
	var r_base: float = 0.0062
	var r_shaft: float = clampf(0.0035 / sqrt(1.0 + total_span * 2.5), 0.0018, 0.0028)
	var r_tip: float = 0.0014

	var pink_color := Color(0.98, 0.48, 0.61, 1.0)
	var cream_color := Color(1.0, 0.88, 0.90, 1.0)

	var tangent0 := (curve[1] - curve[0]).normalized()
	if tangent0.is_zero_approx():
		tangent0 = Vector3.FORWARD
	var normal := tangent0.cross(Vector3.UP)
	if normal.length_squared() < 1e-6:
		normal = tangent0.cross(Vector3.RIGHT)
	normal = normal.normalized()

	for i in rings:
		var dist: float = arc_lengths[i]
		var t: float = dist / maxf(total_span, 0.001)
		var p := curve[i]

		var tangent: Vector3
		if i == 0:
			tangent = (curve[1] - curve[0]).normalized()
		elif i == rings - 1:
			tangent = (curve[rings - 1] - curve[rings - 2]).normalized()
		else:
			tangent = (curve[i + 1] - curve[i - 1]).normalized()
		if tangent.is_zero_approx():
			tangent = tangent0

		normal = normal.slide(tangent).normalized()
		if normal.is_zero_approx():
			normal = tangent.cross(Vector3.UP).normalized()
		var binormal := tangent.cross(normal).normalized()

		# Root transition: localized to the first ~2cm near the body,
		# so the base does not stretch out unnaturally. The trunk and tip
		# perform all the long-distance elongation.
		var root_blend: float = exp(-dist / 0.015)
		var trunk_radius: float = lerpf(r_shaft, r_tip, t)
		var radius: float = lerpf(trunk_radius, r_base, root_blend)

		for j in radial_segments + 1:
			var angle := TAU * float(j) / float(radial_segments)
			var offset := (normal * cos(angle) + binormal * sin(angle)) * radius
			verts.append(p + offset)
			norms.append(offset.normalized())
			uvs.append(Vector2(float(j) / float(radial_segments), t))
			# Underbelly color (cream) vs upper dorsal color (pink)
			var underbelly := clampf(-sin(angle), 0.0, 1.0)
			colors.append(pink_color.lerp(cream_color, underbelly * 0.85))

	# Hemispherical tip cap
	var tip_center := curve[rings - 1]
	var tip_tangent := (curve[rings - 1] - curve[rings - 2]).normalized()
	verts.append(tip_center + tip_tangent * r_tip)
	norms.append(tip_tangent)
	colors.append(pink_color)
	uvs.append(Vector2(0.5, 1.0))
	var tip_idx := verts.size() - 1

	# Root cap (closing the base ring into the mascot socket)
	var root_center := curve[0] - tangent0 * 0.003
	verts.append(root_center)
	norms.append(-tangent0)
	colors.append(pink_color)
	uvs.append(Vector2(0.5, 0.0))
	var root_idx := verts.size() - 1

	var stride := radial_segments + 1
	for i in rings - 1:
		for j in radial_segments:
			var r0 := i * stride + j
			var r1 := r0 + 1
			var r2 := (i + 1) * stride + j
			var r3 := r2 + 1
			indices.append(r0)
			indices.append(r2)
			indices.append(r1)
			indices.append(r1)
			indices.append(r2)
			indices.append(r3)

	var last_ring_start := (rings - 1) * stride
	for j in radial_segments:
		indices.append(last_ring_start + j)
		indices.append(tip_idx)
		indices.append(last_ring_start + j + 1)

	# Connect root cap to ring 0
	for j in radial_segments:
		indices.append(root_idx)
		indices.append(j + 1)
		indices.append(j)

	_surface[Mesh.ARRAY_VERTEX] = verts
	_surface[Mesh.ARRAY_NORMAL] = norms
	_surface[Mesh.ARRAY_COLOR] = colors
	_surface[Mesh.ARRAY_TEX_UV] = uvs
	_surface[Mesh.ARRAY_INDEX] = indices
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _surface)
	_surface.fill(null)


func _subdivide_curve(raw: PackedVector3Array) -> PackedVector3Array:
	if subdivisions <= 1 or raw.size() < 2:
		return raw
	var last := raw.size() - 1
	var out := PackedVector3Array()
	out.resize(last * subdivisions + 1)
	for i in last:
		var p0 := raw[i]
		var p1 := raw[i + 1]
		var before := raw[i - 1] if i > 0 else p0 * 2.0 - p1
		var after := raw[i + 2] if i + 2 <= last else p1 * 2.0 - p0
		for s in subdivisions:
			var t := float(s) / float(subdivisions)
			out[i * subdivisions + s] = p0.cubic_interpolate(p1, before, after, t)
	out[out.size() - 1] = raw[last]
	return out
