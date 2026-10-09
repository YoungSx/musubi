extends TestCase
## Elastic reach geometry. Pure math: no rope, no nodes, no input.


func test_tip_travels_from_the_shoulder_out_to_the_anchor() -> void:
	var arm := _arm()
	var shoulder := Vector3(0.0, 0.1, 0.0)
	var anchor := Vector3(0.9, 0.4, 0.0)
	arm.reach(shoulder, anchor)
	assert_vec3_near(arm.get_tip(), shoulder, "a new reach starts at the shoulder")
	arm.step(0.09)
	var halfway := arm.get_tip()
	assert_true(halfway.distance_to(shoulder) > 0.01, "the tip leaves the body")
	assert_true(halfway.distance_to(anchor) > 0.01, "and has not arrived yet")
	arm.step(0.2)
	assert_vec3_near(arm.get_tip(), anchor, "a finished reach lands exactly on the anchor")
	assert_true(arm.is_extended(), "and reports holding")


func test_reach_is_not_limited_by_distance() -> void:
	var arm := _arm()
	var far := Vector3(0.0, 0.0, 6.0)
	arm.reach(Vector3.ZERO, far)
	arm.step(1.0)
	assert_vec3_near(arm.get_tip(), far, "an arbitrarily distant anchor is still reached")


func test_holding_tracks_both_ends() -> void:
	var arm := _arm()
	arm.reach(Vector3.ZERO, Vector3(0.5, 0.0, 0.0))
	arm.step(1.0)
	arm.hold(Vector3(0.1, 0.2, 0.0), Vector3(0.3, 0.2, 0.0))
	assert_vec3_near(arm.get_tip(), Vector3(0.3, 0.2, 0.0), "the tip stays on the carried material")
	var curve := arm.get_curve(Vector3.UP, 5)
	assert_vec3_near(curve[0], Vector3(0.1, 0.2, 0.0), "the curve starts at the new shoulder")
	assert_vec3_near(curve[4], Vector3(0.3, 0.2, 0.0), "and ends at the tip")


func test_release_retracts_and_then_goes_idle() -> void:
	var arm := _arm()
	arm.reach(Vector3.ZERO, Vector3(0.4, 0.0, 0.0))
	arm.step(1.0)
	arm.release(Vector3.ZERO)
	assert_true(arm.is_active(), "retraction is still drawn")
	arm.step(0.06)
	assert_true(arm.get_extension() < 1.0 and arm.get_extension() > 0.0, "retraction is gradual")
	arm.step(1.0)
	assert_true(not arm.is_active(), "a finished retraction stops drawing")
	assert_vec3_near(arm.get_tip(), Vector3.ZERO, "and the tip is back at the body")


func test_curve_bows_away_from_the_surface_and_tightens_under_load() -> void:
	var arm := _arm()
	var shoulder := Vector3.ZERO
	var anchor := Vector3(1.0, 0.0, 0.0)
	arm.reach(shoulder, anchor)
	arm.step(0.09)
	var reaching := arm.get_curve(Vector3.UP, 7)
	assert_true(reaching[3].y > 0.0, "a relaxed arm bows along the surface normal")
	var slack := _bow(reaching)
	arm.step(1.0)
	var holding := arm.get_curve(Vector3.UP, 7)
	assert_true(_bow(holding) < slack, "a loaded arm is straighter than a slack one, relative to its span")
	assert_eq(holding.size(), 7, "sample count is honored")
	for point in holding:
		assert_true(point.is_finite(), "curve points are finite")


## A taut hold is straighter still than a merely extended one, because the hold
## is nearly rigid and a slack curve would contradict it -- but not straight, so
## the arm still reads as tissue.
func test_a_taut_hold_is_straighter_than_an_extended_but_slack_one() -> void:
	var arm := _arm()
	var shoulder := Vector3.ZERO
	var anchor := Vector3(0.4, 0.0, 0.0)
	arm.reach(shoulder, anchor)
	arm.step(1.0)
	arm.hold(shoulder, anchor, false)
	var slack := _bow(arm.get_curve(Vector3.UP, 9))
	arm.hold(shoulder, anchor, true)
	var taut := _bow(arm.get_curve(Vector3.UP, 9))
	assert_true(taut < slack, "a taut arm is straighter: bow %.4f of span against %.4f" % [taut, slack])
	assert_true(taut > 0.0, "but not a straight rod: bow %.4f of span" % taut)
	# Reaching again drops the load, so the bow comes back.
	arm.reach(shoulder, anchor)
	arm.step(1.0)
	assert_near(_bow(arm.get_curve(Vector3.UP, 9)), slack, "a new reach is slack again", 1e-6)


## Peak deviation from the straight shoulder-to-tip line, as a fraction of span.
static func _bow(curve: PackedVector3Array) -> float:
	var span := curve[0].distance_to(curve[curve.size() - 1])
	if span <= 0.0:
		return 0.0
	var peak := 0.0
	for i in curve.size():
		peak = maxf(peak, curve[i].distance_to(curve[0].lerp(curve[curve.size() - 1], float(i) / float(curve.size() - 1))))
	return peak / span


func test_zero_length_span_is_stable() -> void:
	var arm := _arm()
	arm.reach(Vector3.ONE, Vector3.ONE)
	arm.step(0.5)
	for point in arm.get_curve(Vector3.UP, 4):
		assert_vec3_near(point, Vector3.ONE, "a degenerate span collapses to a point")


func _arm() -> OctopusArm:
	var config := OctopusConfig.new()
	config.reach_time = 0.18
	config.retract_time = 0.12
	config.arm_bow = 0.22
	config.taut_arm_bow = 0.12
	var arm := OctopusArm.new()
	arm.configure(config)
	return arm
