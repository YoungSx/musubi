extends TestCase

# Isolate temporal selection from the geometric observer. Actual geometric
# passage and camera/input are additionally exercised by the rendered replay.
class CandidateFixture extends GroundLoopTopology:
	var choices: Array[Dictionary] = []
	func observe(_points: PackedVector3Array, _radius: float, _floor: float) -> Array[Dictionary]:
		return []
	func entries(_loops: Array[Dictionary], _points: PackedVector3Array, _tip: Vector3,
			_direction: Vector2, _u: float, _radius: float, _collision: RopeCollision) -> Array[Dictionary]:
		return choices

func _points() -> PackedVector3Array:
	return PackedVector3Array([Vector3(-0.3, 0.012, 0), Vector3(-0.2, 0.012, 0),
		Vector3(-0.1, 0.012, 0), Vector3(0, 0.1, -0.1), Vector3(0, 0.1, 0.1),
		Vector3(0.2, 0.012, 0.2), Vector3(0.3, 0.012, 0.2)])

func _candidate(id := Vector2i(1, 8)) -> Dictionary:
	return {"loop": {"id": id, "first": 1.0, "last": 5.0,
		"polygon": PackedVector2Array([Vector2(0,-0.1),Vector2(0.2,-0.1),Vector2(0.2,0.1),Vector2(0,0.1)])},
		"edge": 3, "u": 3.5 / 6.0, "entry": Vector2.ZERO,
		"world": Vector3(0,0.012,0), "normal": Vector2.RIGHT,
		"alignment": 1.0, "distance": 0.05}

func _recognizer(choices: Array[Dictionary]) -> GroundPassIntent:
	var result := GroundPassIntent.new()
	var fixture := CandidateFixture.new()
	fixture.choices = choices
	result.topology = fixture
	result.begin(Vector3(-0.08,0.012,0))
	return result

func _advance(intent: GroundPassIntent, frame: int) -> Vector3:
	return intent.update(Vector3(-0.08 + frame * 0.004,0.012,0),
		Vector3(-0.04,0.012,0), _points(), 0, 0.012, 0, null, 1.0/60.0)

func test_selection_requires_trajectory_and_dwell() -> void:
	var intent := _recognizer([_candidate()])
	_advance(intent, 1)
	assert_true(intent.support_u < 0, "one frame cannot claim the passage")
	for frame in range(2,10): _advance(intent, frame)
	assert_true(intent.support_u >= 0, "consistent motion progressively opens support")
	assert_true(intent.support_strength < 1, "support starts softly")

func test_equal_candidates_do_not_capture_or_inherit_confidence() -> void:
	var intent := _recognizer([_candidate(), _candidate(Vector2i(2,9))])
	for frame in range(1,20): _advance(intent, frame)
	assert_true(intent.support_u < 0, "equally plausible passages stay free")
	var fixture := intent.topology as CandidateFixture
	fixture.choices = [_candidate()]
	for frame in range(20,24): _advance(intent, frame)
	fixture.choices = [_candidate(Vector2i(2,9))]
	_advance(intent, 24)
	assert_true(intent.confidence < 0.2 and intent.support_u < 0, "new loop must earn its own confidence")

func test_stationary_input_does_not_advance_or_drop_under_intent() -> void:
	var intent := _recognizer([_candidate()])
	for frame in range(1,10): _advance(intent, frame)
	var raw := Vector3(-0.044,0.012,0)
	var before := intent._last_output
	var strength := intent.support_strength
	for frame in 120:
		var output := intent.update(raw, Vector3(-0.04,0.012,0), _points(), 0,0.012,0,null,1.0/60.0)
		assert_eq(output, before, "stationary cursor preserves the last constrained target")
	assert_eq(intent.support_strength, strength, "waiting cannot complete an action")
	assert_true(intent.prefer_under, "waiting preserves the established path")

