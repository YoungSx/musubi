class_name DesktopShortcuts
extends Node
## Keyboard intent mapped to semantic actions.
## Registers actions with Godot's InputMap and routes unhandled key events.

signal action_requested(action: StringName)

const ACTIONS: Array[StringName] = [
	&"undo",
	&"redo",
	&"save",
	&"load",
	&"reset",
	&"focus",
	&"back",
	&"pause",
	&"cancel",
	&"fullscreen",
	&"report",
]

static var _input_map_registered := false


func _ready() -> void:
	register_input_map()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var action := action_for_key(event as InputEventKey)
	if action != &"":
		action_requested.emit(action)
		get_viewport().set_input_as_handled()


static func register_input_map() -> void:
	if _input_map_registered:
		return
	_input_map_registered = true
	_register_action(&"undo", [
		_make_key(KEY_Z, true, false),
	])
	_register_action(&"redo", [
		_make_key(KEY_Z, true, true),
		_make_key(KEY_Y, true, false),
	])
	_register_action(&"save", [_make_key(KEY_S, true, false)])
	_register_action(&"load", [_make_key(KEY_O, true, false)])
	_register_action(&"reset", [_make_key(KEY_R)])
	_register_action(&"focus", [_make_key(KEY_F)])
	_register_action(&"back", [_make_key(KEY_B)])
	_register_action(&"pause", [_make_key(KEY_SPACE)])
	_register_action(&"cancel", [_make_key(KEY_ESCAPE)])
	_register_action(&"fullscreen", [_make_key(KEY_F11)])
	_register_action(&"report", [_make_key(KEY_F9)])


static func action_for_key(event: InputEventKey) -> StringName:
	var key := event.physical_keycode if event.physical_keycode else event.keycode
	var ctrl := event.ctrl_pressed or event.meta_pressed
	var shift := event.shift_pressed
	var alt := event.alt_pressed
	if alt:
		return &""
	if ctrl:
		if key == KEY_Z:
			return &"redo" if shift else &"undo"
		if key == KEY_Y:
			return &"redo" if not shift else &""
		if not shift:
			if key == KEY_S: return &"save"
			if key == KEY_O: return &"load"
		return &""
	if shift:
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


static func _register_action(action: StringName, events: Array[InputEventKey]) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev in events:
		if not InputMap.action_has_event(action, ev):
			InputMap.action_add_event(action, ev)


static func _make_key(key: Key, ctrl := false, shift := false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.command_or_control_autoremap = ctrl
	ev.shift_pressed = shift
	return ev
