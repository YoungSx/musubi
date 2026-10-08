extends SceneTree
## Portrait twin-stick replay through Godot input dispatch. Every movement, grab
## and release below comes from synthetic touch events on the on-screen sticks,
## not from calling the octopus directly.

var mode: OctopusMode
var octopus: Octopus
var failures := 0
var output := ""

## Stick centres, read from the live controls rather than hardcoded: both sticks
## are JOYSTICK_FIXED about their own centre, so touching anywhere else would
## skew every reported vector and make the release tap lift as a flick.
var move_stick := Vector2.ZERO
var aim_stick := Vector2.ZERO


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	output = OS.get_cmdline_user_args()[0]
	mode = load("res://scenes/main/octopus_play.tscn").instantiate()
	root.add_child(mode)
	ReplayInputGuard.install(self)
	root.min_size = Vector2i.ZERO
	root.size = Vector2i(390, 844)
	root.content_scale_factor = 1.0
	root.content_scale_size = Vector2i(390, 844)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	await _frames(5)
	octopus = mode.octopus
	move_stick = mode.controls.get_stick_origin(&"move")
	aim_stick = mode.controls.get_stick_origin(&"aim")

	_check(octopus.get_contact() == SurfaceWalker.Contact.FLOOR, "the octopus starts adhered to the floor")
	await _capture("octopus-start")

	# Reach from the floor, where the rope hangs well outside the body's own span.
	# This is the only place unbounded reach is observable: once up on the figure
	# the nearest material is closer than the mantle is wide, so a grab there
	# cannot show it however far the arm could actually stretch.
	var simulation := mode.rope.get_simulation()
	await _flick(_aim_toward(_nearest_visible("overhead")))
	await _frames(1)
	_check(octopus.is_holding(), "a flick from the floor grabs material overhead")
	var anchor := simulation.get_grip_position(OctopusGrab.GRIP_ID)
	var span := anchor.distance_to(octopus.get_position_in_world())
	_check(span > octopus.config.mantle_radius * 2.0, "the grab reached %.2f m, past its own body" % span)
	# The arm stretches out over reach_time rather than snapping to its target: it
	# starts short of the material and arrives over later frames. How many frames
	# that takes is the host's business, so the claim is about the order, not a
	# mid-stretch value.
	_check(octopus.get_reach_extension() < 1.0, "the arm starts short of the material at %.2f" % octopus.get_reach_extension())
	_check(octopus.get_reach_tip().distance_to(anchor) > 0.01, "and its tip has not arrived yet")
	var reach_frames := await _await_extended(120)
	_check(octopus.get_reach_extension() >= 1.0, "the arm reaches full extension after %d frames" % reach_frames)
	# Against the carry point, not the grip: a grab this far out is still reeling in
	# at reel_speed, so the grip keeps moving under the arm. Closing on the body is
	# what the extended arm is doing here; the tip holding its material exactly is
	# checked on the figure, where the rope is already at hand.
	_check(octopus.get_reach_tip().distance_to(octopus.get_position_in_world()) < span, "the extended arm has drawn the material inward")
	await _capture("octopus-reach")
	await _tap()
	await _frames(3)
	_check(not octopus.is_holding(), "the long reach is released")

	# Both sticks are live at once: movement continues while the aim stick is held.
	var spawn := octopus.get_position_in_world()
	_touch(0, move_stick, true)
	await _hold_stick(0, move_stick, Vector2(0, -56), 40)
	var walked := octopus.get_position_in_world()
	_check(walked.distance_to(spawn) > 0.1, "stick dispatch walks the body")
	_check(octopus.get_contact() != SurfaceWalker.Contact.AIR, "walking stays adhered")

	# Steer into the figure and climb until the rope is in sight, the way a player
	# climbs only as far as the material they want. Holding to a fixed frame count
	# instead would depend on the stick's exact ramp, and overshoots onto the crown
	# of the head, where the surface is level again and the rope is occluded.
	var climb := Vector2(0, -56)
	var spent := await _climb_until_sighted(0, climb, 420)
	_touch(0, move_stick + climb, false)
	await _frames(2)
	var climbed := octopus.get_position_in_world()
	_check(spent < 420, "the rope came into sight from the figure after %d frames" % spent)
	_check(octopus.get_contact() == SurfaceWalker.Contact.BODY, "the body is held, not the floor")
	_check(climbed.y > 0.25, "the figure was climbed to %.2f m" % climbed.y)
	_check(octopus.get_up().dot(Vector3.UP) < 0.95, "the surface frame tilted with the figure")
	_check(mode.rope.get_collision().get_body_clearance(climbed) > 0.0, "the body stays outside the figure")
	await _capture("octopus-climb")

	# Flick the aim stick: grab along the aimed direction. From up here the aim is
	# mostly depth, so this only lands if the aim cone is measured on the view
	# plane the flick was made on rather than against the full world offset.
	await _flick(_aim_toward(_nearest_visible("from the figure")))
	await _frames(3)
	_check(octopus.is_holding(), "an aim-stick flick grabs the rope")
	_check(simulation.get_grip_count() == 1, "exactly one grip is claimed")
	await _await_extended(120)
	_check(octopus.get_reach_extension() >= 1.0, "the arm reaches full extension")
	# The extended tip holds its material, to within one frame of the grip's own
	# motion. The arm anchors on the grip as it was before the solver ran, and the
	# solver then reels that grip onward, so the residual is exactly how far the
	# grip travelled this frame -- not a fixed length, and not a function of the
	# reach. Measuring that travel in the same frame window keeps the claim
	# independent of the host's frame rate and of how high the climb happened to
	# stop, neither of which this stage controls.
	var before := simulation.get_grip_position(OctopusGrab.GRIP_ID)
	await _frames(1)
	var held := simulation.get_grip_position(OctopusGrab.GRIP_ID)
	var travel := held.distance_to(before)
	var tip_gap := octopus.get_reach_tip().distance_to(held)
	_check(tip_gap <= travel + 0.001, "the arm tip holds the grabbed material: gap %.4f m against %.4f m of grip travel" % [tip_gap, travel])
	await _capture("octopus-grab")

	# Carry it. The grip is the rope's own soft constraint, so length and
	# contacts still apply while the body moves.
	var grip_start := simulation.get_grip_position(OctopusGrab.GRIP_ID)
	var body_start := octopus.get_position_in_world()
	_touch(0, move_stick, true)
	await _hold_stick(0, move_stick, Vector2(0, 56), 150)
	_touch(0, move_stick + Vector2(0, 56), false)
	await _frames(2)
	var grip_now := simulation.get_grip_position(OctopusGrab.GRIP_ID)
	_check(octopus.is_holding(), "the grip survives carrying")
	_check(octopus.get_position_in_world().distance_to(body_start) > 0.1, "the body moved while holding")
	_check(grip_now.distance_to(grip_start) > 0.05, "the rope was carried along")
	# The reel is a pursuit loop, not a setpoint: carry() reads the grip's actual
	# position every frame and asks for that plus one reel step toward the body, so
	# the target can never run ahead of the material it is pulling. What the stage
	# can claim, then, is that the reel always asks inward and that the material
	# tracks what it asks -- not that the material arrives. How far it gets is the
	# rope's call, and this play scene pins no particle, so nothing clamps the
	# target either; the resistance is the material's own weight and contacts.
	var carry_point := octopus.get_carry_point()
	var carry_target := simulation.get_drag_target(OctopusGrab.GRIP_ID)
	_check(carry_target.distance_to(carry_point) < grip_now.distance_to(carry_point),
		"the reel keeps asking the material inward: target %.4f m from the body against the grip's %.4f m" % [carry_target.distance_to(carry_point), grip_now.distance_to(carry_point)])
	_check(grip_now.distance_to(carry_target) < grip_now.distance_to(grip_start),
		"the carried material rides at that target, %.4f m from it after travelling %.4f m" % [grip_now.distance_to(carry_target), grip_now.distance_to(grip_start)])
	# And it gains ground. The reel pulls at reel_speed while the carry point runs
	# away at no more than move_speed, and the reel is the faster of the two, so the
	# gap can only shrink. Only the sign is assertable: how much it shrinks depends
	# on what the material is dragging over, and the grab can start anywhere the arm
	# can reach -- 0.48 m to 0.80 m out across runs, closing to 0.07 m to 0.41 m.
	_check(carry_point.distance_to(grip_now) < carry_point.distance_to(grip_start),
		"carrying gains ground on the body: %.4f m away, from %.4f m at the grab" % [carry_point.distance_to(grip_now), carry_point.distance_to(grip_start)])
	_check(mode.rope.get_simulation().get_max_segment_stretch() < 1.6, "carrying does not tear the rope")
	await _capture("octopus-carry")

	# Tap the aim stick: let go, and the rope keeps simulating.
	await _tap()
	await _frames(3)
	_check(not octopus.is_holding(), "an aim-stick tap releases")
	_check(simulation.get_grip_count() == 0, "the grip is returned")
	_check(not mode.rope.is_held(), "play release keeps the rope simulating")
	var dropped := simulation.get_positions().duplicate()
	await _frames(45)
	_check(simulation.get_positions() != dropped, "the dropped rope continues to move")
	await _capture("octopus-release")

	# The view follows without any camera gesture.
	var camera := mode.camera_rig.get_camera()
	var screen := camera.unproject_position(octopus.get_position_in_world())
	_check(not camera.is_position_behind(octopus.get_position_in_world()), "the body stays in front of the camera")
	_check(Rect2(40, 60, 310, 560).has_point(screen), "the body stays framed at %s" % screen)
	_check(mode.rope.get_collision().get_clearance(camera.global_transform.origin) > 0.0, "the view origin stays out of geometry")

	print("%d failures" % failures)
	quit(1 if failures else 0)


