@tool
class_name MannequinPart
extends Resource
## One primitive body segment of the mannequin.
##
## A single definition drives both the visual mesh and the collision shape,
## so what the user sees is exactly what the rope will collide with.

enum Primitive { SPHERE, CAPSULE, BOX }

@export var part_name: StringName = &""
@export var primitive: Primitive = Primitive.CAPSULE
@export_range(0.005, 1.0, 0.001, "suffix:m") var radius: float = 0.05
## Total capsule height including both hemispherical caps (Godot convention).
@export_range(0.01, 2.0, 0.001, "suffix:m") var height: float = 0.3
@export var box_size: Vector3 = Vector3(0.1, 0.1, 0.1)
@export var position: Vector3 = Vector3.ZERO
@export var rotation_degrees: Vector3 = Vector3.ZERO


func is_valid() -> bool:
	match primitive:
		Primitive.SPHERE:
			return radius > 0.0
		Primitive.CAPSULE:
			return radius > 0.0 and height >= radius * 2.0
		_:
			return box_size.x > 0.0 and box_size.y > 0.0 and box_size.z > 0.0


func get_local_transform() -> Transform3D:
	var euler := Vector3(
		deg_to_rad(rotation_degrees.x),
		deg_to_rad(rotation_degrees.y),
		deg_to_rad(rotation_degrees.z),
	)
	return Transform3D(Basis.from_euler(euler), position)


func create_mesh() -> PrimitiveMesh:
	match primitive:
		Primitive.SPHERE:
			var sphere := SphereMesh.new()
			sphere.radius = radius
			sphere.height = radius * 2.0
			sphere.radial_segments = 32
			sphere.rings = 16
			return sphere
		Primitive.CAPSULE:
			var capsule := CapsuleMesh.new()
			capsule.radius = radius
			capsule.height = height
			capsule.radial_segments = 32
			capsule.rings = 8
			return capsule
		_:
			var box := BoxMesh.new()
			box.size = box_size
			return box


func create_shape() -> Shape3D:
	match primitive:
		Primitive.SPHERE:
			var sphere := SphereShape3D.new()
			sphere.radius = radius
			return sphere
		Primitive.CAPSULE:
			var capsule := CapsuleShape3D.new()
			capsule.radius = radius
			capsule.height = height
			return capsule
		_:
			var box := BoxShape3D.new()
			box.size = box_size
			return box
