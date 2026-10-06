extends TestCase

class PassProbe extends RopePassAssist:
	var calls := 0
	func update(raw: Vector3,_actual: Vector3,_points: PackedVector3Array,_radius: float,_u: float,_back: Vector3,_collision: RopeCollision,_dt: float) -> Vector3:
		calls += 1
		state = State.APPROACH
		return raw
	func validate_active(_points: PackedVector3Array,_radius: float,_u: float,_collision: RopeCollision) -> bool:
		return true

func test_surface_following_preserves_stationary_intent() -> void:
	var camera := _camera()
	var collision := _collision()
	var start := Vector3(0,0,0.6)
	var cursor := camera.unproject_position(start)
	var intent := SurfaceIntent.new()
	intent.begin(start,cursor)
	var target := _prime(intent,camera,collision,start,cursor)
	assert_true(intent.active,"movement over the body selects surface following")
	assert_true(collision.get_clearance(target) >= 0.012,"target respects the same primitive surface as physics")
	var stopped := intent.update(cursor+Vector2(20,0),camera,Vector3(20,20,20),0.012,collision,start)
	assert_eq(stopped,target,"no pointer motion cannot advance to a new surface target")
	intent.begin(start,cursor)
	assert_true(not intent.active and not intent.rear,"new grab starts with no inherited rear-side choice")

func test_silhouette_jitter_cannot_flip_surface_side() -> void:
	var camera := _camera()
	var collision := _collision()
	var start := Vector3(0,0,0.6)
	var center := camera.unproject_position(start)
	var edge := camera.unproject_position(Vector3(0.53,0,0))+Vector2(2,0)
	var intent := SurfaceIntent.new()
	intent.begin(start,center)
	_prime(intent,camera,collision,start,center)
	for i in range(1,41):
		var screen := (center+Vector2(20,0)).lerp(edge,float(i)/40)
		intent.update(screen,camera,start,0.012,collision,intent._target)
	assert_true(intent._rim,"outward approach establishes actual silhouette evidence")
	intent.update(edge-Vector2(1,0),camera,start,0.012,collision,intent._target)
	assert_true(not intent.rear,"one pixel of reversal is insufficient evidence")
	intent.update(edge-Vector2(12,0),camera,start,0.012,collision,intent._target)
	assert_true(intent.rear,"sustained reversal at the rim can continue behind the object")

func test_front_only_reversal_does_not_mean_wrap() -> void:
	var camera := _camera()
	var collision := _collision()
	var start := Vector3(0,0,0.6)
	var center := camera.unproject_position(start)
	var near_edge := camera.unproject_position(Vector3(0.48,0,0))
	var intent := SurfaceIntent.new()
	intent.begin(start,center)
	_prime(intent,camera,collision,start,center)
	for i in range(1,31): intent.update((center+Vector2(20,0)).lerp(near_edge,float(i)/30),camera,start,0.012,collision,intent._target)
	for i in range(1,9): intent.update(near_edge-Vector2(i*2,0),camera,start,0.012,collision,intent._target)
	assert_true(not intent.rear,"reversing on the visible face without leaving its silhouette stays in front")

func test_returning_from_rim_is_not_counted_as_escape() -> void:
	var camera := _camera()
	var collision := _collision()
	var start := Vector3(0,0,0.6)
	var center := camera.unproject_position(start)
	var edge := camera.unproject_position(Vector3(0.53,0,0))+Vector2(2,0)
	var intent := SurfaceIntent.new()
	intent.begin(start,center)
	_prime(intent,camera,collision,start,center)
	for i in range(1,41):
		intent.update((center+Vector2(20,0)).lerp(edge,float(i)/40),camera,start,0.012,collision,intent._target)
	for i in range(1,10): intent.update(edge+Vector2(i,0),camera,start,0.012,collision,intent._target)
	for i in range(1,27): intent.update(edge+Vector2(9-i,0),camera,start,0.012,collision,intent._target)
	assert_true(intent.active,"return travel cannot add to the distance away from the silhouette")
	assert_true(intent.rear,"small out-and-back motion retains the intended wrap evidence")

func test_surface_route_reaches_rear_without_cutting_through_body() -> void:
	var collision := _collision()
	var route := SurfaceRoute.new()
	var point := Vector3(0.514,0,0)
	var goal := Vector3(0,0,-0.514)
	for i in 120:
		var next := route.advance(point,goal,0.01,0.012,collision)
		assert_true(collision.is_body_segment_clear(point,next,0.012),"every route step remains outside the body")
		point = next
	assert_true(point.distance_to(goal) < 0.02,"route goes around to the rear rather than pressing into the front")
	assert_eq(route.rebuilds,1,"unchanged body slice reuses its grid")

