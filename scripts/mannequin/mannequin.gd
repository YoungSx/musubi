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


func reset_pose() -> void:
	transform = _initial_transform


## Static body holding one CollisionShape3D per part, in config order.
func get_body() -> StaticBody3D:
	return _body


## Parent of the visual mesh(es).
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

	if visual_scene != null:
		_add_custom_visual()


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
		if node != null:
			remove_child(node)
			node.queue_free()
	_visual_root = null
	_body = null
