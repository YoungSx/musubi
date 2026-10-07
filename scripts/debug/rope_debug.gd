class_name RopeDebug
extends Node3D
## Presentation only: lightweight grab feedback plus opt-in physics inspection.

var _rope: Rope
var _hud: Hud
var _enabled := false
var play_mode := false
var _stats_time := 0.0
var _extra_grip_markers: Dictionary[int, MeshInstance3D] = {}
var _hint := ""
var _hover_index := -1
var _lines := ImmediateMesh.new()
var _line_node := MeshInstance3D.new()
var _obstacle_node := MeshInstance3D.new()
var _marker := MeshInstance3D.new()
var _target_marker := MeshInstance3D.new()
var _target_lines := ImmediateMesh.new()
var _target_line_node := MeshInstance3D.new()
var _end_labels: Array[Label3D] = []
var _support_marker := MeshInstance3D.new()
var _hand_shadows: Array[MeshInstance3D] = []


func configure(rope: Rope, mannequin: Mannequin, hud: Hud) -> void:
	_rope = rope
	_hud = hud
	_line_node.mesh = _lines
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	line_material.no_depth_test = true
	_line_node.material_override = line_material
	_obstacle_node.material_override = line_material
	add_child(_line_node)
	add_child(_obstacle_node)
	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 0.024
	marker_mesh.height = 0.048
	marker_mesh.radial_segments = 12
	marker_mesh.rings = 6
	_marker.mesh = marker_mesh
	var marker_material := StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.albedo_color = Color("efc98b")
	marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker.material_override = marker_material
	_marker.visible = false
	add_child(_marker)
	_support_marker.mesh = marker_mesh
	var support_material := marker_material.duplicate() as StandardMaterial3D
	support_material.albedo_color = Color("efe8cf")
	_support_marker.material_override = support_material
	_support_marker.visible = false
	add_child(_support_marker)
	for hand in 2:
		var shadow := MeshInstance3D.new()
		var disk := CylinderMesh.new()
		disk.top_radius = 0.04
		disk.bottom_radius = 0.04
		disk.height = 0.001
		disk.radial_segments = 20
		shadow.mesh = disk
		var shade := StandardMaterial3D.new()
		shade.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		shade.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shade.albedo_color = Color(0, 0, 0, 0.22)
		shadow.material_override = shade
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shadow.visible = false
		add_child(shadow)
		_hand_shadows.append(shadow)
	_target_marker.mesh = marker_mesh
	var target_material := marker_material.duplicate() as StandardMaterial3D
	target_material.albedo_color = Color("79cbd1")
	target_material.no_depth_test = true
	_target_marker.material_override = target_material
	_target_marker.scale = Vector3.ONE * 0.55
	_target_marker.visible = false
	add_child(_target_marker)
	_target_line_node.mesh = _target_lines
	_target_line_node.material_override = line_material
	add_child(_target_line_node)
	for name in ["A", "B"]:
		var label := Label3D.new()
		label.text = name
		label.font_size = 32
		label.pixel_size = 0.002
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color("efc98b")
		add_child(label)
		_end_labels.append(label)
	_build_obstacles(mannequin)
	set_debug_enabled(false)


func set_debug_enabled(enabled: bool) -> void:
	_enabled = enabled
	_line_node.visible = enabled
	_obstacle_node.visible = enabled
	_stats_time = 0.0
	if not enabled and _hud != null:
		_hud.set_diagnostics("")
		_lines.clear_surfaces()


func is_debug_enabled() -> bool:
	return _enabled


func set_hover_index(index: int) -> void:
	_hover_index = index


func refresh_collision(mannequin: Mannequin) -> void:
	_build_obstacles(mannequin)


