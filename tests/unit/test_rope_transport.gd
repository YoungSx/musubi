extends TestCase

func _points() -> PackedVector3Array:
	var points := SelfCollisionFixture.trefoil(72)
	for i in points.size():
		var p := points[i]
		points[i] = Vector3(p.x,0.11+p.z,p.y-1.1)
	return points

func _camera() -> Camera3D:
	var camera := add_to_tree(Camera3D.new()) as Camera3D
	camera.position = Vector3(0,2,3)
	camera.look_at(Vector3.ZERO)
	return camera

func test_transport_requires_knotted_endpoint_and_sustained_inward_intent() -> void:
	var points := _points()
	var camera := _camera()
	var transport := RopeTransport.new()
	transport.begin(points,0.5,0.006,0)
	assert_true(not transport.eligible,"interior shaping never becomes whole-rope transport")
	transport.begin(RopeLayout.floor_curve(2.2,72,0.012),1,0.012,0)
	assert_true(not transport.eligible,"ordinary open rope remains free")
	transport.begin(points,1,0.006,0)
	assert_true(transport.eligible,"current crossing structure supplies the guide")
	var axis := (camera.unproject_position(points[-2])-camera.unproject_position(points[-1])).normalized()
	transport.update(axis*2,camera,points,0.006,1.0/60)
	assert_true(not transport.active,"one frame cannot engage retraction")
	for i in 12: transport.update(axis*2,camera,points,0.006,1.0/60)
	assert_true(transport.active and transport.progress > 0,"sustained inward motion feeds material")
	var before := transport.targets()
	var progress := transport.progress
	for i in 60: transport.update(Vector2.ZERO,camera,points,0.006,1.0/60)
	assert_eq(transport.targets(),before,"stationary input does not advance the guide")
	assert_eq(transport.progress,progress,"time alone cannot untie a knot")
	transport.update(-axis*2,camera,before,0.006,1.0/60)
	assert_true(transport.progress < progress,"reverse input backs out of the current material movement")
	for i in 20: transport.update(axis.orthogonal()*8,camera,transport.targets(),0.006,1.0/60)
	assert_true(not transport.active,"sideways movement releases the inferred route")

func test_transport_constraints_roundtrip_and_release() -> void:
	var config := RopeConfig.new()
	config.segment_count = 72
	var points := _points()
	config.length = RopeLayout.polyline_length(points)
	var sim := RopeSimulation.new(config,points)
	sim.begin_grip(1)
	var targets := points.duplicate()
	for i in targets.size(): targets[i] += Vector3(0.002,0.003,0)
	assert_true(sim.set_transport_targets(targets),"valid distributed soft targets accepted")
	sim.update_drag_target(targets[-1])
	for i in 5: sim.step(config.get_time_step())
	var restored := RopeSimulation.restore_state(JSON.parse_string(JSON.stringify(sim.capture_state(),"",true,true)))
	assert_true(restored != null and restored.has_transport_targets(),"active guide survives JSON roundtrip")
	for i in 20:
		sim.step(config.get_time_step())
		restored.step(config.get_time_step())
	assert_eq(sim.get_positions(),restored.get_positions(),"restored guide continues deterministically")
	sim.release_grip()
	assert_true(not sim.has_transport_targets(),"release removes all temporary guide constraints")
	var legacy := restored.capture_state()
	legacy.version = 4
	legacy.erase("transport")
	assert_true(RopeState.decode(legacy).transport.is_empty(),"version four snapshots have no transport")
	var invalid := restored.capture_state()
	invalid.transport = [[0,0,0]]
	assert_true(RopeState.decode(invalid).is_empty(),"malformed guide cannot load")
	invalid = restored.capture_state()
	invalid.drag_index = -1
	assert_true(RopeState.decode(invalid).is_empty(),"completed scene cannot retain hidden guide constraints")

func test_both_endpoints_transport_without_deleting_material() -> void:
	var points := _points()
	var camera := _camera()
	for side in 2:
		var transport := RopeTransport.new()
		transport.begin(points,float(side),0.006,0)
		var end := 0 if side == 0 else points.size()-1
		var adjacent := 1 if side == 0 else points.size()-2
		var axis := (camera.unproject_position(points[adjacent])-camera.unproject_position(points[end])).normalized()
		for i in 16: transport.update(axis*2,camera,points,0.006,1.0/60)
		var targets := transport.targets()
		assert_eq(targets.size(),points.size(),"all material points remain in either direction")
		assert_true(targets[end].distance_to(points[end]) > 0.001,"selected end retracts along the current path")
		assert_true(targets[points.size()-1-end].distance_to(points[points.size()-1-end]) > 0.001,"opposite end supplies the displaced material")

