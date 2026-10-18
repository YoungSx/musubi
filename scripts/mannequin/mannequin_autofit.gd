class_name MannequinAutofit
extends RefCounted
## Automated collision proxy generator for 3D mannequin / sculpture models.
##
## Analyzes the visual mesh geometry of arbitrary models and generates an
## analytical collision configuration (MannequinConfig) consisting of bounding
## primitives (plinth, torso, chest, shoulders, neck, head).
##
## Supports:
## 1. Runtime model import: user loads a .glb/.gltf at runtime, and collision is
##    fitted automatically in milliseconds with zero manual configuration.
## 2. Editor generation: Technical artists can generate and inspect .tres resources.

const DEFAULT_SLICE_COUNT := 24


## Fits a MannequinConfig to the visual geometry of the provided node or mesh instance.
static func fit_from_node(visual_root: Node3D, target_height: float = 0.0) -> MannequinConfig:
	if visual_root == null:
		return null

	var verts := _collect_vertices(visual_root)
	if verts.is_empty():
		push_warning("MannequinAutofit: No vertices found in visual root.")
		return null

	return fit_from_vertices(verts, target_height)


## Fits a MannequinConfig from a raw array of vertices in mannequin local space.
static func fit_from_vertices(verts: PackedVector3Array, _target_height: float = 0.0) -> MannequinConfig:
	if verts.size() < 4:
		return null

	var aabb := AABB()
	for i in verts.size():
		if i == 0:
			aabb = AABB(verts[i], Vector3.ZERO)
		else:
			aabb = aabb.expand(verts[i])

	var h := aabb.size.y
	var y0 := aabb.position.y

	var slice_stats := func(y_min: float, y_max: float) -> Dictionary:
		var min_x := INF
		var max_x := -INF
		var min_z := INF
		var max_z := -INF
		var count := 0
		var sum_x := 0.0
		var sum_z := 0.0

		for v in verts:
			if v.y >= y_min and v.y <= y_max:
				count += 1
				min_x = minf(min_x, v.x)
				max_x = maxf(max_x, v.x)
				min_z = minf(min_z, v.z)
				max_z = maxf(max_z, v.z)
				sum_x += v.x
				sum_z += v.z

		if count == 0:
			return {
				"center": Vector3(0, (y_min + y_max) * 0.5, 0),
				"radius": 0.1,
				"span_x": 0.1,
				"span_z": 0.1,
				"count": 0
			}

		var cx := sum_x / float(count)
		var cz := sum_z / float(count)
		var max_r := 0.0
		for v in verts:
			if v.y >= y_min and v.y <= y_max:
				var r := Vector2(v.x - cx, v.z - cz).length()
				max_r = maxf(max_r, r)

		return {
			"center": Vector3(cx, (y_min + y_max) * 0.5, cz),
			"radius": max_r,
			"span_x": max_x - min_x,
			"span_z": max_z - min_z,
			"min_x": min_x, "max_x": max_x,
			"min_z": min_z, "max_z": max_z,
			"count": count
		}

	var parts: Array[MannequinPart] = []

	# 1. Base / Plinth (bottom 0% - 11% of height)
	var plinth_stat: Dictionary = slice_stats.call(y0, y0 + h * 0.11)
	var plinth := MannequinPart.new()
	plinth.part_name = &"plinth"
	plinth.primitive = MannequinPart.Primitive.BOX
	var plinth_w: float = maxf(plinth_stat["span_x"], plinth_stat["span_z"])
	var plinth_h: float = maxf(h * 0.11, 0.05)
	plinth.box_size = Vector3(plinth_w, plinth_h, plinth_w)
	plinth.position = Vector3(plinth_stat["center"].x, y0 + plinth_h * 0.5, plinth_stat["center"].z)
	parts.append(plinth)

	# 2. Lower torso / waist transition (11% - 40% of height)
	var torso_stat: Dictionary = slice_stats.call(y0 + h * 0.11, y0 + h * 0.40)
	var torso := MannequinPart.new()
	torso.part_name = &"torso"
	torso.primitive = MannequinPart.Primitive.CAPSULE
	torso.radius = clampf(torso_stat["radius"] * 0.88, 0.18, 0.40)
	torso.height = maxf(h * 0.32, torso.radius * 2.0)
	torso.position = Vector3(torso_stat["center"].x, y0 + h * 0.28, torso_stat["center"].z)
	parts.append(torso)

	# 3. Chest (38% - 65% of height)
	var chest_stat: Dictionary = slice_stats.call(y0 + h * 0.38, y0 + h * 0.65)
	var chest := MannequinPart.new()
	chest.part_name = &"chest"
	chest.primitive = MannequinPart.Primitive.CAPSULE
	chest.radius = clampf(chest_stat["radius"] * 0.82, 0.20, 0.40)
	chest.height = maxf(h * 0.28, chest.radius * 2.0)
	chest.position = Vector3(chest_stat["center"].x, y0 + h * 0.50, chest_stat["center"].z)
	parts.append(chest)

	# 4. Shoulders (lateral span around 50% - 70% of height)
	var shoulder_stat: Dictionary = slice_stats.call(y0 + h * 0.50, y0 + h * 0.70)
	var shoulders := MannequinPart.new()
	shoulders.part_name = &"shoulders"
	shoulders.primitive = MannequinPart.Primitive.CAPSULE
	shoulders.radius = clampf(shoulder_stat["span_z"] * 0.35, 0.18, 0.30)
	shoulders.height = maxf(shoulder_stat["span_x"] * 0.95, shoulders.radius * 2.0)
	shoulders.position = Vector3(shoulder_stat["center"].x, y0 + h * 0.58, shoulder_stat["center"].z)
	shoulders.rotation_degrees = Vector3(0, 0, 90)
	parts.append(shoulders)

	# 5. Neck (65% - 80% of height)
	var neck_stat: Dictionary = slice_stats.call(y0 + h * 0.65, y0 + h * 0.80)
	var neck := MannequinPart.new()
	neck.part_name = &"neck"
	neck.primitive = MannequinPart.Primitive.CAPSULE
	neck.radius = clampf(minf(neck_stat["span_x"], neck_stat["span_z"]) * 0.45, 0.10, 0.22)
	neck.height = maxf(h * 0.16, neck.radius * 2.0)
	neck.position = Vector3(neck_stat["center"].x, y0 + h * 0.72, neck_stat["center"].z)
	parts.append(neck)

	# 6. Head (72% - 100% of height)
	var head_stat: Dictionary = slice_stats.call(y0 + h * 0.72, y0 + h)
	var head := MannequinPart.new()
	head.part_name = &"head"
	head.primitive = MannequinPart.Primitive.CAPSULE
	head.radius = clampf(maxf(head_stat["span_x"], head_stat["span_z"]) * 0.44, 0.15, 0.30)
	head.height = maxf(h * 0.26, head.radius * 2.0)
	head.position = Vector3(head_stat["center"].x, y0 + h * 0.84, head_stat["center"].z)
	head.rotation_degrees = Vector3(8, 0, 0)
	parts.append(head)

	var config := MannequinConfig.new()
	config.parts = parts
	return config


static func _collect_vertices(visual_root: Node3D) -> PackedVector3Array:
	var verts := PackedVector3Array()
	var in_tree := visual_root.is_inside_tree()
	var inv_t := visual_root.global_transform.affine_inverse() if in_tree else Transform3D.IDENTITY

	for child in visual_root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var to_local: Transform3D
		if in_tree and mi.is_inside_tree():
			to_local = inv_t * mi.global_transform
		else:
			to_local = _get_relative_transform(visual_root, mi)
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			if arrays.is_empty():
				continue
			var v_arr: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in v_arr:
				verts.append(to_local * v)

	return verts


static func _get_relative_transform(root: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var curr: Node = node
	while curr != null and curr != root:
		if curr is Node3D:
			t = (curr as Node3D).transform * t
		curr = curr.get_parent()
	return t
