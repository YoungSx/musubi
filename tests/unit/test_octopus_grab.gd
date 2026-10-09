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


## The draw-in is bounded, and it ends. Its duration is the one the reel rate
## states, so the bound is the mechanism's own arithmetic rather than a fitted
## frame count.
func test_the_draw_in_finishes_in_the_time_the_reel_rate_states() -> void:
	var rope := _rope()
	var grab := _grab(rope)
	var origin := Vector3(0.0, 0.3, 0.6)
	assert_true(grab.grab(origin, Vector3.ZERO), "grab for the draw-in test")
	var goal := origin + Vector3.UP * 0.09
	var span := grab.get_position().distance_to(goal)
	assert_true(not grab.is_drawn_in(), "a fresh grab has not drawn in yet")
	var delta := 1.0 / 60.0
	var frames := 0
	var budget := ceili(span / (0.7 * delta)) + 1
	while not grab.is_drawn_in() and frames < budget * 4:
		grab.carry(goal, delta)
		rope.advance(1.0 / 120.0)
		frames += 1
	assert_true(grab.is_drawn_in(), "the draw-in completes")
	assert_true(frames <= budget, "it takes %d frames against the %d the %.2f m span needs at reel_speed" % [frames, budget, span])
	assert_vec3_near(grab.get_carry_target(), goal, "and then asks for the carry point exactly")


## The point of the change. A body walking away from its own grip must not keep
## stretching the arm: once drawn in, the ask is the carry point itself, however
## fast the body moves. Driven faster than `reel_speed`, which is the regime a
## rate-limited pursuit loop cannot hold at all.
func test_a_drawn_in_hold_asks_for_the_body_without_trailing_it() -> void:
	var rope := _rope()
	var grab := _grab(rope)
	var origin := Vector3(0.0, 0.3, 0.6)
	assert_true(grab.grab(origin, Vector3.ZERO), "grab for the rigid carry test")
	var delta := 1.0 / 60.0
	var goal := origin + Vector3.UP * 0.09
	for i in 600:
		grab.carry(goal, delta)
		rope.advance(1.0 / 120.0)
		if grab.is_drawn_in():
			break
	assert_true(grab.is_drawn_in(), "the hold is drawn in before the walk")

	# Retreat at twice the reel rate. A target derived from the material could
	# only ever ask for one reel step, so it would fall behind without bound;
	# the arm's own target cannot fall behind at all. Asserted on the arm's ask:
	# what the rope then does with an ask its material cannot reach is the
	# rope's own clamp, which is not elasticity.
	var retreat := 2.0 * 0.7
	var worst_gap := 0.0
	for i in 180:
		goal += Vector3.FORWARD * (retreat * delta)
		grab.carry(goal, delta)
		rope.advance(1.0 / 120.0)
		worst_gap = maxf(worst_gap, grab.get_carry_target().distance_to(goal))
	assert_near(worst_gap, 0.0, "the ask never trails the body: worst gap %.6f m while retreating at %.2f m/s" % [worst_gap, retreat], 1e-6)


## And the material itself follows, on a rope laid out the way the play scene
## lays it out: draped, with no pinned end, so nothing clamps the ask and what
## is left between the body and its material is the solver's own give.
##
## The bound is the fingertip softness the rope ships with, measured in the same
## walk rather than assumed: the same body motion driven through a default-
## compliance grip is how slack a yielding hold leaves, and the carried hold has
## to beat it. No fitted distance appears.
func test_a_carried_hold_follows_the_body_more_tightly_than_a_fingertip_would() -> void:
	var firm := _walk_and_measure_trailing(0.00002)
	var soft := _walk_and_measure_trailing(-1.0)
	var pursuit := _walk_and_measure_pursuit_trailing()
	assert_true(firm < soft, "the carried hold trails %.4f m against the %.4f m a fingertip-soft grip leaves over the same walk" % [firm, soft])
	assert_true(firm < soft * 0.1, "and it is an order tighter: %.4f m against %.4f m" % [firm, soft])
	assert_true(firm < pursuit * 0.1, "and an order tighter than the pursuit loop it replaced: %.4f m against %.4f m" % [firm, pursuit])
	# The give that remains is small against the carry offset itself, which is the
	# distance the hold is trying to maintain. Anything comparable to it would read
	# as the arm stretching rather than holding.
	assert_true(firm < 0.09 * 0.25, "the remaining give is a fraction of the carry offset: %.4f m against the 0.09 m offset" % firm)