## Screen-space direction from the aim stick toward a world point.
func _aim_toward(point: Vector3) -> Vector2:
	var camera := mode.camera_rig.get_camera()
	var body := camera.unproject_position(octopus.get_eye())
	var target := camera.unproject_position(point)
	var direction := target - body
	return direction.normalized() if direction.length() > 1.0 else Vector2(0, -1)


func _nearest_visible(where: String) -> Vector3:
	var simulation := mode.rope.get_simulation()
	var material := OctopusGrab.pick(mode.rope, octopus.get_eye(), Vector3.ZERO, 1.0)
	_check(material >= 0.0, "visible rope material exists to aim at " + where)
	return simulation.get_point(roundi(maxf(material, 0.0) * (simulation.get_point_count() - 1)))


## Flicks the aim stick along a screen direction: press at the centre, drag out
## past the deadzone, lift there. VirtualJoystick reads that as a flick.
func _flick(aim: Vector2) -> void:
	_touch(1, aim_stick, true)
	await _frames(1)
	_drag(1, aim_stick + aim * 52.0)
	await _frames(1)
	_touch(1, aim_stick + aim * 52.0, false)


## Taps the aim stick: press and lift at the centre, inside the deadzone.
func _tap() -> void:
	_touch(1, aim_stick, true)
	await _frames(1)
	_touch(1, aim_stick, false)


