extends TestCase
## Aim picking and grip lifecycle. The grip goes through the same rope seam a
## finger uses, so these cases check the aim policy and the carried target, not
## the solver.


func test_aim_cone_selects_material_in_front_and_rejects_material_behind() -> void:
	var rope := _rope()
	var simulation := rope.get_simulation()
	var middle := simulation.get_point(simulation.get_point_count() / 2)
	var origin := middle + Vector3(0.0, -0.25, 0.4)
	var aim := (middle - origin).normalized()
	var toward := OctopusGrab.pick(rope, origin, aim, cos(deg_to_rad(35.0)))
	assert_true(toward >= 0.0, "rope ahead of the aim is picked")
	assert_true(OctopusGrab.pick(rope, origin, -aim, cos(deg_to_rad(35.0))) < 0.0, "nothing is picked behind the aim")
	var picked := simulation.get_point(roundi(toward * (simulation.get_point_count() - 1)))
	assert_true((picked - origin).normalized().dot(aim) >= cos(deg_to_rad(35.0)) - 0.001, "the pick lies inside the cone")


func test_aimless_pick_takes_the_nearest_material() -> void:
	var rope := _rope()
	var origin := Vector3(0.0, 0.3, 0.6)
	var material := OctopusGrab.pick(rope, origin, Vector3.ZERO, cos(deg_to_rad(35.0)))
	assert_true(material >= 0.0, "a tap with no aim still finds rope")
	var simulation := rope.get_simulation()
	var chosen := simulation.get_point(roundi(material * (simulation.get_point_count() - 1)))
	var nearest := INF
	for i in simulation.get_point_count():
		nearest = minf(nearest, origin.distance_to(simulation.get_point(i)))
	assert_near(origin.distance_to(chosen), nearest, "the nearest point wins", 0.03)


func test_grab_claims_a_grip_and_release_returns_it() -> void:
	var rope := _rope()
	var grab := _grab(rope)
	assert_true(grab.grab(Vector3(0.0, 0.3, 0.6), Vector3.ZERO), "a grab in range succeeds")
	assert_true(grab.is_active(), "the grab is held")
	assert_eq(rope.get_simulation().get_grip_count(), 1, "exactly one grip is claimed")
	assert_true(not grab.grab(Vector3(0.0, 0.3, 0.6), Vector3.ZERO), "a second grab is refused while holding")
	grab.release()
	assert_true(not grab.is_active(), "release clears the hold")
	assert_eq(rope.get_simulation().get_grip_count(), 0, "and returns the grip to the rope")
	assert_true(grab.grab(Vector3(0.0, 0.3, 0.6), Vector3.ZERO), "the same grip can be taken again")


func test_grab_fails_when_nothing_is_within_the_aim() -> void:
	var rope := _rope()
	var grab := _grab(rope)
	assert_true(not grab.grab(Vector3(0.0, 0.3, 4.0), Vector3.BACK), "aiming away from the rope grabs nothing")
	assert_true(not grab.is_active(), "a missed grab leaves no grip behind")
	assert_eq(rope.get_simulation().get_grip_count(), 0, "and claims nothing from the rope")


func test_carry_reels_the_held_material_toward_the_body_at_a_bounded_rate() -> void:
	var rope := _rope()
	var grab := _grab(rope)
	var origin := Vector3(0.0, 0.3, 0.6)
	assert_true(grab.grab(origin, Vector3.ZERO), "grab for the carry test")
	var start := grab.get_position()
	var goal := origin + Vector3.UP * 0.09
	var requested := start.distance_to(goal)
	grab.carry(goal, 1.0 / 60.0)
	var target := rope.get_simulation().get_drag_target(OctopusGrab.GRIP_ID)
	assert_true(target.distance_to(start) <= 0.7 / 60.0 + 0.0001, "one frame of reeling is rate limited")
	if requested > 0.7 / 60.0:
		assert_true(target.distance_to(goal) < requested, "and it moves toward the body")
	for i in 240:
		grab.carry(goal, 1.0 / 60.0)
		rope.advance(1.0 / 120.0)
	assert_true(grab.get_position().distance_to(goal) < start.distance_to(goal), "sustained carry closes the distance")


func test_grip_id_cannot_collide_with_touch_grips() -> void:
	var rope := _rope()
	var grab := _grab(rope)
	assert_true(rope.begin_grip(0.25, 0), "a finger takes its own grip")
	assert_true(grab.grab(Vector3(0.0, 0.3, 0.6), Vector3.ZERO), "the octopus grip is independent")
	assert_eq(rope.get_simulation().get_grip_count(), 2, "both grips coexist")
	grab.release()
	assert_eq(rope.get_simulation().get_grip_count(), 1, "releasing one leaves the other")