func test_route_can_depart_from_actual_solver_contact() -> void:
	var collision := _collision()
	var route := SurfaceRoute.new()
	var point := collision.project_point(Vector3(0.2,0,0),0.012)
	var goal := Vector3(0,0,-0.514)
	for i in 120: point = route.advance(point,goal,0.01,0.012,collision)
	assert_true(point.distance_to(goal) < 0.02,"a legal solver contact must not be rejected as an impossible route seed")

func test_route_rebuilds_when_same_collision_object_moves() -> void:
	var collision := _collision()
	var route := SurfaceRoute.new()
	var point := Vector3(0.514,0,0)
	var goal := Vector3(0,0,-0.514)
	route.advance(point,goal,0.01,0.012,collision)
	var moved := Transform3D(Basis.IDENTITY,Vector3(0.05,0,0))
	var config := MannequinConfig.new()
	var sphere := MannequinPart.new()
	sphere.primitive = MannequinPart.Primitive.SPHERE
	sphere.radius = 0.5
	config.parts = [sphere]
	collision.configure(config,moved)
	point = Vector3(0.564,0,0)
	for i in 120: point = route.advance(point,goal,0.01,0.012,collision)
	assert_eq(route.rebuilds,2,"restoring a changed mannequin invalidates its old slice")
	assert_true(point.distance_to(goal) < 0.02,"route reaches the goal around the changed obstacle")

func test_surface_route_uses_mannequin_arm_torso_gap() -> void:
	var collision := RopeCollision.new()
	collision.configure(load("res://data/mannequin/default_mannequin.tres"))
	var route := SurfaceRoute.new()
	var point := Vector3(-0.17,1.2,0.05)
	var goal := Vector3(-0.1,1.2,-0.13)
	for i in 60:
		var next := route.advance(point,goal,0.01,0.012,collision)
		assert_true(collision.is_body_segment_clear(point,next,0.012),"gap route respects torso and arm together")
		assert_true(next.x > -0.23,"route can use the actual gap instead of orbiting the entire figure")
		point = next
	assert_true(point.distance_to(goal) < 0.02,"working end reaches the back through the available gap")

func test_surface_brush_and_deliberate_escape_preserve_player_control() -> void:
	var camera := _camera()
	var collision := _collision()
	var start := Vector3(0,0,0.6)
	var cursor := camera.unproject_position(start)
	var intent := SurfaceIntent.new()
	intent.begin(start,cursor)
	var raw := start+Vector3(0.01,0,0)
	assert_eq(intent.update(cursor+Vector2(2,0),camera,raw,0.012,collision,start),raw,"brief overlap preserves free intent")
	assert_true(not intent.active,"one frame cannot silently attach the rope")
	for i in 30: intent.update(cursor+Vector2(2,0),camera,raw,0.012,collision,start)
	assert_true(not intent.active,"resting a pointer cannot earn capture by itself")
	intent.begin(start,cursor)
	for i in 60: intent.update(cursor+Vector2(2 if i%2 == 0 else -2,0),camera,raw,0.012,collision,start)
	assert_true(not intent.active,"small stationary tremor is not a deliberate approach")
	intent.update(cursor+Vector2(10,0),camera,raw,0.012,collision,start,PackedVector3Array(),-1,0.1)
	assert_true(not intent.active,"a pause expires old hover evidence")
	intent.begin(start,cursor)
	_prime(intent,camera,collision,start,cursor)
	assert_true(intent.active,"sustained approach can acquire surface assistance")
	var escape := Vector3(1.5,0,0.6)
	var escaped := intent.update(cursor+Vector2(500,0),camera,escape,0.012,collision,start)
	assert_true(not intent.active and not intent.rear,"pulling away exits assistance without another button")
	assert_eq(escaped,escape,"escaped pointer regains free target control")

func test_idle_surface_cannot_advance_solver_waypoints() -> void:
	var app := add_to_tree(load("res://scenes/main/play.tscn").instantiate()) as AppController
	app.process_mode = Node.PROCESS_MODE_DISABLED
	var sim := app.rope.get_simulation()
	var interaction := app.interaction_manager._rope_interaction
	var screen := app.camera_rig.get_camera().unproject_position(sim.get_point(app.rope.config.segment_count))
	interaction.begin(screen)
	interaction._surface_intent.active = true
	interaction._surface_intent.requested_goal = sim.get_drag_target()+Vector3.RIGHT*0.5
	var target := sim.get_drag_target()
	for i in 60: interaction.tick(1.0/60)
	assert_eq(sim.get_drag_target(),target,"idle time cannot keep routing the hand behind the player's back")

