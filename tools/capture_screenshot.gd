extends SceneTree
## Development tool: renders the main scene and saves a screenshot.
##
## Usage (needs a rendering driver, so not --headless):
##   godot --path . -s res://tools/capture_screenshot.gd -- <output.png> [frames]

const DEFAULT_FRAMES := 30


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("capture_screenshot: missing output path.")
		quit(1)
		return
	var output_path := args[0]
	var frames := int(args[1]) if args.size() > 1 else DEFAULT_FRAMES

	var main_scene_path: String = ProjectSettings.get_setting("application/run/main_scene")
	var scene := load(main_scene_path) as PackedScene
	if scene == null:
		push_error("capture_screenshot: cannot load '%s'." % main_scene_path)
		quit(1)
		return
	root.add_child(scene.instantiate())
	_capture.call_deferred(output_path, frames)


func _capture(output_path: String, frames: int) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var error := image.save_png(output_path)
	if error != OK:
		push_error("capture_screenshot: failed to save '%s' (%s)." % [output_path, error_string(error)])
		quit(1)
		return
	print("capture_screenshot: saved %s (%dx%d)" % [output_path, image.get_width(), image.get_height()])
	quit(0)
