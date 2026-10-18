extends TestCase

const MannequinScene := preload("res://scenes/mannequin/mannequin.tscn")


func test_visuals_and_collision_match_config() -> void:
	var mannequin := add_to_tree(MannequinScene.instantiate()) as Mannequin
	var part_count := mannequin.config.parts.size()
	assert_true(part_count > 0, "config has parts")
	assert_eq(mannequin.get_visual_root().get_child_count(), part_count, "one mesh per part")
	assert_eq(mannequin.get_body().get_child_count(), part_count, "one shape per part")
	for i in part_count:
		var mesh := mannequin.get_visual_root().get_child(i) as MeshInstance3D
		var shape := mannequin.get_body().get_child(i) as CollisionShape3D
		assert_true(mesh.transform.is_equal_approx(shape.transform), "part %d mesh/shape aligned" % i)


func test_all_parts_are_valid() -> void:
	var config := load("res://data/mannequin/default_mannequin.tres") as MannequinConfig
	for part in config.parts:
		assert_true(part.is_valid(), "part '%s' valid" % part.part_name)


func test_reset_pose_restores_transform() -> void:
	var mannequin := add_to_tree(MannequinScene.instantiate()) as Mannequin
	var initial := mannequin.transform
	mannequin.rotate_y(1.0)
	mannequin.reset_pose()
	assert_true(mannequin.transform.is_equal_approx(initial), "transform restored")


func test_marble_bust_config_parts_valid() -> void:
	var config := load("res://data/mannequin/marble_bust.tres") as MannequinConfig
	assert_true(config != null, "marble bust config exists")
	assert_true(config.parts.size() >= 5, "marble bust has all primary body parts")
	for part in config.parts:
		assert_true(part.is_valid(), "part '%s' valid" % part.part_name)


func test_custom_visual_scene_bounds_align_with_collision() -> void:
	var mannequin := MannequinScene.instantiate() as Mannequin
	mannequin.config = load("res://data/mannequin/marble_bust.tres") as MannequinConfig
	mannequin.visual_scene = load("res://assets/models/marble_bust_01/marble_bust_01_2k.gltf") as PackedScene
	mannequin.visual_scale = Vector3(3.3786, 3.3786, 3.3786)
	add_to_tree(mannequin)

	var visual_aabb := mannequin.get_visual_aabb()
	var collision_aabb := mannequin.get_collision_aabb()
	assert_true(visual_aabb.size.length() > 0.1, "visual AABB must be non-empty")
	assert_true(collision_aabb.size.length() > 0.1, "collision AABB must be non-empty")

	# Check bounding height match
	var height_diff := absf(visual_aabb.size.y - collision_aabb.size.y)
	assert_true(height_diff < 0.15, "height difference between visual and collision bounds must be < 0.15m (got %.4f)" % height_diff)

	# Check center alignment
	var center_diff := visual_aabb.get_center().distance_to(collision_aabb.get_center())
	assert_true(center_diff < 0.15, "center offset between visual and collision bounds must be < 0.15m (got %.4f)" % center_diff)


func test_custom_visual_surface_clearance_against_collision() -> void:
	var config := load("res://data/mannequin/marble_bust.tres") as MannequinConfig
	var collision := RopeCollision.new()
	collision.configure(config)

	var gltf_scene := load("res://assets/models/marble_bust_01/marble_bust_01_2k.gltf") as PackedScene
	var instance := gltf_scene.instantiate() as Node3D
	instance.scale = Vector3.ONE * 3.3786
	add_to_tree(instance)

	var mesh_instances: Array[MeshInstance3D] = []
	for child in instance.find_children("*", "MeshInstance3D", true, false):
		mesh_instances.append(child as MeshInstance3D)
	assert_true(mesh_instances.size() > 0, "found mesh instances in custom visual")

	var max_surface_error := 0.0
	var sum_surface_error := 0.0
	var sample_count := 0

	for mi in mesh_instances:
		var mesh := mi.mesh
		if mesh == null:
			continue
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var step := maxi(1, vertices.size() / 100)
		for i in range(0, vertices.size(), step):
			var world_v := mi.global_transform * vertices[i]
			var clr := absf(collision.get_body_clearance(world_v))
			max_surface_error = maxf(max_surface_error, clr)
			sum_surface_error += clr
			sample_count += 1

	assert_true(sample_count > 50, "sampled at least 50 surface points")
	var avg_surface_error := sum_surface_error / float(sample_count)
	assert_true(avg_surface_error < 0.12, "average surface deviation from collision must be < 0.12m (got %.4f)" % avg_surface_error)
	assert_true(max_surface_error < 0.30, "max surface deviation from collision must be < 0.30m (got %.4f)" % max_surface_error)


func test_editor_configuration_warnings_and_mismatch_metrics() -> void:
	var mannequin := MannequinScene.instantiate() as Mannequin
	mannequin.config = load("res://data/mannequin/marble_bust.tres") as MannequinConfig
	mannequin.visual_scene = load("res://assets/models/marble_bust_01/marble_bust_01_2k.gltf") as PackedScene
	mannequin.visual_scale = Vector3(3.3786, 3.3786, 3.3786)
	add_to_tree(mannequin)

	var mismatch := mannequin.get_visual_collision_mismatch()
	assert_true(mismatch["is_aligned"], "properly scaled marble bust is aligned")
	assert_true(mismatch["height_diff"] < 0.15, "height diff within 0.15m")
	var warnings := mannequin._get_configuration_warnings()
	assert_eq(warnings.size(), 0, "no configuration warnings when properly aligned")

	# Test warning on missing config
	mannequin.config = null
	mannequin._rebuild()
	var no_config_warnings := mannequin._get_configuration_warnings()
	assert_true(no_config_warnings.size() > 0, "warns when config is null")

	# Test warning on severe mismatch (e.g. unscaled or 10x scaled model)
	mannequin.config = load("res://data/mannequin/marble_bust.tres") as MannequinConfig
	mannequin.visual_scale = Vector3.ONE * 10.0
	mannequin._rebuild()
	var bad_mismatch := mannequin.get_visual_collision_mismatch()
	assert_true(not bad_mismatch["is_aligned"], "detects 10x scaled visual as mismatched")
	var bad_warnings := mannequin._get_configuration_warnings()
	assert_true(bad_warnings.size() > 0, "warns when visual bounds diverge from collision")


func test_automated_collision_fitting_from_visual_scene() -> void:
	var mannequin := MannequinScene.instantiate() as Mannequin
	mannequin.visual_scene = load("res://assets/models/marble_bust_01/marble_bust_01_2k.gltf") as PackedScene
	mannequin.visual_scale = Vector3(3.3786, 3.3786, 3.3786)
	mannequin.config = null
	mannequin.auto_fit = true
	add_to_tree(mannequin)

	assert_true(mannequin.config != null, "auto_fit generates a config from visual_scene")
	assert_true(mannequin.config.parts.size() >= 5, "generates structured anatomical parts")
	for p in mannequin.config.parts:
		assert_true(p.is_valid(), "every generated part satisfies geometric validity")

	var mismatch := mannequin.get_visual_collision_mismatch()
	assert_true(mismatch["is_aligned"], "auto-fitted collision is geometrically aligned with visual mesh")
	assert_true(mismatch["height_diff"] < 0.15, "height diff within 0.15m")
	assert_true(mismatch["center_diff"] < 0.15, "center diff within 0.15m")
