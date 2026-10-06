extends TestCase

func test_surface_ray_uses_same_body_clearance_without_floor_hit() -> void:
	var part := _part(MannequinPart.Primitive.SPHERE)
	var collision := _collision(part)
	var hit := collision.trace_surface(Vector3(0,0,2),Vector3.FORWARD,4,0.012)
	assert_true(not hit.is_empty(),"front surface found")
	assert_near(collision.get_clearance(hit.position),0.012,"ray target has rope-radius clearance",0.0001)
	assert_true(hit.normal.dot(Vector3.BACK) > 0.99,"front normal faces the viewer")
	var back := collision.trace_surface(Vector3(0,0,-2),Vector3.BACK,4,0.012)
	assert_true(back.position.z < 0,"reverse ray finds the rear surface")
	assert_true(collision.trace_surface(Vector3(3,2,2),Vector3.DOWN,4,0.012).is_empty(),"floor is not treated as a mannequin surface")


func test_sphere_capsule_and_box_project_outward() -> void:
	for primitive in [MannequinPart.Primitive.SPHERE, MannequinPart.Primitive.CAPSULE, MannequinPart.Primitive.BOX]:
		var part := _part(primitive)
		var collision := _collision(part)
		var projected := collision.project_point(Vector3.ZERO, 0.012)
		assert_true(projected.is_finite(), "projection at primitive center is finite")
		assert_true(collision.get_clearance(projected) >= 0.012 - 1e-5, "center projects outside primitive %d" % primitive)
		assert_vec3_near(collision.project_point(Vector3(3, 3, 3), 0.012), Vector3(3, 3, 3), "distant point unchanged")


func test_collision_uses_part_rotation_and_world_transform() -> void:
	var part := _part(MannequinPart.Primitive.CAPSULE)
	part.position = Vector3(0.2, 1.0, 0.0)
	part.rotation_degrees.z = 90.0
	var config := MannequinConfig.new()
	config.parts = [part]
	var world := Transform3D(Basis.from_euler(Vector3(0, 0.7, 0)).scaled(Vector3.ONE * 2.0), Vector3(2, 1, -1))
	var collision := RopeCollision.new()
	collision.floor_enabled = false
	collision.configure(config, world)
	var center := world * part.position
	assert_near(collision.get_clearance(center), -part.radius * 2.0, "uniform scale used")
	var projected := collision.project_point(center, 0.012)
	assert_near(collision.get_clearance(projected), 0.012, "world-space radius preserved", 0.0001)


func test_segment_interior_contacts_narrow_capsule() -> void:
	var part := _part(MannequinPart.Primitive.CAPSULE)
	part.radius = 0.015
	var collision := _collision(part)
	var points := PackedVector3Array([Vector3(-0.2, 0, 0.005), Vector3(0.2, 0, 0.005)])
	var previous := points.duplicate()
	var masses := PackedFloat32Array([1, 1])
	assert_true(collision.get_clearance(points[0]) > 0.012 and collision.get_clearance(points[1]) > 0.012, "both endpoints start clear")
	collision.solve(points, previous, masses, 0.012, 0.2)
	assert_true(collision.get_clearance(points[0].lerp(points[1], 0.5)) >= 0.012 - 1e-5, "segment interior clears narrow obstacle")


func test_segment_interior_contacts_rotated_box() -> void:
	var part := _part(MannequinPart.Primitive.BOX)
	part.rotation_degrees = Vector3(0, 45, 0)
	var collision := _collision(part)
	var points := PackedVector3Array([Vector3(-0.3, 0, 0), Vector3(0.3, 0, 0)])
	var previous := points.duplicate()
	for i in 8:
		collision.solve(points, previous, PackedFloat32Array([1, 1]), 0.012, 0.2)
	for i in 21:
		assert_true(collision.get_clearance(points[0].lerp(points[1], i / 20.0)) >= 0.012 - 0.0002, "box segment clear")


func test_pins_remain_fixed_even_inside_obstacle() -> void:
	var collision := _collision(_part(MannequinPart.Primitive.SPHERE))
	var positions := PackedVector3Array([Vector3.ZERO, Vector3(0.05, 0, 0)])
	var previous := positions.duplicate()
	collision.solve(positions, previous, PackedFloat32Array([0, 1]), 0.012, 0.2)
	assert_vec3_near(positions[0], Vector3.ZERO, "pin cannot be moved by contact")
	assert_vec3_near(previous[0], Vector3.ZERO, "pin velocity untouched")


