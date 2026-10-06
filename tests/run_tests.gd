extends SceneTree
## Minimal dependency-free test runner.
##
## Usage:
##   godot --headless --path . -s res://tests/run_tests.gd
##
## Every script in TEST_SCRIPTS extends TestCase; each method named test_*
## runs in isolation on a fresh instance. Exit code is non-zero on failure.

const TEST_SCRIPTS: Array[String] = [
	"res://tests/unit/test_gesture_tracker.gd",
	"res://tests/unit/test_camera_rig.gd",
	"res://tests/unit/test_mannequin.gd",
	"res://tests/unit/test_rope_simulation.gd",
	"res://tests/unit/test_rope_renderer.gd",
	"res://tests/unit/test_rope_collision.gd",
	"res://tests/unit/test_rope_geometry.gd",
	"res://tests/unit/test_rope_self_collision.gd",
	"res://tests/unit/test_rope_drag.gd",
	"res://tests/unit/test_rope_interaction.gd",
	"res://tests/unit/test_rope_debug.gd",
	"res://tests/unit/test_rope_state.gd",
	"res://tests/unit/test_desktop_interaction.gd",
	"res://tests/unit/test_performance_recorder.gd",
	"res://tests/unit/test_scene_state.gd",
	"res://tests/unit/test_creation_controls.gd",
	"res://tests/unit/test_rope_history.gd",
	"res://tests/unit/test_play_grip.gd",
	"res://tests/unit/test_pass_assist.gd",
	"res://tests/unit/test_support_constraints.gd",
	"res://tests/unit/test_ground_intent.gd",
	"res://tests/unit/test_surface_intent.gd",
]


func _initialize() -> void:
	# Headless windows otherwise default to 100×100 when desktop stretch is off.
	root.size = Vector2i(1280, 800)
	root.content_scale_size = Vector2i(1280, 800)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	_run.call_deferred()


func _run() -> void:
	var passed := 0
	var failed := 0
	for path in TEST_SCRIPTS:
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			printerr("FAIL  %s: cannot load script" % path)
			failed += 1
			continue
		for method in script.get_script_method_list():
			var method_name: String = method.name
			if not method_name.begins_with("test_"):
				continue
			var test: TestCase = script.new()
			test.tree = self
			await test.call(method_name)
			test.cleanup()
			if test.failures.is_empty():
				passed += 1
				print("PASS  %s::%s" % [path.get_file(), method_name])
			else:
				failed += 1
				for failure in test.failures:
					printerr("FAIL  %s::%s: %s" % [path.get_file(), method_name, failure])
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
