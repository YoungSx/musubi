extends TestCase
## What the aim stick tells the player while it is held, and what it does when it
## is let go.
##
## The bug these cover: the stick acted only on release and reported nothing at
## all in between, so holding it looked identical to a stick that was not wired
## up, and a grab that found nothing looked identical to a grab that never fired.


func test_every_lift_is_answered_as_a_grab_or_a_let_go() -> void:
	var controls := _controls()
	var grabs: Array[Vector2] = []
	# Arrays, not an int counter: a lambda captures an integer by value, so
	# incrementing one inside the handler would never be visible out here.
	var releases: Array[bool] = []
	controls.grab_requested.connect(func(aim: Vector2): grabs.append(aim))
	controls.release_requested.connect(func(): releases.append(true))
	var stick: VirtualJoystick = controls.get_node("SafeArea/Layout/AimStick")

	# VirtualJoystick fires flicked on any lift outside the deadzone and tapped
	# only when the finger never moved, so a lift that drifted inside the deadzone
	# fires neither. Driving both intents off released leaves no gesture silent.
	stick.released.emit(Vector2(0.0, -0.8))
	assert_eq(grabs.size(), 1, "a lift away from centre asks for a grab")
	assert_eq(grabs[0], Vector2(0.0, -0.8), "carrying the direction it was lifted at")
	assert_eq(releases.size(), 0, "and asks for no let-go")

	stick.released.emit(Vector2.ZERO)
	assert_eq(releases.size(), 1, "a lift at centre asks to let go")
	assert_eq(grabs.size(), 1, "and asks for no grab")

	# The gesture VirtualJoystick reports as neither flick nor tap: pushed out,
	# returned to centre, lifted. It still has to mean something.
	stick.released.emit(Vector2(0.0, 0.0))
	assert_eq(releases.size(), 2, "a cancelled push still answers as a let-go")


func test_holding_the_stick_marks_the_material_a_release_would_take() -> void:
	var mode := _mode()
	var octopus: Octopus = mode.octopus
	var indicator := mode.controls.get_aim_indicator()
	assert_eq(indicator.get_state(), AimIndicator.State.IDLE, "a centred stick draws nothing")

	# Aim at material the octopus can actually reach, the way a player sweeping the
	# stick finds it: through the camera the player is looking through.
	var camera: Camera3D = mode.camera_rig.get_camera()
	var view := camera.global_transform.basis
	var material := octopus.aim_material(Vector3.ZERO)
	assert_true(material >= 0.0, "the scene has visible material to aim at")
	var target := octopus.get_material_position(material)
	var offset := (target - octopus.get_eye()).normalized()
	var screen := Vector2(view.x.dot(offset), -view.y.dot(offset)).normalized()

	_push_aim(screen)
	mode._process(1.0 / 60.0)
	assert_eq(indicator.get_state(), AimIndicator.State.LOCKED, "pushing the stick at reachable material marks it")

	# The ring is on the rope as the player sees it, checked against the rope's own
	# projected points rather than by recomputing the aim the way the mode did --
	# that would only confirm the same call was made twice.
	var ring := indicator.get_endpoint()
	var nearest_on_screen := INF
	var simulation := mode.rope.get_simulation()
	for i in simulation.get_point_count():
		var point := simulation.get_point(i)
		if not camera.is_position_behind(point):
			nearest_on_screen = minf(nearest_on_screen, ring.distance_to(camera.unproject_position(point)))
	assert_true(nearest_on_screen < 1.0, "the ring sits on the rope on screen, %.2f px from its nearest point" % nearest_on_screen)
	assert_eq(mode._hint_text(), "Release to grab", "and the hint says the release will take it")

	# And releasing takes the material that was marked: the preview runs its own
	# query, so agreeing with what the grab claims is a real claim, not a tautology.
	var marked := octopus.get_material_position(octopus.aim_material(OctopusMode.aim_direction(screen, view), view.z))
	mode.controls.grab_requested.emit(screen)
	assert_true(octopus.is_holding(), "releasing there grabs")
	assert_vec3_near(simulation.get_grip_position(OctopusGrab.GRIP_ID), marked, "and takes the material the ring was on", 0.01)
	_release_aim()


func test_an_aim_with_nothing_in_reach_shows_the_bearing_and_says_so() -> void:
	var mode := _mode()
	var indicator := mode.controls.get_aim_indicator()
	# Straight down: the floor is underfoot, so no rope lies that way.
	_push_aim(Vector2(0.0, 1.0))
	mode._process(1.0 / 60.0)
	assert_eq(indicator.get_state(), AimIndicator.State.SEARCHING, "an aim at nothing still shows where it points")
	assert_eq(mode._hint_text(), "Nothing in reach yet · keep sweeping", "and says nothing is there")
	assert_true(not mode.octopus.is_holding(), "previewing grabs nothing on its own")
	_release_aim()