func test_pass_requires_actual_finite_edge_and_height_clearance() -> void:
	var intent := _recognizer([])
	intent._activate(_candidate(), Vector3(-0.04,0.012,0))
	intent._previous_actual = Vector3(-0.04,0.012,0.3)
	intent.observe_actual(Vector3(0.04,0.012,0.3), _points(),0.012)
	assert_eq(intent.confirmed_passes,0,"crossing an infinite extension is not a pass")
	intent._previous_actual = Vector3(-0.04,0.09,0)
	intent.observe_actual(Vector3(0.04,0.09,0), _points(),0.012)
	assert_eq(intent.confirmed_passes,0,"height overlap is not a pass")
	intent._previous_actual = Vector3(-0.04,0.012,0)
	intent.observe_actual(Vector3(0.04,0.012,0), _points(),0.012)
	assert_eq(intent.confirmed_passes,1,"physical endpoint crossed below the finite strand")
	intent.observe_actual(Vector3(0.06,0.012,0), _points(),0.012)
	assert_eq(intent.confirmed_passes,1,"one passage counts once")
	intent.phase = GroundPassIntent.Phase.UNWIND
	intent.observe_actual(Vector3(-0.04,0.012,0), _points(),0.012)
	assert_true(intent._recent_pass.is_empty() and intent.support_u < 0,"reverse crossing releases remembered passage")

func test_missing_closure_releases_support() -> void:
	var intent := _recognizer([])
	intent._activate(_candidate(), Vector3(-0.04,0.012,0))
	assert_true(not intent.validate_active(_points(),0.012),"a disappeared loop invalidates assistance")
	assert_true(intent.support_u < 0,"invalid route cannot leave a hidden support behind")

func test_open_floor_rope_is_not_a_loop() -> void:
	var points := RopeLayout.floor_curve(2.2,72,0.012)
	assert_true(GroundLoopTopology.new().observe(points,0.012,0).is_empty(),"ordinary open curve is not recognized as a passage")

func test_multi_channel_scores_survive_jitter_but_not_a_changed_intent() -> void:
	var selection := PassageChoice.new()
	var a := _candidate()
	var b := _candidate(Vector2i(3,12))
	var selected := {}
	for frame in 18:
		a.alignment = 0.9 if frame%2 == 0 else 1.0
		b.alignment = 1.0 if frame%2 == 0 else 0.9
		selected = selection.update([a,b],1,0.003,1.0/60,72,0.012)
	assert_true(selected.is_empty(),"jitter between equally plausible exits cannot select one")
	assert_eq(selection.tracks.size(),2,"both hypotheses retained rather than first-hit selection")
	b.alignment = 0.2
	a.alignment = 1.0
	for frame in 30: selected = selection.update([a,b],1,0.003,1.0/60,72,0.012)
	assert_eq(selected.loop.id,a.loop.id,"clear sustained trajectory selects the intended corridor")
	for frame in 30: selection.update([],1,0.003,1.0/60,72,0.012)
	assert_true(selection.tracks.is_empty(),"departed channels cannot keep attracting the tip")

func test_arrangement_discovers_multiple_mixed_material_channels() -> void:
	var path := PackedVector3Array()
	for p in [Vector2(-0.7,0),Vector2(-0.4,0.2),Vector2(-0.2,0.2),Vector2(-0.2,-0.2),Vector2(-0.5,-0.2),Vector2(-0.5,0.15),Vector2(0,0.15),Vector2(0.2,0.3),Vector2(0.5,0.3),Vector2(0.5,-0.1),Vector2(0.1,-0.1),Vector2(0.1,0.25),Vector2(0.65,0.25)]:
		path.append(Vector3(p.x,0.03,p.y))
	var faces := GroundFaces.new().observe(RopeLayout.resample(path,96),0.012,0)
	assert_true(faces.size() >= 2,"intersecting arcs yield multiple bounded passage cells")
	for face in faces:
		assert_true(Geometry2D.is_point_in_polygon(face.center,face.polygon),"candidate center lies inside its own cell")

