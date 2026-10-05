class_name Hud
extends CanvasLayer
## Minimal presentation layer. Emits user intents only; it never reaches into
## the camera, mannequin or simulation directly.

signal reset_requested
signal debug_toggled(enabled: bool)
signal action_requested(action: StringName)
signal save_requested(path: String)
signal load_requested(path: String)

@onready var _reset_button: Button = %ResetButton
@onready var _safe_area: MarginContainer = %SafeArea

var _base_margins: Dictionary[StringName, int] = {}
var _file_dialog: FileDialog


func _ready() -> void:
	_reset_button.pressed.connect(reset_requested.emit)
	%DebugButton.visible = OS.is_debug_build()
	%DebugButton.toggled.connect(debug_toggled.emit)
	%SaveButton.pressed.connect(func(): action_requested.emit(&"save"))
	%LoadButton.pressed.connect(func(): action_requested.emit(&"load"))
	for side: StringName in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]:
		_base_margins[side] = _safe_area.get_theme_constant(side)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


func set_diagnostics(text: String) -> void:
	%Diagnostics.text = text
	%Diagnostics.visible = not text.is_empty()


func set_interaction_hint(text: String) -> void:
	%InteractionHint.text = text


func set_status(text: String) -> void:
	%Status.text = text
	%Status.tooltip_text = text


func show_file_dialog(saving: bool, last_path: String = "") -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.filters = PackedStringArray(["*.musubi : Musubi creation"])
		_file_dialog.file_selected.connect(_file_selected)
		add_child(_file_dialog)
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if saving else FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.title = "Save creation" if saving else "Open creation"
	var directory := ProjectSettings.globalize_path("user://creations")
	DirAccess.make_dir_recursive_absolute(directory)
	_file_dialog.current_dir = last_path.get_base_dir() if not last_path.is_empty() else directory
	_file_dialog.current_file = last_path.get_file() if not last_path.is_empty() else ("Untitled.musubi" if saving else "")
	_file_dialog.popup_centered_ratio(0.75)


func _file_selected(path: String) -> void:
	if _file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		if path.get_extension().to_lower() != "musubi":
			path += ".musubi"
		save_requested.emit(path)
	else:
		load_requested.emit(path)


## Keeps the UI clear of notches and home indicators. Display safe-area insets
## are in window pixels, so they are scaled into canvas units first.
func _apply_safe_area() -> void:
	var window_size := Vector2(DisplayServer.window_get_size())
	if window_size.x <= 0.0 or window_size.y <= 0.0:
		return
	if OS.has_feature("pc"):
		for side: StringName in _base_margins:
			_safe_area.add_theme_constant_override(side, _base_margins[side])
		return
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var window_rect := Rect2(Vector2(DisplayServer.window_get_position()), window_size)
	safe = safe.intersection(window_rect)
	if not safe.has_area():
		safe = window_rect
	var scale := get_viewport().get_visible_rect().size / window_size
	var insets := {
		&"margin_left": (safe.position.x - window_rect.position.x) * scale.x,
		&"margin_top": (safe.position.y - window_rect.position.y) * scale.y,
		&"margin_right": (window_rect.end.x - safe.end.x) * scale.x,
		&"margin_bottom": (window_rect.end.y - safe.end.y) * scale.y,
	}
	for side: StringName in _base_margins:
		_safe_area.add_theme_constant_override(side, _base_margins[side] + roundi(insets[side]))