func test_model_mode_lifts_a_floor_endpoint_instead_of_amplifying_depth() -> void:
	var app := add_to_tree(load("res://scenes/main/play.tscn").instantiate()) as AppController
	app.process_mode = Node.PROCESS_MODE_DISABLED
	app.new_rope(6)
	var sim := app.rope.get_simulation()
	var interaction := app.interaction_manager._rope_interaction
	var point := sim.get_point(app.rope.config.segment_count)
	var screen := app.camera_rig.get_camera().unproject_position(point)
	assert_true(interaction.begin(screen),"pick floor endpoint in the mannequin view")
	assert_true(not interaction._ground_hand.active,"shallow mannequin camera does not use floor-knot projection")
	interaction.move(screen+Vector2(0,-10))
	assert_true(sim.get_drag_target().y > point.y+0.01,"upward cursor motion lifts the requested rope position")

func test_spatial_pass_has_priority_over_surface_following() -> void:
	var app := add_to_tree(load("res://scenes/main/play.tscn").instantiate()) as AppController
	app.process_mode = Node.PROCESS_MODE_DISABLED
	var sim := app.rope.get_simulation()
	var interaction := app.interaction_manager._rope_interaction
	var point := sim.get_point(app.rope.config.segment_count)
	var screen := app.camera_rig.get_camera().unproject_position(point)
	assert_true(interaction.begin(screen),"capture endpoint")
	var probe := PassProbe.new()
	interaction._pass_assist = probe
	interaction._surface_intent.active = true
	interaction.move(screen+Vector2(5,0))
	assert_true(probe.calls > 0,"surface motion is still offered to the passage layer")
	var target := sim.get_drag_target()
	interaction._surface_intent.requested_goal = target+Vector3.UP
	interaction.tick(0.1)
	assert_eq(sim.get_drag_target(),target,"surface follower cannot overwrite an active pass constraint")
	interaction.end()
	interaction.tick(0.1)
	assert_eq(sim.get_drag_index(),-1,"release cancels any pending surface motion")

func test_wrap_clearance_lifts_over_a_standing_strand() -> void:
	var collision := _collision()
	var points := PackedVector3Array([Vector3(0.2,0,0.55),Vector3(0.3,0,0.6),Vector3(0.4,0,0.6),Vector3(0.4,0.2,0.6),Vector3(-0.1,0,0.514),Vector3(0.1,0,0.514),Vector3(0.2,0.2,0.55)])
	var target := SurfaceClearance.over_target(Vector3(0,0,0.514),points,0,0.012,collision)
	assert_true(target.z > 0.539,"ordinary Wrap supplies outward clearance at a rope crossing")
	assert_true(collision.get_body_clearance(target) >= 0.012,"lift remains outside the mannequin")
	var contact := collision.project_point(Vector3(0,0,0.2),0.012)
	assert_true(SurfaceClearance.over_target(contact,points,0,0.012,collision).z > 0.539,"legal surface contact can begin an outward lift")
	var far := Vector3(0,0.3,0.55)
	assert_eq(SurfaceClearance.over_target(far,points,0,0.012,collision),far,"unrelated strands cannot attract or lift the hand")

func test_wrap_lift_does_not_push_into_a_neighboring_arm() -> void:
	var collision := RopeCollision.new()
	collision.configure(load("res://data/mannequin/default_mannequin.tres"))
	var point := Vector3(-0.17,1.2,0)
	var points := PackedVector3Array([Vector3(-0.4,1.1,0.3),Vector3(-0.4,1.1,0.4),Vector3(-0.4,1.1,0.5),Vector3(-0.4,1.2,0.5),Vector3(-0.17,1.2,-0.05),Vector3(-0.17,1.2,0.05),Vector3(-0.17,1.4,0.1)])
	assert_eq(SurfaceClearance.over_target(point,points,0,0.012,collision),point,"insufficient room cannot become an inward body target")

func test_slice_broad_phase_preserves_body_occupancy() -> void:
	var collision := RopeCollision.new()
	collision.configure(load("res://data/mannequin/default_mannequin.tres"))
	var margin := 0.017
	for height in [0.1,0.9,1.2,1.6]:
		var parts := collision.get_slice_parts(height,margin)
		for x in range(-12,13):
			for z in range(-8,9):
				var point := Vector3(x*0.04,height,z*0.04)
				var blocked := false
				for part in parts:
					if part.bounds.grow(margin).has_point(point) and part.clearance(point) < margin: blocked = true
				assert_eq(blocked,collision.get_body_clearance(point)<margin,"slice pruning cannot open a false route")