func test_shared_entrances_merge_and_inside_motion_can_exit() -> void:
	var points := PackedVector3Array([Vector3(-0.05,0.012,0),Vector3(-0.2,0.012,-0.3),Vector3(-0.3,0.012,-0.4),Vector3(-0.2,0.1,-0.4),Vector3(0,0.1,-0.1),Vector3(0,0.1,0.1),Vector3(0.2,0.1,0.1),Vector3(0.2,0.1,-0.1)])
	var loop: Dictionary = _candidate().loop
	loop.first = 4.0
	loop.last = 5.0
	loop.face = true
	var overlapping := loop.duplicate(true)
	overlapping.id = Vector2i(4,9)
	var topology := GroundLoopTopology.new()
	var candidates := topology.entries([loop,overlapping],points,points[0],Vector2.RIGHT,0,0.012,null)
	assert_eq(candidates.size(),1,"one physical opening is not two ambiguous choices")
	var inside := Vector3(0.05,0.012,0)
	var exits := topology.entries([loop],points,inside,Vector2.LEFT,0,0.012,null)
	assert_eq(exits.size(),1,"the tip can leave a cell without selecting a new tool")
	assert_true(exits[0].exiting,"exit carries its geometric orientation")
	var intent := GroundPassIntent.new()
	intent.begin(inside)
	intent._activate(exits[0],inside)
	intent.observe_actual(Vector3(-0.05,0.012,0),points,0.012)
	assert_eq(intent.confirmed_exits,1,"exit requires a real below-strand crossing")

func test_soft_lock_aligns_corridor_laterally_and_breakout_releases() -> void:
	var intent := _recognizer([])
	intent._activate(_candidate(), Vector3(-0.04, 0.012, 0))
	intent.support_strength = 0.8
	# _candidate.entry is (0,0), normal is (1,0) (RIGHT). Tangent is (0,1) (UP/DOWN in 2D, mapped to z in 3D).
	var raw_centered := Vector3(-0.02, 0.012, 0.0)
	var out_centered := intent.update(raw_centered, Vector3(-0.02, 0.012, 0), _points(), 0, 0.012, 0, null, 1.0/60.0)
	assert_near(out_centered.z, 0.0, "zero lateral offset stays centered", 0.001)

	# Small lateral offset: soft lock gently pulls lateral misalignment towards centerline
	var raw_offset := Vector3(-0.02, 0.012, 0.03)
	var out_offset := intent.update(raw_offset, Vector3(-0.02, 0.012, 0), _points(), 0, 0.012, 0, null, 1.0/60.0)
	assert_true(out_offset.z < 0.03 and out_offset.z > 0.0, "soft magnetism pulls lateral misalignment towards center")

	# Large lateral offset (> radius * 7.0 = 0.084): deliberate sideways breakout
	var raw_breakout := Vector3(-0.02, 0.012, 0.12)
	var out_breakout := intent.update(raw_breakout, Vector3(-0.02, 0.012, 0), _points(), 0, 0.012, 0, null, 1.0/60.0)
	assert_eq(intent.support_u, -1.0, "pulling away laterally cleanly breaks out and drops support")
	assert_eq(out_breakout, raw_breakout, "breakout returns exact raw position without latching")

func test_approach_lead_in_provides_subtle_magnetism() -> void:
	var intent := _recognizer([_candidate()])
	for frame in range(1, 8):
		_advance(intent, frame)
	assert_true(intent.phase == GroundPassIntent.Phase.APPROACH, "intent is in approach phase")
	assert_true(intent.confidence > 0.2, "confidence is rising")
	assert_true(intent.support_u < 0, "support is not yet active")
	var raw_approach := Vector3(-0.05, 0.012, 0.02)
	var out_approach := intent.update(raw_approach, Vector3(-0.04, 0.012, 0), _points(), 0, 0.012, 0, null, 1.0/60.0)
	assert_true(out_approach.z < 0.02 and out_approach.z > 0.0, "approach lead-in provides subtle magnetism towards entrance")