func _process(delta: float) -> void:
	if _rope == null:
		return
	var sim := _rope.get_simulation()
	if _rope.start_anchor != null:
		_rope.start_anchor.visible = _rope.is_start_attached()
	if _rope.end_anchor != null:
		_rope.end_anchor.visible = _rope.is_end_attached()
	var grip_ids := sim.get_grip_ids()
	var first_grip := grip_ids[0] if not grip_ids.is_empty() else -1
	var selected := sim.get_drag_index(first_grip)
	_hud.set_simulation_state(_rope.is_held(), selected >= 0 or _rope.has_support())
	_support_marker.visible = _rope.has_support() and _enabled
	if _support_marker.visible:
		_support_marker.global_position = sim.get_support_position()
	for hand in 2:
		var active := selected >= 0 if hand == 0 else _rope.has_support()
		var point := sim.get_grip_position(first_grip) if hand == 0 else sim.get_support_position()
		_hand_shadows[hand].visible = play_mode and active and point.y < 0.5
		if _hand_shadows[hand].visible:
			_hand_shadows[hand].global_position = Vector3(point.x, 0.003, point.z)
	_hud.set_rope_state(_rope.config.length, _rope.is_start_attached(), _rope.is_end_attached())
	for side in 2:
		_end_labels[side].visible = not play_mode or _enabled
		_end_labels[side].global_position = sim.get_point(0 if side == 0 else sim.get_point_count() - 1) + Vector3.UP * 0.05
	_target_marker.visible = selected >= 0 and (not play_mode or _enabled)
	_target_line_node.visible = not play_mode or _enabled
	_target_lines.clear_surfaces()
	if selected >= 0:
		_target_marker.global_position = sim.get_drag_target(first_grip)
		_target_lines.surface_begin(Mesh.PRIMITIVE_LINES)
		_line(_target_lines, sim.get_grip_position(first_grip), sim.get_drag_target(first_grip), Color("79cbd1"))
		_target_lines.surface_end()
	var marker_index := selected if selected >= 0 else _hover_index
	_marker.visible = marker_index >= 0 and marker_index < sim.get_point_count()
	if _marker.visible:
		_marker.global_position = sim.get_grip_position(first_grip) if selected >= 0 else sim.get_point(marker_index)
		_marker.scale = Vector3.ONE * (1.0 if selected >= 0 else 0.6)
		var camera := get_viewport().get_camera_3d()
		var occluded := false
		if play_mode and selected >= 0 and camera != null:
			occluded = not RopeVisibility.is_visible(camera.project_ray_origin(camera.unproject_position(_marker.global_position)), _marker.global_position, _rope.get_collision())
		var material := _marker.material_override as StandardMaterial3D
		material.no_depth_test = occluded
		material.albedo_color = Color(0.94, 0.79, 0.55, 0.55 if occluded else 1.0)
	for id: int in _extra_grip_markers.keys():
		if id not in grip_ids or id == first_grip:
			_extra_grip_markers[id].queue_free()
			_extra_grip_markers.erase(id)
	for id: int in grip_ids:
		if id == first_grip: continue
		if not _extra_grip_markers.has(id):
			var marker := _marker.duplicate() as MeshInstance3D
			marker.material_override = _marker.material_override.duplicate()
			_marker.get_parent().add_child(marker)
			_extra_grip_markers[id] = marker
		var marker := _extra_grip_markers[id]
		marker.visible = true
		marker.global_position = sim.get_grip_position(id)
		marker.scale = Vector3.ONE
		var camera := get_viewport().get_camera_3d()
		var occluded := play_mode and camera != null and not RopeVisibility.is_visible(camera.project_ray_origin(camera.unproject_position(marker.global_position)), marker.global_position, _rope.get_collision())
		var material := marker.material_override as StandardMaterial3D
		material.no_depth_test = occluded
		material.albedo_color = Color(0.94, 0.79, 0.55, 0.55 if occluded else 1.0)
	var hint := "Drag rope · Drag space to orbit" if OS.has_feature("pc") else "Grab with each finger · Two fingers orbit · Three fingers pan"
	if _rope.is_held():
		hint = "Shape held · Grab to continue"
	elif selected >= 0:
		hint = "Gold: rope · Blue: target · Wheel: depth · Release: hold" if OS.has_feature("pc") else "Shape the rope · Release to hold"
	if _hint != hint:
		_hint = hint
		_hud.set_interaction_hint(hint)
	if not _enabled:
		return
	_lines.clear_surfaces()
	_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in sim.get_point_count():
		var point := sim.get_point(i)
		_line(_lines, point - Vector3.RIGHT * 0.006, point + Vector3.RIGHT * 0.006, Color.CYAN)
		_line(_lines, point - Vector3.UP * 0.006, point + Vector3.UP * 0.006, Color.CYAN)
		if i > 0:
			_line(_lines, sim.get_point(i - 1), point, Color("62bfa4"))
	if selected >= 0:
		_line(_lines, sim.get_grip_position(first_grip), sim.get_drag_target(first_grip), Color.YELLOW)
	_lines.surface_end()
	_stats_time -= delta
	if _stats_time <= 0.0:
		_stats_time = 0.25
		_hud.set_diagnostics("%d FPS · sim %.2f ms · mesh %.2f ms\n%d iterations × %d substeps · %d Hz\nLength %.3f m · stretch %.1f%% · selected %d" % [
			Engine.get_frames_per_second(), _rope.get_last_simulation_ms(), _rope.get_last_mesh_ms(),
			_rope.config.solver_iterations, _rope.config.substeps, _rope.config.simulation_rate,
			sim.get_length(), sim.get_max_segment_stretch() * 100.0, selected] + "\nSelf contact: %s · last pass %d" % ["on" if sim.is_self_collision_enabled() else "off", sim.get_self_contact_count()])


func _build_obstacles(mannequin: Mannequin) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for part in mannequin.config.parts:
		var frame := mannequin.global_transform * part.get_local_transform()
		if part.primitive == MannequinPart.Primitive.BOX:
			var half := part.box_size * 0.5
			for axis in 3:
				for a in [-1.0, 1.0]:
					for b in [-1.0, 1.0]:
						var p := Vector3.ZERO
						p[(axis + 1) % 3] = half[(axis + 1) % 3] * a
						p[(axis + 2) % 3] = half[(axis + 2) % 3] * b
						p[axis] = -half[axis]
						var q := p
						q[axis] = half[axis]
						_line(mesh, frame * p, frame * q, Color("7489a6"))
		else:
			var half_axis := maxf(part.height * 0.5 - part.radius, 0.0) if part.primitive == MannequinPart.Primitive.CAPSULE else 0.0
			for ring in 3:
				for i in 24:
					var a := _ring_point(TAU * float(i) / 24.0, ring, part.radius, half_axis)
					var b := _ring_point(TAU * float(i + 1) / 24.0, ring, part.radius, half_axis)
					_line(mesh, frame * a, frame * b, Color("7489a6"))
	mesh.surface_end()
	_obstacle_node.mesh = mesh


static func _ring_point(angle: float, ring: int, radius: float, half_axis: float) -> Vector3:
	var c := cos(angle) * radius
	var s := sin(angle) * radius
	if ring == 0:
		return Vector3(c, half_axis, s)
	var y := s + (half_axis if s >= 0.0 else -half_axis)
	return Vector3(c, y, 0) if ring == 1 else Vector3(0, y, c)


static func _line(mesh: ImmediateMesh, a: Vector3, b: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(a)
	mesh.surface_add_vertex(b)
