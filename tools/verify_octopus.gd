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
	#
	# Held out first, and inspected before the lift: the grab only happens on
	# release, so if nothing is shown while the stick is out the player is aiming
	# blind. The ring has to be on the rope as drawn, and the lift has to take the
	# material the ring was on -- a preview that can disagree with the grab is
	# worse than none.
	var aim := _aim_toward(_nearest_visible("from the figure"))
	await _hold_aim(aim, 3)
	var indicator := mode.controls.get_aim_indicator()
	_check(indicator.get_state() == AimIndicator.State.LOCKED, "holding the aim stick marks material before any grab")
	var ring := indicator.get_endpoint()
	var ring_gap := _screen_distance_to_rope(ring)
	# Material coordinate, not world position. The claim is that the release takes
	# the material the ring was on, and that material keeps its identity while it
	# falls; its position does not. Within one segment, because the pick is per
	# particle and the rope moves between the preview and the lift.
	var marked_u := octopus.aim_material(aim_direction_of(aim), view_normal())
	_check(not octopus.is_holding(), "and aiming alone grabs nothing")
	# The ring is on the rope, to within how far that material moves on screen in a
	# frame. The mode draws the ring from its own _process while the rope keeps its
	# fixed-step schedule, so the mark is a frame stale by construction and that
	# motion is the floor on any pixel figure here. Measured after the two readings
	# above so they stay in one frame, and at the marked material rather than over
	# the whole rope, so a whipping free end cannot buy slack for a misplaced ring.
	var rope_motion := await _rope_screen_motion(ring)
	_check(ring_gap <= rope_motion, "the ring is drawn on the rope: %.2f px out against %.2f px the material moves per frame" % [ring_gap, rope_motion])
	_lift_aim(aim)
	await _frames(3)
	_check(octopus.is_holding(), "an aim-stick release grabs the rope")
	_check(simulation.get_grip_count() == 1, "exactly one grip is claimed")
	var taken_u := simulation.get_grip_u(OctopusGrab.GRIP_ID)
	var segments := absf(taken_u - marked_u) * float(simulation.get_point_count() - 1)
	_check(segments <= 1.0, "it took the material the ring marked, %.2f segments away" % segments)
	_check(indicator.get_state() == AimIndicator.State.IDLE, "and the marker clears once the grab is made")
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


## World aim direction for a stick vector, through the live camera frame.
func aim_direction_of(stick: Vector2) -> Vector3:
	return OctopusMode.aim_direction(stick, mode.camera_rig.get_camera().global_transform.basis)


## The axis a stick-derived aim carries no information about.
func view_normal() -> Vector3:
	return mode.camera_rig.get_camera().global_transform.basis.z


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


## Pushes the aim stick along a screen direction and lifts there: press at the
## centre, drag out past the deadzone, lift. The lift outside the deadzone is
## what asks for a grab.
func _flick(aim: Vector2) -> void:
	await _hold_aim(aim, 1)
	_lift_aim(aim)


## Pushes the aim stick out and holds it there, without lifting. This is the
## state a player is in while aiming, which is the only time a preview can help.
func _hold_aim(aim: Vector2, frames: int) -> void:
	_touch(1, aim_stick, true)
	await _frames(1)
	for frame in maxi(frames, 1):
		_drag(1, aim_stick + aim * 52.0)
		await _frames(1)


func _lift_aim(aim: Vector2) -> void:
	_touch(1, aim_stick + aim * 52.0, false)


## Taps the aim stick: press and lift at the centre, inside the deadzone, which
## is what asks to let go.
func _tap() -> void:
	_touch(1, aim_stick, true)
	await _frames(1)
	_touch(1, aim_stick, false)


## Screen distance from a canvas point to the nearest projected rope point.
## Measured against the rope's own projection rather than by recomputing the aim,
## which would only confirm the same call was made twice.
func _screen_distance_to_rope(point: Vector2) -> float:
	var index := _nearest_projected_point(point)
	if index < 0:
		return INF
	return point.distance_to(_project_point(index))


## How far the rope point nearest a canvas position travels on screen over one
## frame. This is the resolution any ring-to-rope pixel figure can be held to:
## the material keeps moving after the mark is drawn, so a bound tighter than its
## own motion is measuring the phase of the frame rather than the placement.
func _rope_screen_motion(point: Vector2) -> float:
	var index := _nearest_projected_point(point)
	if index < 0:
		return 0.0
	var before := _project_point(index)
	await _frames(1)
	return _project_point(index).distance_to(before)


## Index of the rope point whose projection is nearest a canvas position, or -1
## when none of them is in front of the camera.
func _nearest_projected_point(point: Vector2) -> int:
	var camera := mode.camera_rig.get_camera()
	var simulation := mode.rope.get_simulation()
	var nearest := INF
	var index := -1
	for i in simulation.get_point_count():
		if camera.is_position_behind(simulation.get_point(i)):
			continue
		var distance := point.distance_to(camera.unproject_position(simulation.get_point(i)))
		if distance < nearest:
			nearest = distance
			index = i
	return index


## Canvas position of a rope point through the live camera.
func _project_point(index: int) -> Vector2:
	return mode.camera_rig.get_camera().unproject_position(mode.rope.get_simulation().get_point(index))


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
