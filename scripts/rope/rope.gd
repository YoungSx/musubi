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

var _simulation: RopeSimulation
var _collision: RopeCollision
var _accumulator := 0.0
var _held := false
var _last_simulation_ms := 0.0
var _last_mesh_ms := 0.0
var _rendered_radius := -1.0
var _drag_snapshot: Dictionary = {}

@onready var _renderer: RopeRenderer = $RopeRenderer


func _ready() -> void:
	assert(config != null, "Rope requires a RopeConfig.")
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
	var start := _anchor_position(start_anchor, global_position)
	var end := _anchor_position(end_anchor, start + Vector3.DOWN * config.length)
	var points := RopeLayout.hanging(start, end, config.length, config.segment_count)
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


## Input changes solver intent only. Release holds the whole shape, allowing
## the user to orbit, inspect and grab again without losing their arrangement.
func begin_drag(index: int) -> bool:
	var before := _simulation.capture_state()
	if not _simulation.begin_drag(index):
		return false
	_drag_snapshot = {"simulation": before, "held": _held, "accumulator": _accumulator}
	_held = false
	_accumulator = 0.0
	return true


func update_drag_target(target: Vector3) -> void:
	_simulation.update_drag_target(target)


func end_drag() -> void:
	if _simulation.get_drag_index() < 0:
		return
	_simulation.end_drag()
	_drag_snapshot.clear()
	_simulation.stop_motion()
	_held = true
	_accumulator = 0.0
	_refresh_mesh()


func is_held() -> bool:
	return _held


func set_held(held: bool) -> void:
	_held = held
	_accumulator = 0.0


func cancel_drag() -> void:
	if _drag_snapshot.is_empty():
		return
	_simulation = RopeSimulation.restore_state(_drag_snapshot.simulation)
	_simulation.set_collision(_collision)
	_held = _drag_snapshot.held
	_accumulator = _drag_snapshot.accumulator
	_drag_snapshot.clear()
	_refresh_mesh()


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
	if start_anchor != null:
		_simulation.pin(0, start_anchor.global_position)
	if end_anchor != null:
		_simulation.pin(_simulation.get_point_count() - 1, end_anchor.global_position)


static func _anchor_position(anchor: Node3D, fallback: Vector3) -> Vector3:
	return anchor.global_position if anchor != null else fallback