func test_aim_maps_a_flick_through_the_camera_frame_including_pitch() -> void:
	var view := CameraRig.orbit_basis(deg_to_rad(-25.0), deg_to_rad(18.0))
	assert_true(OctopusMode.aim_direction(Vector2.ZERO, view) == Vector3.ZERO, "a dead stick aims nowhere")
	# Screen y grows downward, so an up-flick must aim above the horizon. A
	# horizon-locked aim cannot reach rope hanging over the body.
	var up_flick := OctopusMode.aim_direction(Vector2(0.0, -1.0), view)
	assert_true(up_flick.dot(Vector3.UP) > 0.2, "an up-flick aims upward, not along the horizon")
	assert_true(absf(up_flick.length() - 1.0) < 0.001, "the aim is a unit direction")
	assert_true(OctopusMode.aim_direction(Vector2(0.0, 1.0), view).dot(Vector3.UP) < -0.2, "a down-flick aims downward")
	var right_flick := OctopusMode.aim_direction(Vector2(1.0, 0.0), view)
	assert_true(right_flick.dot(view.x) > 0.99, "a right-flick aims along the camera's right")
	assert_true(absf(right_flick.dot(Vector3.UP)) < 0.001, "and stays level")


func test_aim_reaches_material_hanging_above_the_body() -> void:
	var rope := _rope()
	var simulation := rope.get_simulation()
	var eye := Vector3(0.0, 0.06, 0.55)
	var target := simulation.get_point(0)
	var view := CameraRig.orbit_basis(deg_to_rad(-25.0), deg_to_rad(18.0))
	# The flick a player makes when the rope is drawn up and to one side.
	var screen := Vector2(view.x.dot((target - eye).normalized()), -view.y.dot((target - eye).normalized()))
	var aim := OctopusMode.aim_direction(screen, view)
	assert_true(OctopusGrab.pick(rope, eye, aim, cos(deg_to_rad(35.0))) >= 0.0, "a flick toward raised material picks it")
	var level := OctopusMode.aim_direction(Vector2(screen.x, 0.0).normalized(), view)
	assert_true(OctopusGrab.pick(rope, eye, level, cos(deg_to_rad(35.0))) < 0.0, "a level aim at the same bearing cannot reach it")


func test_aim_cone_is_measured_on_the_view_plane_not_against_depth() -> void:
	var rope := _rope()
	var simulation := rope.get_simulation()
	var view := CameraRig.orbit_basis(deg_to_rad(-25.0), deg_to_rad(18.0))
	var cone := cos(deg_to_rad(35.0))
	# An eye a few centimetres off the material along the viewing axis, which is
	# where a climbing body sits. Most of that short distance is depth the stick
	# cannot express, so the planar fraction caps the cosine a full-offset test can
	# ever see for this material, and here it caps it below the cone. No cone width
	# would reach it.
	var index := simulation.get_point_count() / 2
	var target := simulation.get_point(index)
	var eye := target - view.z * 0.05 - view.x * 0.012 - view.y * 0.009
	var offset := target - eye
	var planar_fraction := (offset - view.z * offset.dot(view.z)).length() / offset.length()
	assert_true(planar_fraction < cone, "the aimed material is depth-dominated at %.3f" % planar_fraction)
	assert_true(RopeVisibility.is_visible(eye, target, rope.get_collision()), "and it is visible from the eye")

	# The flick a player makes, read off the screen: the aim the stick can produce
	# is the offset's projection onto the view plane.
	var screen := Vector2(view.x.dot(offset.normalized()), -view.y.dot(offset.normalized())).normalized()
	var aim := OctopusMode.aim_direction(screen, view)
	var spatial := OctopusGrab.pick(rope, eye, aim, cone)
	var planar := OctopusGrab.pick(rope, eye, aim, cone, view.z)
	var span := float(simulation.get_point_count() - 1)
	assert_true(absf(spatial * span - index) > 1.0, "measured against the full offset the flick cannot take the material it points at")
	assert_near(planar * span, index, "measured on the view plane it takes exactly that material", 1.0)

	# The plane test still has to reject: a flick the other way must not grab.
	var away := OctopusMode.aim_direction(-screen, view)
	assert_true(OctopusGrab.pick(rope, eye, away, cone, view.z) < 0.0, "a flick away from the material still misses")

	var grab := _grab(rope)
	assert_true(grab.grab(eye, aim, view.z), "the grab goes through with the view axis supplied")
	assert_eq(rope.get_simulation().get_grip_count(), 1, "and claims one grip")


func test_material_centred_on_screen_is_reachable_by_any_flick() -> void:
	var rope := _rope()
	var simulation := rope.get_simulation()
	var view := CameraRig.orbit_basis(deg_to_rad(-25.0), deg_to_rad(18.0))
	var target := simulation.get_point(simulation.get_point_count() / 2)
	# Straight down the viewing axis: the material projects onto the body itself,
	# so there is no screen direction to disagree with.
	var eye := target - view.z * 0.06
	for screen in [Vector2(0.0, -1.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(-1.0, 0.0)]:
		var aim := OctopusMode.aim_direction(screen, view)
		assert_true(OctopusGrab.pick(rope, eye, aim, cos(deg_to_rad(35.0)), view.z) >= 0.0, "a flick %v reaches material centred on the body" % screen)


func _rope() -> Rope:
	var rope := add_to_tree(load("res://scenes/rope/rope.tscn").instantiate()) as Rope
	rope.hold_on_release = false
	return rope


func _grab(rope: Rope) -> OctopusGrab:
	var config := OctopusConfig.new()
	config.reel_speed = 0.7
	config.aim_cone_degrees = 35.0
	var grab := OctopusGrab.new()
	grab.configure(config, rope)
	return grab
