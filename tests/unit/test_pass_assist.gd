extends TestCase


func test_candidate_requires_real_open_aperture() -> void:
	var provider := RopePassCandidates.new()
	var points := PassFixture.points()
	var candidates := provider.find(points, 0.012, 0.0, null)
	assert_true(not candidates.is_empty(), "local near-contact loop creates a corridor")
	assert_true(provider.find(points, 0.012, 0.5, null).is_empty(), "interior rope grips do not trigger endpoint assistance")
	var twisted := points.duplicate()
	twisted[12].z += 0.2
	assert_true(provider.find(twisted, 0.012, 0.0, null).is_empty(), "screen-like crossing with nonplanar boundary is refused")
	assert_true(provider.find(PassFixture.points(Vector3(0, 1, 0), 0.025), 0.012, 0.0, null).is_empty(), "too-small aperture refused")
	var collision := RopeCollision.new()
	collision.configure(load("res://data/mannequin/default_mannequin.tres"))
	assert_true(provider.find(PassFixture.points(Vector3(0, 1.2, 0)), 0.012, 0.0, collision).is_empty(), "torso blocks otherwise valid rope aperture")
	assert_true(not provider.find(PassFixture.points(Vector3(0.55, 1.1, 0)), 0.012, 0.0, collision).is_empty(), "clear aperture beside full mannequin remains available")


func test_body_blocked_center_can_offer_clear_side_corridors() -> void:
	var collision := RopeCollision.new()
	collision.configure(load("res://data/mannequin/default_mannequin.tres"))
	var points := PassFixture.points(Vector3(0, 1.2, 0), 0.22)
	points[0].z = 0.22
	var candidates := RopePassCandidates.new().find(points, 0.012, 0, collision)
	assert_true(not candidates.is_empty(), "torso-filled center does not erase usable arm/torso side space")
	for candidate in candidates:
		assert_true(candidate.id.z > 0, "blocked center is never chosen")
		assert_true(collision.get_clearance(candidate.center) >= 0.012, "side corridor clears the real mannequin")

func test_torso_ring_discovers_open_space_near_its_boundary() -> void:
	var collision := RopeCollision.new()
	collision.configure(load("res://data/mannequin/default_mannequin.tres"))
	var points := PassFixture.points(Vector3.ZERO,0.2)
	for i in points.size():
		points[i] = Vector3(points[i].x,1.22+points[i].z,points[i].y)
	points[0] = Vector3(0,1.30,0.17)
	var provider := RopePassCandidates.new()
	assert_true(provider.corridor_clear(points,0.012,Vector3(0,1.22,0.17),Vector3.UP,0.048,collision,0),"fixture has an actually clear corridor between torso and ring")
	var candidates := provider.find(points,0.012,0,collision)
	assert_true(not candidates.is_empty(),"a fixed radial sample must not erase the real body-side passage")
	var sampled := RopeLayout.resample(points,96)
	var sampled_candidates := provider.find(sampled,0.012,0,collision)
	var front_found := false
	for candidate in sampled_candidates:
		if absf(candidate.center.x) < 0.04 and candidate.center.z > 0.15: front_found = true
	assert_true(front_found,"a finely sampled incoming tail must not block its own entrance")
	for candidate in candidates:
		assert_true(provider.corridor_clear(points,0.012,candidate.center,candidate.normal,candidate.half_length,collision,0),"every reported passage clears the torso and all standing strands")
	var assist := RopePassAssist.new()
	var raw := points[0]
	assist.begin(raw)
	var active_seen := false
	for i in 65:
		raw.y -= 0.0016
		points[0] = assist.update(raw,points[0],points,0.012,0,Vector3.BACK,collision,1.0/60)
		active_seen = active_seen or assist.state != RopePassAssist.State.FREE
	assert_true(active_seen,"sustained downwards intent chooses the nearby clear entrance among side candidates")
	assert_true(points[0].y < 1.22,"the intended route crosses the ring plane beside the torso")


func test_progress_is_input_driven_and_reversible() -> void:
	var assist := RopePassAssist.new()
	var points := PassFixture.points()
	var raw := points[0]
	assist.begin(raw)
	var direction := Vector3(0.0016, 0, -0.0012)
	var camera_back := Vector3(0.6, 0, 0.8)
	var active_seen := false
	for frame in 50:
		raw += direction
		points[0] = assist.update(raw, points[0], points, 0.012, 0.0, camera_back, null, 1.0 / 60.0)
		active_seen = active_seen or assist.state != RopePassAssist.State.FREE
	assert_true(active_seen, "consistent intent activates assistance")
	assert_true(points[0].z < 0.0, "input crosses the aperture plane")
	var stopped := points[0]
	for frame in 60:
		points[0] = assist.update(raw, points[0], points, 0.012, 0.0, camera_back, null, 1.0 / 60.0)
	assert_eq(points[0], stopped, "stopping input never auto-completes a pass")
	for frame in 10:
		raw -= direction
		points[0] = assist.update(raw, points[0], points, 0.012, 0.0, camera_back, null, 1.0 / 60.0)
	assert_true(points[0].z > stopped.z, "reverse input moves back through the path")

