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
