class_name Rope
extends Node3D
## Scene-facing rope: owns one RopeSimulation and feeds a RopeRenderer.
##
##   anchors -> pins -> RopeSimulation (fixed steps) -> centerline -> RopeRenderer
##
## Simulation runs at RopeConfig.simulation_rate independent of the display
## rate, so behaviour is identical at 60 Hz and 120 Hz (ProMotion). Anchors are
## optional; a missing anchor leaves that end free.

@export var config: RopeConfig
@export var start_anchor: Node3D
@export var end_anchor: Node3D
enum InitialLayout { HANGING, DRAPED }
@export var initial_layout: InitialLayout = InitialLayout.HANGING
@export var hold_on_release := true
signal edit_completed(before: Dictionary, after: Dictionary)

var _simulation: RopeSimulation
var _collision: RopeCollision
var _accumulator := 0.0
var _held := false
var _last_simulation_ms := 0.0
var _last_mesh_ms := 0.0
var _rendered_radius := -1.0
var _drag_snapshot: Dictionary = {}
var _start_attached := false
var _end_attached := false
var _initial_start_position := Vector3.ZERO
var _initial_end_position := Vector3.ZERO

@onready var _renderer: RopeRenderer = $RopeRenderer


func _ready() -> void:
	assert(config != null, "Rope requires a RopeConfig.")
	_initial_start_position = _anchor_position(start_anchor, global_position)
	_initial_end_position = _anchor_position(end_anchor, _initial_start_position + Vector3.DOWN * config.length)
	reset()


func _process(delta: float) -> void:
	var started := Time.get_ticks_usec()
	var steps := advance(delta)
	_last_simulation_ms = float(Time.get_ticks_usec() - started) / 1000.0
	_last_mesh_ms = 0.0
	if steps > 0 or _rendered_radius != config.radius:
		_refresh_mesh()


## Advances the simulation by wall-clock time using fixed steps. Returns the
## number of steps taken.
func advance(delta: float) -> int:
	if _held:
		return 0
	var dt := config.get_time_step()
	_accumulator += delta
	var steps := 0
	while _accumulator >= dt and steps < config.max_steps_per_tick:
		_sync_anchors()
		_simulation.step(dt)
		_accumulator -= dt
		steps += 1
	# Drop any backlog after a hitch instead of spiralling.
	_accumulator = minf(_accumulator, dt)
	return steps


## Lays the rope out in its rest shape between the anchors.
func reset() -> void:
	config = config.duplicate() as RopeConfig
	config.self_collision_enabled = true
	if start_anchor != null:
		start_anchor.global_position = _initial_start_position
	if end_anchor != null:
		end_anchor.global_position = _initial_end_position
	_start_attached = start_anchor != null and initial_layout == InitialLayout.HANGING
	_end_attached = end_anchor != null and initial_layout == InitialLayout.HANGING
	var start := _anchor_position(start_anchor, global_position)
	var end := _anchor_position(end_anchor, start + Vector3.DOWN * config.length)
	var points := RopeLayout.hanging(start, end, config.length, config.segment_count)
	if initial_layout == InitialLayout.DRAPED:
		points = RopeLayout.shoulder_drape(config.length, config.segment_count)
	_simulation = RopeSimulation.new(config, points)
	_simulation.set_collision(_collision)
	_accumulator = 0.0
	_held = false
	_drag_snapshot.clear()
	_sync_anchors()
	_refresh_mesh()


func get_simulation() -> RopeSimulation:
	return _simulation


func set_collision(collision: RopeCollision) -> void:
	_collision = collision
	if _simulation != null:
		_simulation.set_collision(collision)


func get_collision() -> RopeCollision:
	return _collision


func new_rope(length_m: float) -> bool:
	var preset := RopeConfig.for_length(length_m)
	if preset == null or _simulation.get_drag_index() >= 0:
		return false
	config = preset
	if initial_layout == InitialLayout.DRAPED:
		config.drag_compliance = 0.00008
		config.damping = 4.0
		config.friction = 0.35
	reset()
	return true


func set_endpoint_attached(side: int, attached: bool) -> bool:
	if side not in [0, 1] or _simulation.get_drag_index() >= 0:
		return false
	var anchor := start_anchor if side == 0 else end_anchor
	if anchor == null:
		return false
	var index := 0 if side == 0 else _simulation.get_point_count() - 1
	if attached:
		anchor.global_position = _simulation.get_point(index)
		_simulation.pin(index, anchor.global_position)
	else:
		_simulation.unpin(index)
	if side == 0:
		_start_attached = attached
	else:
		_end_attached = attached
	_simulation.stop_motion()
	set_held(true)
	return true


## Input changes solver intent only. Release holds the whole shape, allowing
## the user to orbit, inspect and grab again without losing their arrangement.
func begin_drag(index: int) -> bool:
	if _simulation.get_drag_index() >= 0 or not can_drag(index):
		return false
	return begin_grip(float(index) / float(_simulation.get_point_count() - 1))


func begin_grip(material_u: float) -> bool:
	if _simulation.get_drag_index() >= 0 or not is_finite(material_u) or material_u < 0 or material_u > 1:
		return false
	var before := capture_scene_state()
	if material_u == 0.0 and _start_attached:
		_start_attached = false
		_simulation.unpin(0)
	if material_u == 1.0 and _end_attached:
		_end_attached = false
		_simulation.unpin(_simulation.get_point_count() - 1)
	if not _simulation.begin_grip(material_u):
		restore_scene_state(before)
		return false
	_drag_snapshot = before
	_held = false
	_accumulator = 0.0
	return true


