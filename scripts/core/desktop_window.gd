class_name DesktopWindow
extends Node
## Native window policy stays outside simulation, camera and touch handling.


func _ready() -> void:
	if not OS.has_feature("pc") or DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	window.min_size = Vector2i(960, 640)
	window.title = "Musubi · " + str(ProjectSettings.get_setting("application/config/version", "dev"))
	window.dpi_changed.connect(_apply_dpi)
	_apply_dpi()


func _apply_dpi() -> void:
	var dpi := DisplayServer.screen_get_dpi(get_window().current_screen)
	get_window().content_scale_factor = clampf(float(dpi) / 96.0, 1.0, 2.5)
