extends TestCase

const OctopusLocomotion = preload("res://scripts/octopus/octopus_locomotion.gd")

func test_moving_intent_produces_squash_stretch_and_bobbing() -> void:
	var rope: Rope = load("res://scenes/rope/rope.tscn").instantiate() as Rope
	rope.initial_layout = Rope.InitialLayout.DRAPED
	var collision := RopeCollision.new()
	collision.configure(load("res://data/mannequin/default_mannequin.tres"))
	rope.set_collision(collision)
	add_to_tree(rope)

	var octopus: Octopus = load("res://scenes/octopus/octopus.tscn").instantiate() as Octopus
	octopus.rope = rope
	add_to_tree(octopus)
	octopus.attach_to_world()

	var mascot: Node3D = octopus.get_node("Mascot")
	var initial_transform: Transform3D = mascot.transform
	var initial_scale: Vector3 = initial_transform.basis.get_scale()
	var initial_origin: Vector3 = initial_transform.origin

	# Advance with forward intent for 30 frames
	var delta: float = 1.0 / 60.0
	var scale_changed := false
	var origin_changed := false

	for i in 30:
		octopus.advance(delta, Vector3(0, 0, -1))
		var current_scale := mascot.transform.basis.get_scale()
		var current_origin := mascot.transform.origin

		if absf(current_scale.y - initial_scale.y) > 1e-6:
			scale_changed = true
		if absf(current_origin.y - initial_origin.y) > 1e-6:
			origin_changed = true

	assert_true(scale_changed, "mascot scale deforms (squash & stretch) during locomotion")
	assert_true(origin_changed, "mascot vertical origin bobs during locomotion")


func test_locomotion_conserves_approximate_volume() -> void:
	var locomotion = OctopusLocomotion.new()
	var mascot := Node3D.new()
	var base_transform := Transform3D(Basis.IDENTITY.scaled(Vector3(0.00018, 0.00018, 0.00018)), Vector3(0, -0.0015, 0))
	mascot.transform = base_transform

	var delta: float = 1.0 / 60.0
	var base_vol: float = pow(0.00018, 3)

	for i in 120:
		locomotion.step(delta, 0.55, mascot, base_transform)
		var s := mascot.transform.basis.get_scale()
		var vol := s.x * s.y * s.z
		var ratio := vol / base_vol
		assert_true(ratio >= 0.95 and ratio <= 1.05,
			"squash & stretch preserves volume within 5 percent: ratio %.4f" % ratio)

	mascot.free()


func test_waddle_roll_and_pitch_are_bounded() -> void:
	var locomotion = OctopusLocomotion.new()
	var mascot := Node3D.new()
	var base_transform := Transform3D(Basis.from_euler(Vector3(0, PI, 0)).scaled(Vector3(0.00018, 0.00018, 0.00018)), Vector3(0, -0.0015, 0))
	mascot.transform = base_transform

	var delta: float = 1.0 / 60.0
	var max_roll := 0.0
	var max_pitch := 0.0

	for i in 180:
		locomotion.step(delta, 0.55, mascot, base_transform)
		var rot := mascot.transform.basis.orthonormalized()
		var euler := rot.get_euler()
		# Relative to base Y rotation of PI
		max_roll = maxf(max_roll, absf(euler.z))
		max_pitch = maxf(max_pitch, absf(euler.x))

	assert_true(max_roll > 0.01, "mascot exhibits waddle roll during crawl")
	assert_true(max_roll < deg_to_rad(12.0), "waddle roll is physically bounded under 12 deg: got %.2f deg" % rad_to_deg(max_roll))
	assert_true(max_pitch < deg_to_rad(15.0), "forward pitch lean is bounded under 15 deg: got %.2f deg" % rad_to_deg(max_pitch))

	mascot.free()


func test_idle_breathing_is_smooth_and_subtle() -> void:
	var locomotion = OctopusLocomotion.new()
	var mascot := Node3D.new()
	var base_transform := Transform3D(Basis.IDENTITY.scaled(Vector3(0.00018, 0.00018, 0.00018)), Vector3(0, -0.0015, 0))
	mascot.transform = base_transform

	var delta: float = 1.0 / 60.0
	var min_sy := 1.0
	var max_sy := 1.0

	# Idle for 3 seconds
	for i in 180:
		locomotion.step(delta, 0.0, mascot, base_transform)
		var s := mascot.transform.basis.get_scale()
		var rel_y := s.y / 0.00018
		min_sy = minf(min_sy, rel_y)
		max_sy = maxf(max_sy, rel_y)

	assert_true(min_sy < 0.99, "idle animation exhibits breathing contraction")
	assert_true(max_sy > 1.01, "idle animation exhibits breathing expansion")
	assert_true(min_sy > 0.94 and max_sy < 1.06, "idle breathing is subtle (<6% scale change)")

	mascot.free()


func test_landing_impact_triggers_squash_and_recovers() -> void:
	var locomotion = OctopusLocomotion.new()
	var mascot := Node3D.new()
	var base_transform := Transform3D(Basis.IDENTITY.scaled(Vector3(0.00018, 0.00018, 0.00018)), Vector3(0, -0.0015, 0))
	mascot.transform = base_transform

	locomotion.trigger_landing_impact(0.18)
	locomotion.step(1.0 / 60.0, 0.0, mascot, base_transform)
	var s_squashed := mascot.transform.basis.get_scale()
	var rel_y := s_squashed.y / 0.00018
	assert_true(rel_y < 0.9, "landing impact visibly squashes the mascot body: got %.2f" % rel_y)

	# After recovering for 1 second, impact should decay
	for i in 60:
		locomotion.step(1.0 / 60.0, 0.0, mascot, base_transform)
	var s_recovered := mascot.transform.basis.get_scale()
	var rel_y_recovered := s_recovered.y / 0.00018
	assert_near(rel_y_recovered, 1.0, "landing impact fully decays over time", 0.06)

	mascot.free()
