@tool
class_name Mannequin
extends Node3D
## Abstract mannequin or imported sculpture model assembled with collision shapes.
##
## Its job is to be a clean spatial obstacle for the rope.
## When visual_scene is provided, it instantiates the high-detail model (e.g. classical bust).
## Otherwise, visuals are generated from config.parts so visuals and collision match.

@export var config: MannequinConfig:
	set(value):
		config = value
		_request_rebuild()
@export var material: Material:
	set(value):
		material = value
		_request_rebuild()
@export var visual_scene: PackedScene:
	set(value):
		visual_scene = value
		_request_rebuild()
@export var visual_scale: Vector3 = Vector3.ONE:
	set(value):
		visual_scale = value
		_request_rebuild()
@export_flags_3d_physics var collision_layer: int = 1

var _initial_transform := Transform3D.IDENTITY
var _visual_root: Node3D
var _body: StaticBody3D
var _rebuild_pending := false


func _ready() -> void:
	_initial_transform = transform
	_rebuild()
	update_configuration_warnings()


func reset_pose() -> void:
	transform = _initial_transform


## Static body holding one CollisionShape3D per part, in config order.
func get_body() -> StaticBody3D:
	return _body


## Parent of the visual mesh(es).
func get_visual_root() -> Node3D:
	return _visual_root


## Computes combined AABB of all visual meshes in local space of this mannequin.
func get_visual_aabb() -> AABB:
	var total_aabb := AABB()
	var has_aabb := false
	if _visual_root != null:
		var inv_t := global_transform.affine_inverse()
		for child in _visual_root.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if mi.mesh != null:
				var mesh_aabb := mi.mesh.get_aabb()
				var local_mesh_aabb := (inv_t * mi.global_transform) * mesh_aabb
				if not has_aabb:
					total_aabb = local_mesh_aabb
					has_aabb = true
				else:
					total_aabb = total_aabb.merge(local_mesh_aabb)
	return total_aabb


## Computes combined AABB of all collision shapes in local space of this mannequin.
func get_collision_aabb() -> AABB:
	var total_aabb := AABB()
	var has_aabb := false
	if _body != null:
		var inv_t := global_transform.affine_inverse()
		for child in _body.find_children("*", "CollisionShape3D", true, false):
			var cs := child as CollisionShape3D
			if cs.shape != null:
				var shape_aabb := _get_shape_aabb(cs.shape)
				var local_shape_aabb := (inv_t * cs.global_transform) * shape_aabb
				if not has_aabb:
					total_aabb = local_shape_aabb
					has_aabb = true
				else:
					total_aabb = total_aabb.merge(local_shape_aabb)
	return total_aabb


## Returns bounding mismatch metrics between visual mesh and collision shapes.
func get_visual_collision_mismatch() -> Dictionary:
	var visual_aabb := get_visual_aabb()
	var collision_aabb := get_collision_aabb()
	var height_diff := absf(visual_aabb.size.y - collision_aabb.size.y)
	var center_diff := visual_aabb.get_center().distance_to(collision_aabb.get_center())
	var has_visual := visual_aabb.size.length_squared() > 0.0001
	var has_collision := collision_aabb.size.length_squared() > 0.0001
	var is_aligned := (not has_visual or not has_collision) or (height_diff <= 0.15 and center_diff <= 0.15)
	return {
		"visual_aabb": visual_aabb,
		"collision_aabb": collision_aabb,
		"height_diff": height_diff,
		"center_diff": center_diff,
		"is_aligned": is_aligned
	}


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if config == null:
		warnings.append("Missing MannequinConfig resource.")
		return warnings
	if visual_scene != null:
		var mismatch := get_visual_collision_mismatch()
		if not mismatch["is_aligned"]:
			warnings.append(
				"Visual mesh bounds differ from collision bounds (height diff: %.2fm, center diff: %.2fm). Adjust collision parts or visual_scale to avoid penetration/floating." % [
					mismatch["height_diff"],
					mismatch["center_diff"]
				]
			)
	return warnings


static func _get_shape_aabb(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		return AABB(-size * 0.5, size)
	elif shape is SphereShape3D:
		var r := (shape as SphereShape3D).radius
		return AABB(Vector3(-r, -r, -r), Vector3(r, r, r) * 2.0)
	elif shape is CapsuleShape3D:
		var r := (shape as CapsuleShape3D).radius
		var h := (shape as CapsuleShape3D).height
		return AABB(Vector3(-r, -h * 0.5, -r), Vector3(r * 2.0, h, r * 2.0))
	return AABB()


func _request_rebuild() -> void:
	if not is_node_ready() or _rebuild_pending:
		return
	_rebuild_pending = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_pending = false
	_free_generated()
	if config == null:
		update_configuration_warnings()
		return

	_visual_root = Node3D.new()
	_visual_root.name = "Visuals"
	add_child(_visual_root)

	_body = StaticBody3D.new()
	_body.name = "Collision"
	_body.collision_layer = collision_layer
	_body.collision_mask = 0
	add_child(_body)

	for part in config.parts:
		if part == null or not part.is_valid():
			push_warning("Mannequin: skipping invalid part '%s'." % (part.part_name if part else &"<null>"))
			continue
		_add_part(part)

	if visual_scene != null:
		_add_custom_visual()

	update_configuration_warnings()


func _add_part(part: MannequinPart) -> void:
	var local_transform := part.get_local_transform()

	if visual_scene == null:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = String(part.part_name)
		mesh_instance.mesh = part.create_mesh()
		mesh_instance.material_override = material
		mesh_instance.transform = local_transform
		_visual_root.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	collision.name = String(part.part_name)
	collision.shape = part.create_shape()
	collision.transform = local_transform
	_body.add_child(collision)


func _add_custom_visual() -> void:
	var instance := visual_scene.instantiate() as Node3D
	instance.name = "Sculpt"
	instance.scale = visual_scale
	if material != null:
		for mi in instance.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = material
	_visual_root.add_child(instance)


func _free_generated() -> void:
	for node: Node in [_visual_root, _body]:
		if is_instance_valid(node):
			if node.get_parent() == self:
				remove_child(node)
			node.queue_free()
	_visual_root = null
	_body = null
