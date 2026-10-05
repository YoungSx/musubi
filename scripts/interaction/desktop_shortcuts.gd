class_name DesktopShortcuts
extends Node
## Keyboard intent only; the application owns each action's effects.

signal action_requested(action: StringName)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var action := action_for_key(event)
	if action != &"":
		action_requested.emit(action)
		get_viewport().set_input_as_handled()


static func action_for_key(event: InputEventKey) -> StringName:
	var key := event.physical_keycode if event.physical_keycode else event.keycode
	if event.ctrl_pressed or event.meta_pressed:
		return &"save" if key == KEY_S else (&"load" if key == KEY_O else &"")
	if event.alt_pressed or event.shift_pressed:
		return &""
	match key:
		KEY_R: return &"reset"
		KEY_F: return &"focus"
		KEY_B: return &"back"
		KEY_SPACE: return &"pause"
		KEY_ESCAPE: return &"cancel"
		KEY_F11: return &"fullscreen"
		KEY_F9: return &"report"
	return &""
