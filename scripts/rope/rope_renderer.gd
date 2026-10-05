class_name RopeRenderer
extends MeshInstance3D
## Turns a rope centerline into one smooth tube mesh.
##
##   centerline -> Catmull-Rom samples -> parallel-transport frames -> rings
##
## Rendering only: it never touches the simulation. Ends are closed with
## hemispherical caps. One mesh and one draw call regardless of point count.
## Vertices are in world space, so the node is top-level.

@export_range(3, 32, 1) var radial_segments: int = 10
## Centerline samples per rope segment.
@export_range(1, 8, 1) var subdivisions: int = 3
## Rings per hemispherical end cap.
@export_range(1, 8, 1) var cap_rings: int = 3

var _mesh := ArrayMesh.new()
var _surface := []
var _centers := PackedVector3Array()
var _tangents := PackedVector3Array()
var _frame_normals := PackedVector3Array()
var _arc := PackedFloat32Array()
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()
var _indexed_rings := -1
var _indexed_radial := -1
var _unit_circle := PackedVector2Array()


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _mesh
	_surface.resize(Mesh.ARRAY_MAX)


func update_mesh(points: PackedVector3Array, radius: float) -> void:
	if points.size() < 2 or radius <= 0.0:
		_mesh.clear_surfaces()
		return
	_sample_centerline(points, radius)
	_build_frames()
	_build_vertices(radius)
	var ring_count := _centers.size() + cap_rings * 2
	if ring_count != _indexed_rings or radial_segments != _indexed_radial:
		_build_indices(ring_count)

	_surface[Mesh.ARRAY_VERTEX] = _vertices
	_surface[Mesh.ARRAY_NORMAL] = _normals
	_surface[Mesh.ARRAY_TEX_UV] = _uvs
	_surface[Mesh.ARRAY_INDEX] = _indices
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _surface)
	# Drop the shared references so next frame's writes don't copy-on-write.
	_surface.fill(null)


func _sample_centerline(points: PackedVector3Array, radius: float) -> void:
	var last := points.size() - 1
	_centers.resize(last * subdivisions + 1)
	for i in last:
		var p0 := points[i]
		var p1 := points[i + 1]
		# Mirrored ghost points keep the curve straight at the ends.
		var before := points[i - 1] if i > 0 else p0 * 2.0 - p1
		var after := points[i + 2] if i + 2 <= last else p1 * 2.0 - p0
		for s in subdivisions:
			var t := float(s) / float(subdivisions)
			var linear := p0.lerp(p1, t)
			var smooth := p0.cubic_interpolate(p1, before, after, t)
			# Unbounded cubic overshoot cuts through nearby strands of a tight knot
			# even when the solver's polyline has valid clearance. Keep cosmetic
			# smoothing within 2.5% of radius of the collision centerline.
			_centers[i * subdivisions + s] = linear + (smooth - linear).limit_length(radius * 0.025)
	_centers[_centers.size() - 1] = points[last]


func _build_frames() -> void:
	var count := _centers.size()
	_tangents.resize(count)
	_frame_normals.resize(count)
	_arc.resize(count)

	var previous_tangent := (_centers[1] - _centers[0]).normalized()
	if previous_tangent.is_zero_approx():
		previous_tangent = Vector3.RIGHT
	_arc[0] = 0.0
	for i in count:
		var ahead := _centers[mini(i + 1, count - 1)]
		var behind := _centers[maxi(i - 1, 0)]
		var tangent := (ahead - behind).normalized()
		_tangents[i] = tangent if not tangent.is_zero_approx() else previous_tangent
		previous_tangent = _tangents[i]
		if i > 0:
			_arc[i] = _arc[i - 1] + _centers[i].distance_to(_centers[i - 1])

	# Parallel transport: carry the normal along with minimal rotation so the
	# tube never twists.
	var normal := _perpendicular(_tangents[0], Vector3.UP)
	for i in count:
		var tangent := _tangents[i]
		normal = _perpendicular(tangent, normal)
		_frame_normals[i] = normal


func _build_vertices(radius: float) -> void:
	if _unit_circle.size() != radial_segments + 1:
		_unit_circle.resize(radial_segments + 1)
		for j in radial_segments + 1:
			var angle := TAU * float(j) / float(radial_segments)
			_unit_circle[j] = Vector2(cos(angle), sin(angle))
	var body := _centers.size()
	var ring_count := body + cap_rings * 2
	var stride := radial_segments + 1
	_vertices.resize(ring_count * stride)
	_normals.resize(ring_count * stride)
	_uvs.resize(ring_count * stride)
	var uv_scale := 1.0 / (TAU * radius)

	for ring in ring_count:
		var sample: int
		var axial: float # Offset along the tangent, in radii. Non-zero on caps.
		var scale: float # Ring radius, in radii.
		if ring < cap_rings:
			var theta := PI * 0.5 * float(ring) / float(cap_rings)
			sample = 0
			axial = -cos(theta)
			scale = sin(theta)
		elif ring >= body + cap_rings:
			var theta := PI * 0.5 * float(ring_count - 1 - ring) / float(cap_rings)
			sample = body - 1
			axial = cos(theta)
			scale = sin(theta)
		else:
			sample = ring - cap_rings
			axial = 0.0
			scale = 1.0

		var tangent := _tangents[sample]
		var normal := _frame_normals[sample]
		var binormal := tangent.cross(normal)
		var center := _centers[sample] + tangent * (axial * radius)
		var v := (_arc[sample] + axial * radius) * uv_scale
		for j in stride:
			var radial := normal * _unit_circle[j].x + binormal * _unit_circle[j].y
			var index := ring * stride + j
			_vertices[index] = center + radial * (scale * radius)
			_normals[index] = radial * scale + tangent * axial
			_uvs[index] = Vector2(float(j) / float(radial_segments), v)


func _build_indices(ring_count: int) -> void:
	var stride := radial_segments + 1
	_indices.resize((ring_count - 1) * radial_segments * 6)
	var cursor := 0
	for ring in ring_count - 1:
		for j in radial_segments:
			var a := ring * stride + j
			var b := a + stride
			# Godot treats clockwise triangles as front faces.
			_indices[cursor] = a
			_indices[cursor + 1] = b
			_indices[cursor + 2] = a + 1
			_indices[cursor + 3] = a + 1
			_indices[cursor + 4] = b
			_indices[cursor + 5] = b + 1
			cursor += 6
	_indexed_rings = ring_count
	_indexed_radial = radial_segments


static func _perpendicular(tangent: Vector3, hint: Vector3) -> Vector3:
	var result := hint - tangent * hint.dot(tangent)
	if result.length_squared() < 1e-8:
		var axis := Vector3.UP if absf(tangent.y) < 0.9 else Vector3.RIGHT
		result = axis - tangent * axis.dot(tangent)
	return result.normalized()
