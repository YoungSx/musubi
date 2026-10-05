@tool
class_name Mannequin
extends Node3D
## Abstract mannequin assembled from primitive parts.
##
## Its job is to be a clean spatial obstacle for the rope. Visuals and collision
## are generated from the same MannequinConfig so they can never drift apart.
## Generated nodes are not owned by the scene, so they are never saved to disk.

@export var config: MannequinConfig:
	set(value):
		config = value
		_request_rebuild()
@export var material: Material:
	set(value):
		material = value
		_request_rebuild()
@export_flags_3d_physics var collision_layer: int = 1

var _initial_transform := Transform3D.IDENTITY
var _visual_root: Node3D
var _body: StaticBody3D
var _rebuild_pending := false


func _ready() -> void:
	_initial_transform = transform
	_rebuild()


func reset_pose() -> void:
	transform = _initial_transform


## Static body holding one CollisionShape3D per part, in config order.
func get_body() -> StaticBody3D:
	return _body


## Parent of one MeshInstance3D per part, in config order.
func get_visual_root() -> Node3D:
	return _visual_root


func _request_rebuild() -> void:
	if not is_node_ready() or _rebuild_pending:
		return
	_rebuild_pending = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_pending = false
	_free_generated()
	if config == null:
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


func _add_part(part: MannequinPart) -> void:
	var local_transform := part.get_local_transform()

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


func _free_generated() -> void:
	for node: Node in [_visual_root, _body]:
		if node != null:
			remove_child(node)
			node.queue_free()
	_visual_root = null
	_body = null
