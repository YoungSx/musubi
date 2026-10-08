class_name Hud
extends CanvasLayer
## Minimal presentation layer. Emits user intents only; it never reaches into
## the camera, mannequin or simulation directly.

signal reset_requested
signal debug_toggled(enabled: bool)
signal action_requested(action: StringName)
signal save_requested(path: String)
signal load_requested(path: String)
signal new_rope_requested(length_m: float)

@onready var _reset_button: Button = %ResetButton
@onready var _safe_area: MarginContainer = %SafeArea

var _base_margins: Dictionary[StringName, int] = {}
var _file_dialog: FileDialog
var _play_mode := false
var _advanced_visible := true


func _ready() -> void:
	_reset_button.pressed.connect(reset_requested.emit)
	%DebugButton.visible = OS.is_debug_build()
	%DebugButton.toggled.connect(debug_toggled.emit)
	%SaveButton.pressed.connect(func(): action_requested.emit(&"save"))
	%LoadButton.pressed.connect(func(): action_requested.emit(&"load"))
	%SimulateButton.pressed.connect(func(): action_requested.emit(&"pause"))
	%BackButton.pressed.connect(func(): action_requested.emit(&"back"))
	%UndoButton.pressed.connect(func(): action_requested.emit(&"undo"))
	%RedoButton.pressed.connect(func(): action_requested.emit(&"redo"))
	var menu: PopupMenu = %RopeButton.get_popup()
	menu.add_item("New rope · 1.4 m", 0)
	menu.add_item("New rope · 2.2 m", 1)
	menu.add_item("New rope · 3.0 m", 2)
	menu.add_item("New rope · 6.0 m", 3)
	menu.add_separator()
	menu.add_item("Release A", 10)
	menu.add_item("Release B", 11)
	menu.id_pressed.connect(_rope_menu_selected)
	var play_menu: PopupMenu = %PlayMenu.get_popup()
	play_menu.add_item("Start again", 0)
	play_menu.add_item("Save", 1)
	play_menu.add_item("Open", 2)
	play_menu.add_item("Lay rope on ground", 5)
	play_menu.add_separator("Camera")
	play_menu.add_radio_check_item("Assisted follow", 6)
	play_menu.add_radio_check_item("Free camera", 7)
	set_camera_mode(0)
	play_menu.add_separator()
	play_menu.add_item("Advanced", 3)
	if OS.is_debug_build():
		play_menu.add_item("Debug", 4)
	play_menu.id_pressed.connect(_play_menu_selected)
	_base_margins = MusubiSafeArea.capture(_safe_area)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


func set_diagnostics(text: String) -> void:
	%Diagnostics.text = text
	%Diagnostics.visible = not text.is_empty()


func set_camera_mode(mode: int) -> void:
	var menu: PopupMenu = %PlayMenu.get_popup()
	menu.set_item_checked(menu.get_item_index(6), mode == 0)
	menu.set_item_checked(menu.get_item_index(7), mode == 1)


func _play_menu_selected(id: int) -> void:
	var actions := {0: &"reset", 1: &"save", 2: &"load", 3: &"advanced", 4: &"debug", 5: &"ground", 6: &"camera_assisted", 7: &"camera_free"}
	if actions.has(id): action_requested.emit(actions[id])


func set_interaction_hint(text: String) -> void:
	%InteractionHint.text = text


func set_status(text: String) -> void:
	%Status.text = text
	%Status.tooltip_text = text
	if _play_mode:
		%Status.visible = not text.is_empty()


func set_play_mode(enabled: bool) -> void:
	if enabled != _play_mode:
		_play_mode = enabled
		set_advanced_visible(not enabled)
	%PlayMenu.visible = enabled


func is_advanced_visible() -> bool:
	return _advanced_visible


func set_advanced_visible(enabled: bool) -> void:
	_advanced_visible = enabled
	for path in ["SafeArea/Layout/RopeControls", "SafeArea/Layout/Actions", "SafeArea/Layout/Shortcuts"]:
		get_node(path).visible = enabled
	%InteractionHint.visible = enabled
	%Status.visible = enabled or not %Status.text.is_empty()


func set_simulation_state(held: bool, dragging: bool) -> void:
	%SimulateButton.text = "Continue" if held else "Hold"
	%SimulateButton.disabled = dragging
	%BackButton.disabled = dragging
	%RopeButton.disabled = dragging


func set_history_state(undo_available: bool, redo_available: bool) -> void:
	%UndoButton.disabled = not undo_available
	%RedoButton.disabled = not redo_available


func set_rope_state(length_m: float, start_attached: bool, end_attached: bool) -> void:
	%RopeButton.text = "Rope · %.1f m" % length_m
	%AttachmentState.text = "A %s · B %s" % ["fixed" if start_attached else "free", "fixed" if end_attached else "free"]
	var menu: PopupMenu = %RopeButton.get_popup()
	menu.set_item_text(menu.get_item_index(10), "Release A" if start_attached else "Fix A here")
	menu.set_item_text(menu.get_item_index(11), "Release B" if end_attached else "Fix B here")


func _rope_menu_selected(id: int) -> void:
	if id >= 0 and id <= 3:
		new_rope_requested.emit([1.4, 2.2, 3.0, 6.0][id])
	elif id == 10 or id == 11:
		action_requested.emit(&"attachment_a" if id == 10 else &"attachment_b")


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
	MusubiSafeArea.apply(_safe_area, _base_margins)
