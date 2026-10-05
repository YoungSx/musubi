class_name Hud
extends CanvasLayer
## Minimal presentation layer. Emits user intents only; it never reaches into
## the camera, mannequin or simulation directly.

signal reset_requested

@onready var _reset_button: Button = %ResetButton
@onready var _safe_area: MarginContainer = %SafeArea

var _base_margins: Dictionary[StringName, int] = {}


func _ready() -> void:
	_reset_button.pressed.connect(reset_requested.emit)
	for side: StringName in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]:
		_base_margins[side] = _safe_area.get_theme_constant(side)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()


## Keeps the UI clear of notches and home indicators. Display safe-area insets
## are in window pixels, so they are scaled into canvas units first.
func _apply_safe_area() -> void:
	var window_size := Vector2(DisplayServer.window_get_size())
	if window_size.x <= 0.0 or window_size.y <= 0.0:
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
