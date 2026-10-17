extends TestCase

func test_shoulder_anchors_flush_to_mascot_body() -> void:
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
	var mascot_world_pos: Vector3 = mascot.global_position

	# Verify shoulder distance is within expected collar radius from mascot center (~4.5cm - 5.5cm)
	var angles = [0.0, PI * 0.25, PI * 0.5, PI * 0.75, PI, -PI * 0.5]
	for a in angles:
		var dir := Vector3(cos(a), 0.0, sin(a))
		var target := octopus.get_position_in_world() + dir * 1.0
		var shoulder := octopus.get_shoulder(target)
		var radial_dist := Vector2(shoulder.x - mascot_world_pos.x, shoulder.z - mascot_world_pos.z).length()
		var height_diff := absf(shoulder.y - (mascot_world_pos.y + 0.009))

		assert_true(radial_dist >= 0.040 and radial_dist <= 0.055,
			"radial distance to mascot center is on collar rim: %.4f m" % radial_dist)
		assert_true(height_diff <= 0.008,
			"height matches tentacle base height on mascot collar: diff %.4f m" % height_diff)

	# Verify that when target is at carry point (directly overhead), shoulder does not flip backwards
	var carry_target := octopus.get_carry_point()
	var shoulder_carry := octopus.get_shoulder(carry_target)
	var carry_radial := Vector2(shoulder_carry.x - mascot_world_pos.x, shoulder_carry.z - mascot_world_pos.z).length()
	assert_true(carry_radial >= 0.040 and carry_radial <= 0.055,
		"carry shoulder remains anchored on collar rim: %.4f m" % carry_radial)

	# Verify shoulder tracks mascot during locomotion animation deformation
	octopus.advance(0.1, Vector3(0, 0, -1))
	var deformed_mascot_pos := mascot.global_position
	var deformed_shoulder := octopus.get_shoulder(octopus.get_position_in_world() + Vector3(0, 0, -1))
	var deformed_radial := Vector2(deformed_shoulder.x - deformed_mascot_pos.x, deformed_shoulder.z - deformed_mascot_pos.z).length()
	assert_true(deformed_radial >= 0.038 and deformed_radial <= 0.058,
		"shoulder stays glued to mascot collar during locomotion: %.4f m" % deformed_radial)


func test_held_rope_keeps_shoulder_attached_during_pull() -> void:
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

	# Grab rope
	var grabbed := octopus.grab(Vector3.FORWARD)
	if grabbed:
		var mascot: Node3D = octopus.get_node("Mascot")
		# Advance and pull rope over 60 frames
		for i in 60:
			octopus.advance(1.0 / 60.0, Vector3(0, 0, -1))
			var shoulder := octopus.get_shoulder(octopus.get_carry_point())
			var mascot_pos := mascot.global_position
			var gap := shoulder.distance_to(mascot_pos)
			assert_true(gap >= 0.040 and gap <= 0.060,
				"shoulder remains firmly attached to mascot during pulling: gap %.4f m" % gap)
