class_name RopeDebug
extends Node3D
## Presentation only: lightweight grab feedback plus opt-in physics inspection.

var _rope: Rope
var _hud: Hud
var _enabled := false
var _stats_time := 0.0
var _hint := ""
var _hover_index := -1
var _lines := ImmediateMesh.new()
var _line_node := MeshInstance3D.new()
var _obstacle_node := MeshInstance3D.new()
var _marker := MeshInstance3D.new()


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
	_marker.material_override = marker_material
	_marker.visible = false
	add_child(_marker)
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
	var selected := sim.get_drag_index()
	var marker_index := selected if selected >= 0 else _hover_index
	_marker.visible = marker_index >= 0 and marker_index < sim.get_point_count()
	if _marker.visible:
		_marker.global_position = sim.get_point(marker_index)
		_marker.scale = Vector3.ONE * (1.0 if selected >= 0 else 0.6)
	var hint := "Drag rope · Drag space to orbit"
	if _rope.is_held():
		hint = "Shape held · Grab to continue"
	elif selected >= 0:
		hint = "Shape the rope · Wheel for depth · Release to hold" if OS.has_feature("pc") else "Shape the rope · Release to hold"
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
		_line(_lines, sim.get_point(selected), sim.get_drag_target(), Color.YELLOW)
	_lines.surface_end()
	_stats_time -= delta
	if _stats_time <= 0.0:
		_stats_time = 0.25
		_hud.set_diagnostics("%d FPS · sim %.2f ms · mesh %.2f ms\n%d iterations × %d substeps · %d Hz\nLength %.3f m · stretch %.1f%% · selected %d" % [
			Engine.get_frames_per_second(), _rope.get_last_simulation_ms(), _rope.get_last_mesh_ms(),
			_rope.config.solver_iterations, _rope.config.substeps, _rope.config.simulation_rate,
			sim.get_length(), sim.get_max_segment_stretch() * 100.0, selected])


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
