class_name ReplayInputGuard
extends Node
## Test-window isolation only. Production input and focus behavior are unchanged.
## Native mouse movement must not alter a synthetic drag, and replay windows
## should not steal focus from the user's other applications.
const DEVICE := 77

static func install(tree: SceneTree) -> void:
	tree.root.unfocusable = true
	tree.root.add_child(ReplayInputGuard.new())

func _input(event: InputEvent) -> void:
	if event.device != DEVICE:
		get_viewport().set_input_as_handled()