func test_motion_sweep_does_not_jump_through_sphere() -> void:
	var collision := _collision(_part(MannequinPart.Primitive.SPHERE))
	var result := collision.constrain_motion(Vector3(-0.3, 0, 0), Vector3(0.3, 0, 0), 0.012)
	assert_true(result.x < -0.1, "large drag stops at near surface")
	assert_true(collision.get_clearance(result) >= 0.012 - 1e-5, "drag target clear")


func test_floor_stops_falling_rope_and_friction_removes_slide() -> void:
	var config := RopeConfig.new()
	config.segment_count = 12
	config.length = 0.6
	var points := PackedVector3Array()
	for i in 13:
		points.append(Vector3(i * 0.05, 0.2, 0))
	var collision := RopeCollision.new()
	var sim := RopeSimulation.new(config, points)
	sim.set_collision(collision)
	for i in 180:
		sim.step(config.get_time_step())
	for point in sim.get_positions():
		assert_true(point.y >= config.radius - 0.0001, "floor clearance")
	assert_true(sim.get_max_speed() < 0.001, "resting rope stable")
	var sliding := PackedVector3Array([Vector3(0.0, 0.0, 0.0)])
	var previous := PackedVector3Array([Vector3(-0.02, 0.0, 0.0)])
	collision.solve(sliding, previous, PackedFloat32Array([1]), config.radius, 0.5)
	assert_near((sliding[0] - previous[0]).x, 0.01, "friction removes half tangent velocity")


func test_default_mannequin_rope_contacts_conserve_length_and_settle() -> void:
	var config := load("res://data/rope/default_rope.tres") as RopeConfig
	var collision := RopeCollision.new()
	collision.configure(load("res://data/mannequin/default_mannequin.tres") as MannequinConfig)
	var a := Vector3(-0.5, 1.45, 0.12)
	var b := Vector3(0.5, 1.45, 0.12)
	var sim := RopeSimulation.new(config, RopeLayout.hanging(a, b, config.length, config.segment_count))
	sim.pin(0, a)
	sim.pin(config.segment_count, b)
	sim.set_collision(collision)
	for i in 600:
		sim.step(config.get_time_step())
	var lowest_clearance := INF
	var points := sim.get_positions()
	for i in points.size() - 1:
		for sample_index in 5:
			lowest_clearance = minf(lowest_clearance, collision.get_clearance(points[i].lerp(points[i + 1], sample_index / 4.0)))
	assert_true(lowest_clearance >= config.radius - 0.0005, "body clearance %.6f" % lowest_clearance)
	assert_near(sim.get_length(), config.length, "contact rope length", 0.015)
	assert_true(sim.get_max_segment_stretch() < 0.03, "contact segment stretch %.5f" % sim.get_max_segment_stretch())
	assert_true(sim.get_max_speed() < 0.03, "contact settling speed %.5f" % sim.get_max_speed())
	assert_vec3_near(sim.get_point(0), a, "first pin fixed")
	assert_vec3_near(sim.get_point(config.segment_count), b, "last pin fixed")


func test_friction_acts_during_resting_simulation() -> void:
	var config := RopeConfig.new()
	config.segment_count = 2
	config.length = 0.1
	config.damping = 0.0
	config.gravity = Vector3(1, -9.8, 0)
	config.friction = 0.5
	var points := PackedVector3Array([Vector3(0, config.radius, 0), Vector3(0.05, config.radius, 0), Vector3(0.1, config.radius, 0)])
	var stopped := RopeSimulation.new(config, points)
	stopped.set_collision(RopeCollision.new())
	var sliding_config := config.duplicate() as RopeConfig
	sliding_config.friction = 0.0
	var sliding := RopeSimulation.new(sliding_config, points)
	sliding.set_collision(RopeCollision.new())
	for i in 120:
		stopped.step(config.get_time_step())
		sliding.step(config.get_time_step())
	assert_true(stopped.get_point(0).x < 0.01, "friction resists sliding on floor")
	assert_true(sliding.get_point(0).x > 0.2, "friction-free rope accelerates sideways")


func _part(primitive: MannequinPart.Primitive) -> MannequinPart:
	var part := MannequinPart.new()
	part.primitive = primitive
	part.radius = 0.1
	part.height = 0.5
	part.box_size = Vector3(0.2, 0.3, 0.2)
	return part


func _collision(part: MannequinPart) -> RopeCollision:
	var config := MannequinConfig.new()
	config.parts = [part]
	var collision := RopeCollision.new()
	collision.floor_enabled = false
	collision.configure(config)
	return collision