func test_incoming_tail_clearance_is_material_bounded() -> void:
	var provider := RopePassCandidates.new()
	var points := PackedVector3Array([Vector3(0,0.12,0),Vector3(0,0.10,0),Vector3(0,0.08,0),Vector3(0,0.06,0),Vector3(0,0.04,0),Vector3(0.2,0.02,0),Vector3(0.4,0.2,0)])
	for sampled in [points,RopeLayout.resample(points,96)]:
		assert_true(provider.corridor_clear(sampled,0.012,Vector3.ZERO,Vector3.UP,0.048,null,0),"the incoming tail can follow its tip through a corridor at either resolution")
		var reversed: PackedVector3Array = sampled.duplicate()
		reversed.reverse()
		assert_true(provider.corridor_clear(reversed,0.012,Vector3.ZERO,Vector3.UP,0.048,null,reversed.size()-1),"both ends use the same material-length rule")
	points.append_array(PackedVector3Array([Vector3(0.2,-0.1,0),Vector3(0,-0.04,0),Vector3(0,0.04,0)]))
	assert_true(not provider.corridor_clear(points,0.012,Vector3.ZERO,Vector3.UP,0.048,null,0),"a nonlocal return still blocks the corridor")
	var coarse := PackedVector3Array([Vector3(0,0.2,0),Vector3(0,-0.2,0)])
	assert_true(not provider.corridor_clear(coarse,0.012,Vector3.ZERO,Vector3.UP,0.048,null,0),"a coarse first segment is trimmed rather than ignored in full")


func test_collapsed_path_releases_without_a_jump() -> void:
	var assist := RopePassAssist.new()
	var points := PassFixture.points()
	var raw := points[0]
	assist.begin(raw)
	for frame in 12:
		raw += Vector3(0.0016, 0, -0.0012)
		points[0] = assist.update(raw, points[0], points, 0.012, 0.0, Vector3(0.6, 0, 0.8), null, 1.0 / 60.0)
	assert_true(assist.state != RopePassAssist.State.FREE, "fixture acquired corridor")
	var before := points[0]
	points[12].z += 0.2
	var after := assist.update(raw, points[0], points, 0.012, 0.0, Vector3(0.6, 0, 0.8), null, 1.0 / 60.0)
	assert_eq(after, before, "invalidating geometry never teleports the target")
	assert_eq(assist.state, RopePassAssist.State.FREE, "collapsed path exits guidance")
	assert_true(assist.needs_rebase, "free dragging rebases its offset")


func test_view_aligned_and_sideways_intent_do_not_capture() -> void:
	for movement in [Vector3.RIGHT * 0.002, Vector3.UP * 0.002]:
		var assist := RopePassAssist.new()
		var points := PassFixture.points()
		var raw := points[0]
		assist.begin(raw)
		for frame in 20:
			raw += movement
			var target := assist.update(raw, points[0], points, 0.012, 0.0, Vector3.BACK, null, 1.0 / 60.0)
			assert_eq(target, raw, "degenerate screen projection leaves the hand in control")
		assert_eq(assist.state, RopePassAssist.State.FREE, "no hidden depth decision")


func test_crossing_evidence_requires_inside_clearance() -> void:
	var aperture := RopePassCandidates.new().find(PassFixture.points(), 0.012, 0, null)[0]
	var center: Vector3 = aperture.center
	var normal: Vector3 = aperture.normal
	assert_true(RopePassCandidates.crosses_aperture(center + normal * 0.1, center - normal * 0.1, aperture, 0.012), "actual opening crossing accepted")
	var outside := center + Vector3.RIGHT * 0.4
	assert_true(not RopePassCandidates.crosses_aperture(outside + normal * 0.1, outside - normal * 0.1, aperture, 0.012), "moving behind a plane outside its opening is not a pass")
	assert_true(not RopePassCandidates.crosses_aperture(center + normal * 0.1, center + normal * 0.01, aperture, 0.012), "approaching without crossing is not a pass")


func test_equal_candidates_do_not_choose_by_array_order() -> void:
	var points := PassFixture.points()
	var base := RopePassCandidates.new().find(points, 0.012, 0, null)[0]
	for reversed in [false, true]:
		var assist := RopePassAssist.new()
		var provider := AmbiguousProvider.new()
		provider.options = [base.duplicate(true), base.duplicate(true)]
		provider.options[1].id = Vector3i(50, 60, 0)
		if reversed:
			provider.options.reverse()
		assist.provider = provider
		var raw := points[0]
		assist.begin(raw)
		for frame in 20:
			raw += Vector3(0.0016, 0, -0.0012)
			var target := assist.update(raw, points[0], points, 0.012, 0.0, Vector3(0.6, 0, 0.8), null, 1.0 / 60.0)
			assert_eq(target, raw, "ambiguous paths leave raw hand intent unchanged")
		assert_eq(assist.state, RopePassAssist.State.FREE, "equal scores never pick an arbitrary path")


func test_sampling_and_stationary_invalidation() -> void:
	var sampled := RopeLayout.resample(PassFixture.points(), 96)
	assert_true(not RopePassCandidates.new().find(sampled, 0.012, 0, null).is_empty(), "endpoint duplicates do not make a valid aperture look self-intersecting")
	var assist := RopePassAssist.new()
	var points := PassFixture.points()
	var raw := points[0]
	assist.begin(raw)
	for frame in 12:
		raw += Vector3(0.0016, 0, -0.0012)
		points[0] = assist.update(raw, points[0], points, 0.012, 0, Vector3(0.6, 0, 0.8), null, 1.0 / 60.0)
	points[12].z += 0.2
	assert_true(not assist.validate_active(points, 0.012, 0, null), "moving boundary invalidates even when pointer is idle")
	assert_eq(assist.state, RopePassAssist.State.FREE, "idle validation never advances a stale path")


class AmbiguousProvider:
	extends RopePassCandidates
	var options: Array[Dictionary] = []
	func find(_p: PackedVector3Array, _r: float, _u: float, _c: RopeCollision) -> Array[Dictionary]:
		return options
	func refresh(_p: PackedVector3Array, _r: float, id: Vector3i, _c: RopeCollision, _e: int) -> Dictionary:
		for option in options:
			if option.id == id:
				return option
		return {}
