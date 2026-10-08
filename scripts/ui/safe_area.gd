class_name MusubiSafeArea
extends RefCounted
## Translates the display's safe area into canvas-unit margin overrides.
##
## Phone notches and home indicators are reported in window pixels while the
## UI lives in a stretched canvas, so the insets have to be scaled before they
## mean anything to a MarginContainer. Every on-screen control layer uses this
## one conversion.


## Applies base margins plus the current safe-area insets to the container.
## Desktop keeps its authored margins.
static func apply(container: MarginContainer, base: Dictionary[StringName, int]) -> void:
	var insets := insets_for(container.get_viewport())
	for side: StringName in base:
		container.add_theme_constant_override(side, base[side] + roundi(insets[side]))


## Captures the margins a scene authored, before any override is applied.
static func capture(container: MarginContainer) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	for side: StringName in [&"margin_left", &"margin_top", &"margin_right", &"margin_bottom"]:
		result[side] = container.get_theme_constant(side)
	return result


static func insets_for(viewport: Viewport) -> Dictionary[StringName, float]:
	var empty: Dictionary[StringName, float] = {&"margin_left": 0.0, &"margin_top": 0.0, &"margin_right": 0.0, &"margin_bottom": 0.0}
	var window_size := Vector2(DisplayServer.window_get_size())
	if OS.has_feature("pc") or viewport == null or window_size.x <= 0.0 or window_size.y <= 0.0:
		return empty
	var window_rect := Rect2(Vector2(DisplayServer.window_get_position()), window_size)
	var safe := Rect2(DisplayServer.get_display_safe_area()).intersection(window_rect)
	if not safe.has_area():
		return empty
	var scale := viewport.get_visible_rect().size / window_size
	return {
		&"margin_left": (safe.position.x - window_rect.position.x) * scale.x,
		&"margin_top": (safe.position.y - window_rect.position.y) * scale.y,
		&"margin_right": (window_rect.end.x - safe.end.x) * scale.x,
		&"margin_bottom": (window_rect.end.y - safe.end.y) * scale.y,
	}