func test_a_missed_grab_says_so_instead_of_looking_like_a_dead_stick() -> void:
	var mode := _mode()
	var hint: Label = mode.controls.get_node("SafeArea/Layout/Hint")
	mode.controls.grab_requested.emit(Vector2(0.0, 1.0))
	assert_true(not mode.octopus.is_holding(), "the grab missed")
	assert_eq(hint.text, "Nothing in reach that way", "the miss is reported")

	# A notice has to outlive the frame that raised it, or the next frame's steady
	# hint erases it before it can be read.
	mode._process(1.0 / 60.0)
	assert_eq(hint.text, "Nothing in reach that way", "and survives the next frame's steady hint")
	mode.controls._process(OctopusControls.NOTICE_SECONDS)
	assert_eq(hint.text, mode._hint_text(), "then the steady hint returns")


func test_no_target_is_marked_while_already_holding() -> void:
	var mode := _mode()
	var indicator := mode.controls.get_aim_indicator()
	mode.controls.grab_requested.emit(Vector2.ZERO)
	assert_true(mode.octopus.is_holding(), "holding for this case")
	# A push of this stick while holding releases, whichever way it points, so a
	# target would promise a grab the gesture does not perform.
	_push_aim(Vector2(0.0, -1.0))
	mode._process(1.0 / 60.0)
	assert_eq(indicator.get_state(), AimIndicator.State.IDLE, "nothing is marked while holding")
	assert_eq(mode._hint_text(), "Centre the right stick and release to let go", "and the hint names the gesture that lets go")
	_release_aim()


func test_the_indicator_never_swallows_touches_meant_for_the_sticks() -> void:
	var indicator: AimIndicator = add_to_tree(AimIndicator.new())
	assert_eq(indicator.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the overlay passes touches through")
	var controls := _controls()
	assert_eq(controls.get_aim_indicator().mouse_filter, Control.MOUSE_FILTER_IGNORE, "and so does the one in the scene")


func test_a_target_off_the_edge_of_the_screen_still_shows_its_bearing() -> void:
	# The ring marks where the material is, and the camera does not always frame
	# it. Clamping the ring onto the screen would put it somewhere the material is
	# not; leaving it where it belongs keeps the ray, whose visible part still
	# points at it. Drawing is not clipped to the control's own rect, so that part
	# is actually drawn.
	var controls := _controls()
	var indicator := controls.get_aim_indicator()
	var off_screen := Vector2(-64.0, 158.0)
	controls.show_aim_target(Vector2(200.0, 500.0), off_screen)
	assert_eq(indicator.get_state(), AimIndicator.State.LOCKED, "an off-screen target is still a target")
	assert_eq(indicator.get_endpoint(), off_screen, "and the ring stays where the material actually is")


func test_material_position_samples_the_same_point_a_grip_would_take() -> void:
	var rope := add_to_tree(load("res://scenes/rope/rope.tscn").instantiate()) as Rope
	rope.hold_on_release = false
	var simulation := rope.get_simulation()
	var span := float(simulation.get_point_count() - 1)
	for index in [0, 1, simulation.get_point_count() / 3, simulation.get_point_count() - 1]:
		assert_vec3_near(simulation.get_material_position(float(index) / span), simulation.get_point(index),
			"material %d samples its own point" % index, 1e-5)
	# Between points it interpolates, and a grip taken there agrees.
	var u := (float(simulation.get_point_count() / 3) + 0.5) / span
	var sampled := simulation.get_material_position(u)
	assert_true(rope.begin_grip(u, 7), "a grip can be taken at the same coordinate")
	assert_vec3_near(simulation.get_grip_position(7), sampled, "and reports the position the sampler gave", 1e-5)
	assert_vec3_near(simulation.get_material_position(-0.1), Vector3.ZERO, "an out-of-range coordinate samples nowhere")


func _controls() -> OctopusControls:
	return add_to_tree(load("res://scenes/ui/octopus_controls.tscn").instantiate()) as OctopusControls


func _mode() -> OctopusMode:
	var mode := add_to_tree(load("res://scenes/main/octopus_play.tscn").instantiate()) as OctopusMode
	# _process runs the frame explicitly in these cases, so the scene's own
	# processing must not race it.
	mode.set_process(false)
	return mode


## Presses the aim actions the way VirtualJoystick does, so read_aim() reports a
## pushed stick without a touch sequence.
func _push_aim(stick: Vector2) -> void:
	_release_aim()
	if stick.x > 0.0: Input.action_press(&"octopus_aim_right", stick.x)
	elif stick.x < 0.0: Input.action_press(&"octopus_aim_left", -stick.x)
	if stick.y > 0.0: Input.action_press(&"octopus_aim_back", stick.y)
	elif stick.y < 0.0: Input.action_press(&"octopus_aim_forward", -stick.y)


func _release_aim() -> void:
	for action in [&"octopus_aim_left", &"octopus_aim_right", &"octopus_aim_forward", &"octopus_aim_back"]:
		Input.action_release(action)
