class_name TestCase
extends RefCounted
## Base class for tests run by tests/run_tests.gd.

const EPSILON := 1e-4

var tree: SceneTree
var failures: Array[String] = []
var _owned_nodes: Array[Node] = []


## Adds a node to the scene tree for the duration of one test.
func add_to_tree(node: Node) -> Node:
	tree.root.add_child(node)
	_owned_nodes.append(node)
	return node


func cleanup() -> void:
	for node in _owned_nodes:
		if is_instance_valid(node):
			node.free()
	_owned_nodes.clear()


func assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s (expected %s, got %s)" % [message, expected, actual])


func assert_near(actual: float, expected: float, message: String, tolerance := EPSILON) -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s (expected %f, got %f)" % [message, expected, actual])


func assert_vec3_near(actual: Vector3, expected: Vector3, message: String, tolerance := EPSILON) -> void:
	if actual.distance_to(expected) > tolerance:
		failures.append("%s (expected %s, got %s)" % [message, expected, actual])
