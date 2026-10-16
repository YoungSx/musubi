class_name OctopusSkin
extends MeshInstance3D
## Procedural continuous cartoon tentacle mesh using Godot's native ArrayMesh.
##
## When reaching/holding rope, generates a smooth tapered swept tube that emerges
## seamlessly from the octopus model's tentacle base, featuring a two-tone cartoon
## finish (pastel pink back, soft cream underbelly) and a rounded tip cap.
## When idle, clears surfaces so only the mascot toy's resting tentacles are shown.

@export var radial_segments: int = 12
@export var top_level_arms: bool = true

var _config: OctopusConfig
var _mesh := ArrayMesh.new()
var _surface := []


func _ready() -> void:
	top_level = top_level_arms
	global_transform = Transform3D.IDENTITY
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


func _build_tentacle_mesh(curve: PackedVector3Array) -> void:
	var rings := curve.size()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var root_radius := _config.mantle_radius * 0.28
	var tip_radius := _config.mantle_radius * 0.08
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
		var t := float(i) / float(rings - 1)
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

		var radius := lerpf(root_radius, tip_radius, sqrt(t))
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
	verts.append(tip_center + tip_tangent * tip_radius)
	norms.append(tip_tangent)
	colors.append(pink_color)
	uvs.append(Vector2(0.5, 1.0))
	var tip_idx := verts.size() - 1

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

	_surface[Mesh.ARRAY_VERTEX] = verts
	_surface[Mesh.ARRAY_NORMAL] = norms
	_surface[Mesh.ARRAY_COLOR] = colors
	_surface[Mesh.ARRAY_TEX_UV] = uvs
	_surface[Mesh.ARRAY_INDEX] = indices
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _surface)
	_surface.fill(null)
