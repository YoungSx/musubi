extends TestCase

func test_surface_following_preserves_stationary_intent() -> void:
	var camera := _camera()
	var collision := _collision()
	var start := Vector3(0,0,0.6)
	var cursor := camera.unproject_position(start)
	var intent := SurfaceIntent.new()
	intent.begin(start,cursor)
	var target := intent.update(cursor+Vector2(20,0),camera,start,0.012,collision,start)
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
	var edge := camera.unproject_position(Vector3(0.5,0,0))
	var intent := SurfaceIntent.new()
	intent.begin(start,center)
	intent.update(center+Vector2(20,0),camera,start,0.012,collision,start)
	intent.update(edge+Vector2(30,0),camera,Vector3(0.6,0,0),0.012,collision,start)
	intent.update(edge-Vector2(1,0),camera,start,0.012,collision,start)
	# A fresh rim with a very small return cannot immediately force the rear.
	intent.begin(start,center)
	intent.update(center+Vector2(20,0),camera,start,0.012,collision,start)
	intent._rim = true
	intent._rim_direction = Vector2.RIGHT
	intent.update(center+Vector2(19,0),camera,start,0.012,collision,start)
	assert_true(not intent.rear,"one pixel of reversal is insufficient evidence")
	intent.update(center+Vector2(8,0),camera,start,0.012,collision,start)
	assert_true(intent.rear,"sustained reversal at the rim can continue behind the object")

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