func update_drag_target(target: Vector3) -> void:
	_simulation.update_drag_target(target)


func end_drag() -> void:
	if _simulation.get_drag_index() < 0:
		return
	var before := _drag_snapshot.duplicate(true)
	if hold_on_release:
		_simulation.end_drag()
		_simulation.stop_motion()
	else:
		_simulation.release_grip()
	_drag_snapshot.clear()
	_held = hold_on_release
	_accumulator = 0.0
	_refresh_mesh()
	edit_completed.emit(before, capture_scene_state())


func is_held() -> bool:
	return _held


func set_held(held: bool) -> void:
	_held = held
	_accumulator = 0.0


func cancel_drag() -> void:
	if _drag_snapshot.is_empty():
		return
	restore_scene_state(_drag_snapshot)


func can_drag(index: int) -> bool:
	if index < 0 or index >= _simulation.get_point_count():
		return false
	return not _simulation.is_pinned(index) or (index == 0 and _start_attached) or (index == _simulation.get_point_count() - 1 and _end_attached)


func is_start_attached() -> bool:
	return _start_attached


func is_end_attached() -> bool:
	return _end_attached


## Scene snapshots deliberately reject active gestures; a saved scene cannot
## recreate a physical pointer or its pre-grab cancellation history.
func capture_scene_state() -> Dictionary:
	if _simulation.get_drag_index() >= 0:
		return {}
	return {"simulation": _simulation.capture_state(), "held": _held,
		"initial_layout": int(initial_layout), "hold_on_release": hold_on_release,
		"accumulator": _accumulator, "start_attached": _start_attached,
		"end_attached": _end_attached, "start_anchor": _encode_anchor(start_anchor),
		"end_anchor": _encode_anchor(end_anchor)}


## Validate the whole payload before touching live nodes or simulation state.
func validate_scene_state(data: Dictionary) -> bool:
	var layout: Variant = data.get("initial_layout", 0)
	if not (layout is int or layout is float) or (layout != 0 and layout != 1) or not data.get("hold_on_release", true) is bool:
		return false
	if not data.get("simulation") is Dictionary or not data.get("held") is bool:
		return false
	if not data.get("start_attached") is bool or not data.get("end_attached") is bool:
		return false
	var accumulator: Variant = data.get("accumulator")
	if not (accumulator is float or accumulator is int) or not is_finite(float(accumulator)):
		return false
	var state := RopeState.decode(data.simulation)
	if state.is_empty() or state.drag_index != -1 or not state.config.is_scene_supported():
		return false
	if accumulator < 0.0 or accumulator > state.config.get_time_step() + 1e-9 or (data.held and accumulator != 0.0):
		return false
	for side in ["start", "end"]:
		var anchor: Node3D = start_anchor if side == "start" else end_anchor
		var attached: bool = data[side + "_attached"]
		var position: Variant = data.get(side + "_anchor")
		if anchor == null:
			if attached or position != null:
				return false
		elif not _valid_anchor_position(position):
			return false
		var index: int = 0 if side == "start" else state.positions.size() - 1
		if (state.inverse_mass[index] == 0.0) != attached:
			return false
		if attached:
			var anchor_point := Vector3(position[0], position[1], position[2])
			if not state.positions[index].is_equal_approx(anchor_point) or not state.previous[index].is_equal_approx(anchor_point):
				return false
	return true


func restore_scene_state(data: Dictionary) -> bool:
	if not validate_scene_state(data):
		return false
	var restored := RopeSimulation.restore_state(data.simulation)
	if restored == null:
		return false
	_simulation = restored
	initial_layout = int(data.get("initial_layout", 0))
	hold_on_release = data.get("hold_on_release", true)
	config = RopeState.decode(data.simulation).config
	_simulation.set_collision(_collision)
	_held = data.held
	_accumulator = float(data.accumulator)
	_start_attached = data.start_attached
	_end_attached = data.end_attached
	if start_anchor != null:
		start_anchor.global_position = Vector3(data.start_anchor[0], data.start_anchor[1], data.start_anchor[2])
	if end_anchor != null:
		end_anchor.global_position = Vector3(data.end_anchor[0], data.end_anchor[1], data.end_anchor[2])
	_drag_snapshot = {}
	_refresh_mesh()
	return true


static func _encode_anchor(anchor: Node3D) -> Variant:
	if anchor == null:
		return null
	var point := anchor.global_position
	return [point.x, point.y, point.z]


static func _valid_anchor_position(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for component in value:
		if not (component is int or component is float) or not is_finite(float(component)) or absf(float(component)) > 1000000.0:
			return false
	return true


func get_last_simulation_ms() -> float:
	return _last_simulation_ms


func get_last_mesh_ms() -> float:
	return _last_mesh_ms


func _refresh_mesh() -> void:
	var started := Time.get_ticks_usec()
	_renderer.update_mesh(_simulation.get_positions(), config.radius)
	_rendered_radius = config.radius
	_last_mesh_ms = float(Time.get_ticks_usec() - started) / 1000.0


func _sync_anchors() -> void:
	if start_anchor != null and _start_attached:
		_simulation.pin(0, start_anchor.global_position)
	if end_anchor != null and _end_attached:
		_simulation.pin(_simulation.get_point_count() - 1, end_anchor.global_position)


static func _anchor_position(anchor: Node3D, fallback: Vector3) -> Vector3:
	return anchor.global_position if anchor != null else fallback