func test_small_nudges_do_not_take_over_the_whole_rope() -> void:
	var points := _points()
	var camera := _camera()
	var transport := RopeTransport.new()
	transport.begin(points,1,0.006,0)
	var axis := (camera.unproject_position(points[-2])-camera.unproject_position(points[-1])).normalized()
	for i in 30: transport.update(axis*0.2,camera,points,0.006,1.0/60)
	assert_true(not transport.active,"a small local correction must not engage whole-rope guidance")
	transport.update(axis*0.2,camera,points,0.006,0.1)
	assert_true(transport._screen_travel < 1,"a pause expires old approach evidence")

func test_material_extension_cannot_request_motion_below_floor() -> void:
	var points := _points()
	points[0].y = 0.01205
	points[1].y = 0.022
	var transport := RopeTransport.new()
	transport.begin(points,1,0.012,0)
	transport.active = true
	transport.progress = 0.5
	var targets := transport.targets()
	assert_true(targets[0].y >= 0.012,"material emerging from an inclined tail stays above floor")
	var supplied := PackedVector3Array()
	for i in 21: supplied.append(transport._payout.sample(0.5*float(i)/20))
	assert_near(RopeLayout.polyline_length(supplied),0.5,"floor handling preserves supplied arc length",0.02)

func test_payout_routes_around_other_strands() -> void:
	var points := PackedVector3Array([Vector3(0,0.01205,0),Vector3(-0.03,0.01205,0),Vector3(-0.06,0.01205,0),Vector3(-0.1,0.01205,0),Vector3(0.3,0.01205,-0.2),Vector3(0.3,0.01205,0.2),Vector3(0.5,0.01205,0.3)])
	var payout := RopePayout.new()
	payout.configure(points,0,0.012,0.01205,null)
	var end := payout.sample(0.6)
	assert_true(absf(end.z) > 0.1,"blocked straight payout turns toward free space")
	for point in payout._path:
		assert_true(RopePayout._segment_distance(point,points[4],points[5]) >= 0.012*1.9,"payout respects the blocking strand")

func test_escape_cancels_transport_without_losing_original_scene() -> void:
	var app := add_to_tree(load("res://scenes/main/play.tscn").instantiate()) as AppController
	app.process_mode = Node.PROCESS_MODE_DISABLED
	app.handle_action(&"ground")
	var before := app.rope.capture_scene_state()
	app.rope.begin_grip(1)
	app.rope.get_simulation().set_transport_targets(app.rope.get_simulation().get_positions())
	app.interaction_manager.cancel_drag()
	assert_eq(app.rope.capture_scene_state(),before,"cancel restores geometry and removes transport")

func test_real_focus_loss_still_releases_transport() -> void:
	var app := add_to_tree(load("res://scenes/main/play.tscn").instantiate()) as AppController
	app.process_mode = Node.PROCESS_MODE_DISABLED
	app.handle_action(&"ground")
	var screen := app.camera_rig.get_camera().unproject_position(app.rope.get_simulation().get_point(app.rope.config.segment_count))
	assert_true(app.interaction_manager._rope_interaction.begin(screen),"capture endpoint")
	var sim := app.rope.get_simulation()
	sim.set_transport_targets(sim.get_positions())
	app.interaction_manager._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	assert_true(not sim.has_transport_targets() and sim.get_drag_index() == -1,"normal focus policy releases all constraints")

func test_camera_change_discards_old_screen_axis_without_moving_target() -> void:
	var app := add_to_tree(load("res://scenes/main/play.tscn").instantiate()) as AppController
	app.process_mode = Node.PROCESS_MODE_DISABLED
	app.handle_action(&"ground")
	var sim := app.rope.get_simulation()
	var interaction := app.interaction_manager._rope_interaction
	var screen := app.camera_rig.get_camera().unproject_position(sim.get_point(app.rope.config.segment_count))
	interaction.begin(screen)
	interaction._transport.active = true
	interaction._surface_intent.active = true
	interaction._surface_intent.rear = true
	sim.set_transport_targets(sim.get_positions())
	var target := sim.get_drag_target()
	app.camera_rig.orbit(Vector2(0.1,0.1))
	app.camera_rig._process(0.1)
	interaction.move(screen)
	assert_true(not interaction._transport.active and not sim.has_transport_targets(),"old camera axis cannot continue transporting")
	assert_true(not interaction._surface_intent.active and not interaction._surface_intent.rear,"a new view cannot inherit an old rear-side inference")
	assert_eq(sim.get_drag_target(),target,"camera motion is not pointer intent")