## Waits for the arm to finish stretching, returning the frames it took. The
## stretch runs on reach_time, so waiting on the state rather than a frame count
## keeps the replay independent of the host's frame rate.
func _await_extended(cap: int) -> int:
	for frame in cap:
		if octopus.get_reach_extension() >= 1.0:
			return frame
		await process_frame
	return cap


## Holds the move stick until the body is up on the figure with rope material in
## sight. Returns the frames spent, which stays under the cap when it arrives.
func _climb_until_sighted(id: int, offset: Vector2, cap: int) -> int:
	for frame in cap:
		_drag(id, move_stick + offset)
		await _frames(1)
		if octopus.get_contact() != SurfaceWalker.Contact.BODY or octopus.get_position_in_world().y <= 0.25:
			continue
		if OctopusGrab.pick(mode.rope, octopus.get_eye(), Vector3.ZERO, 1.0) >= 0.0:
			return frame + 1
	return cap


## Holds one stick at an offset for a number of frames.
func _hold_stick(id: int, center: Vector2, offset: Vector2, frames: int) -> void:
	for frame in frames:
		_drag(id, center + offset)
		await _frames(1)


func _touch(id: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.device = ReplayInputGuard.DEVICE
	event.index = id
	event.position = position
	event.pressed = pressed
	Input.parse_input_event(event)


func _drag(id: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.device = ReplayInputGuard.DEVICE
	event.index = id
	event.position = position
	Input.parse_input_event(event)


func _frames(count: int) -> void:
	for i in count: await process_frame


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "capture " + label)


func _check(condition: bool, message: String) -> void:
	print("PASS " if condition else "FAIL ", message)
	if not condition: failures += 1