func test_returned_control_sheds_offset_only_with_pointer_motion() -> void:
	var app := add_to_tree(load("res://scenes/main/play.tscn").instantiate()) as AppController
	app.process_mode = Node.PROCESS_MODE_DISABLED
	app.handle_action(&"ground")
	var interaction := app.interaction_manager._rope_interaction
	var sim := app.rope.get_simulation()
	var camera := app.camera_rig.get_camera()
	var screen := camera.unproject_position(sim.get_point(app.rope.config.segment_count))
	interaction.begin(screen)
	interaction._grab_offset = -camera.global_basis.x*0.08
	interaction._returning_control = true
	interaction.move(screen+Vector2(2,0))
	var offset := interaction._grab_offset
	assert_true(offset.length() < 0.08 and offset.length() > 0,"handoff corrects gradually")
	for i in 30: interaction.tick(1.0/60)
	assert_eq(interaction._grab_offset,offset,"idle time does not pull the hand toward the cursor")
	for i in range(2,51): interaction.move(screen+Vector2(i*2,0))
	assert_true(interaction._grab_offset.length() < 0.0001,"continued motion restores direct control")

func test_wrap_route_preserves_the_expressed_entry_side() -> void:
	var collision := _collision()
	for side in [-1.0,1.0]:
		var intent := SurfaceIntent.new()
		var point := Vector3(0,0,0.514)
		intent.begin(point,Vector2.ZERO)
		intent.active = true
		intent.rear = true
		intent._via = Vector3(side*0.514,0,0)
		intent._via_pending = true
		intent.requested_goal = Vector3(0,0,-0.514)
		for i in 220:
			point = intent._advance(point,0.012,collision,0.01,PackedVector3Array(),-1)
			assert_true(point.x*side >= -0.025,"same destination must not erase the player's chosen side")
		assert_true(point.distance_to(intent.requested_goal) < 0.025,"expressed side still reaches the requested rear destination")

func test_changed_direction_cancels_pending_wrap() -> void:
	var camera := _camera()
	var collision := _collision()
	var point := Vector3(0,0,0.6)
	var screen := camera.unproject_position(point)
	var intent := SurfaceIntent.new()
	intent.begin(point,screen)
	intent.active = true
	intent.rear = true
	intent._via_pending = true
	intent._wrap_direction = Vector2.RIGHT
	for i in range(1,6): intent.update(screen-Vector2(i*2,0),camera,point,0.012,collision,point)
	assert_true(not intent._via_pending and not intent.rear,"withdrawal cancels the pending rear interpretation")

func test_loaded_hand_can_turn_and_retreat_without_more_lead() -> void:
	var collision := RopeCollision.new()
	collision.floor_enabled = false
	var intent := SurfaceIntent.new()
	intent._target = Vector3.RIGHT*0.048
	intent.requested_goal = Vector3.FORWARD
	var turned := intent._advance(Vector3.ZERO,0.012,collision,0.02,PackedVector3Array(),-1)
	assert_true(turned.z < -0.005,"a loaded grip can steer tangentially without waiting for zero lag")
	assert_true(turned.length() <= 0.048001,"steering cannot increase the hand lead")
	assert_true(turned.distance_to(Vector3.RIGHT*0.048) <= 0.020001,"steering is bounded by expressed motion")
	intent.requested_goal = -turned
	var reversed := intent._advance(Vector3.ZERO,0.012,collision,0.02,PackedVector3Array(),-1)
	assert_true(reversed.length() < turned.length()-0.01,"retreat reduces the loaded gap immediately")

func _camera() -> Camera3D:
	var camera := add_to_tree(Camera3D.new()) as Camera3D
	camera.position = Vector3(0,0,3)
	camera.look_at(Vector3.ZERO)
	return camera

func _collision() -> RopeCollision:
	var part := MannequinPart.new()
	part.primitive = MannequinPart.Primitive.SPHERE
	part.radius = 0.5
	var config := MannequinConfig.new()
	config.parts = [part]
	var collision := RopeCollision.new()
	collision.floor_enabled = false
	collision.configure(config)
	return collision

func _prime(intent: SurfaceIntent,camera: Camera3D,collision: RopeCollision,start: Vector3,screen: Vector2) -> Vector3:
	var result := start
	for i in range(1,11): result = intent.update(screen+Vector2(i*2,0),camera,start,0.012,collision,start)
	return result
