class_name ReplayInputGuard
extends Node
## Test-window isolation only. Production input and focus behavior are unchanged.
## Native mouse movement must not alter a synthetic drag, and replay windows
## should not steal focus from the user's other applications.
const DEVICE := 77

static func install(tree: SceneTree) -> void:
	tree.root.unfocusable = true
	tree.root.add_child(ReplayInputGuard.new())
	_isolate_focus(tree.root)

static func _isolate_focus(node: Node) -> void:
	if node is InteractionManager:
		node.cancel_on_focus_loss = false
	for child in node.get_children(): _isolate_focus(child)

func _input(event: InputEvent) -> void:
	if event.device != DEVICE:
		get_viewport().set_input_as_handled()