## What remains is the solver's compliance, and it is the arm's only give. The
## bound is the fingertip softness the rope ships with: the carried grip has to
## be firmer than that, which is the claim, and no fitted distance is involved.
func test_the_carried_grip_is_firmer_than_a_fingertip() -> void:
	var rope := _rope()
	var grab := _grab(rope)
	var simulation := rope.get_simulation()
	var origin := Vector3(0.0, 0.3, 0.6)
	assert_true(grab.grab(origin, Vector3.ZERO), "grab for the stiffness test")
	assert_true(simulation.get_grip_compliance(OctopusGrab.GRIP_ID) < rope.config.drag_compliance,
		"the carried grip is stiffer than the rope's fingertip default: %.8f against %.8f" % [simulation.get_grip_compliance(OctopusGrab.GRIP_ID), rope.config.drag_compliance])

	# And the stiffness is what the config asked for, not the rope's default.
	assert_near(simulation.get_grip_compliance(OctopusGrab.GRIP_ID), 0.00002, "it runs at carry_compliance", 1e-9)

	# A finger taking its own grip alongside keeps the soft default: the rope
	# holds both claims at once rather than being globally retuned.
	assert_true(rope.begin_grip(0.25, 0), "a finger grips alongside")
	assert_near(simulation.get_grip_compliance(0), rope.config.drag_compliance, "the finger keeps the soft default", 1e-9)
	assert_true(not simulation.set_grip_compliance(777, 0.0001), "an absent grip cannot be tuned")
	assert_true(not simulation.set_grip_compliance(OctopusGrab.GRIP_ID, NAN), "a non-finite compliance is refused")


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


## The play scene's layout: draped over the figure, so neither end is pinned and
## the material rests on collision geometry rather than falling freely. Both
## matter to a carry measurement -- an unpinned rope is what makes the ask
## unclamped, and the geometry is what the carried material drags over.
func _draped_rope() -> Rope:
	var rope := load("res://scenes/rope/rope.tscn").instantiate() as Rope
	rope.initial_layout = Rope.InitialLayout.DRAPED
	rope.hold_on_release = false
	var collision := RopeCollision.new()
	collision.configure(load("res://data/mannequin/default_mannequin.tres"))
	rope.set_collision(collision)
	add_to_tree(rope)
	return rope


## Draws a grip in, then walks the carry point at `move_speed` and reports how
## far the material ends up trailing it. A negative compliance leaves the grip
## at the rope's fingertip default, which is the comparison case.
func _walk_and_measure_trailing(compliance: float) -> float:
	var rope := _draped_rope()
	var grab := _grab(rope)
	var simulation := rope.get_simulation()
	var origin := _carry_origin(rope)
	if not grab.grab(origin, Vector3.ZERO):
		return INF
	simulation.set_grip_compliance(OctopusGrab.GRIP_ID, compliance)
	var delta := 1.0 / 60.0
	var carry := origin + Vector3.UP * 0.09
	for i in 600:
		grab.carry(carry, delta)
		rope.advance(delta)
		if grab.is_drawn_in():
			break
	for i in 120:
		carry += Vector3.FORWARD * (0.55 * delta)
		grab.carry(carry, delta)
		rope.advance(delta)
	return grab.get_position().distance_to(carry)


## The superseded pursuit loop, driven over the identical walk: the target was
## one reel step ahead of where the material actually was, so it could never ask
## for more pull than one step. Kept here as the comparison the change is
## against, since the claim is about what it replaced.
func _walk_and_measure_pursuit_trailing() -> float:
	var rope := _draped_rope()
	var simulation := rope.get_simulation()
	var origin := _carry_origin(rope)
	var material := OctopusGrab.pick(rope, origin, Vector3.ZERO, cos(deg_to_rad(35.0)))
	if material < 0.0 or not rope.begin_grip(material, OctopusGrab.GRIP_ID):
		return INF
	var delta := 1.0 / 60.0
	var carry := origin + Vector3.UP * 0.09
	for i in 600:
		_pursue(rope, carry, delta)
		rope.advance(delta)
		if simulation.get_grip_position(OctopusGrab.GRIP_ID).distance_to(carry) < 0.7 * delta:
			break
	for i in 120:
		carry += Vector3.FORWARD * (0.55 * delta)
		_pursue(rope, carry, delta)
		rope.advance(delta)
	return simulation.get_grip_position(OctopusGrab.GRIP_ID).distance_to(carry)


## A body position with clear line of sight to draped material: out in front of
## the figure rather than under it, since the pick requires visibility and the
## drape lies against geometry.
func _carry_origin(rope: Rope) -> Vector3:
	var simulation := rope.get_simulation()
	var collision := rope.get_collision()
	var best := Vector3.ZERO
	var best_clearance := -INF
	for i in simulation.get_point_count():
		var candidate := simulation.get_point(i) + Vector3(0.0, -0.12, 0.26)
		var clearance := collision.get_clearance(candidate) if collision != null else 1.0
		if clearance > best_clearance and OctopusGrab.pick(rope, candidate, Vector3.ZERO, cos(deg_to_rad(35.0))) >= 0.0:
			best = candidate
			best_clearance = clearance
	return best


func _pursue(rope: Rope, carry: Vector3, delta: float) -> void:
	var current := rope.get_simulation().get_grip_position(OctopusGrab.GRIP_ID)
	rope.update_drag_target(current + (carry - current).limit_length(0.7 * delta), OctopusGrab.GRIP_ID)


func _grab(rope: Rope) -> OctopusGrab:
	var config := OctopusConfig.new()
	config.reel_speed = 0.7
	config.aim_cone_degrees = 35.0
	config.carry_compliance = 0.00002
	var grab := OctopusGrab.new()
	grab.configure(config, rope)
	return grab
