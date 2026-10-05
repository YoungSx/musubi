extends TestCase


func test_debug_toggle_and_selection_feedback_follow_state() -> void:
	var app := add_to_tree(load("res://scenes/main/main.tscn").instantiate()) as AppController
	assert_true(not app.rope_debug.is_debug_enabled(), "debug is off by default")
	app.hud.debug_toggled.emit(true)
	app.rope_debug._process(0.25)
	assert_true(app.rope_debug.is_debug_enabled(), "HUD toggles debug")
	var diagnostics := app.hud.get_node("%Diagnostics") as Label
	assert_true(diagnostics.visible and "FPS" in diagnostics.text, "diagnostics are shown")
	app.rope.begin_drag(24)
	app.rope_debug._process(0.25)
	assert_true("Release" in (app.hud.get_node("%InteractionHint") as Label).text, "grab hint")
	app.rope.end_drag()
	app.rope_debug._process(0.25)
	assert_true("held" in (app.hud.get_node("%InteractionHint") as Label).text, "hold hint")
	app.hud.debug_toggled.emit(false)
	assert_true(not diagnostics.visible, "disabled debug removes diagnostics")
	app.reset()
	app.rope_debug._process(0.25)
	assert_true("Drag rope" in (app.hud.get_node("%InteractionHint") as Label).text, "reset restores hint")
