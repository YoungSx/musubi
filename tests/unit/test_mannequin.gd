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
