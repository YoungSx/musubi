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

@onready var _renderer: RopeRenderer = $RopeRenderer


func _ready() -> void:
	assert(config != null, "Rope requires a RopeConfig.")
	reset()


func _process(delta: float) -> void:
	advance(delta)
	_renderer.update_mesh(_simulation.get_positions(), config.radius)


## Advances the simulation by wall-clock time using fixed steps. Returns the
## number of steps taken.
func advance(delta: float) -> int:
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
	_sync_anchors()
	_renderer.update_mesh(_simulation.get_positions(), config.radius)


func get_simulation() -> RopeSimulation:
	return _simulation


func set_collision(collision: RopeCollision) -> void:
	_collision = collision
	if _simulation != null:
		_simulation.set_collision(collision)


func get_collision() -> RopeCollision:
	return _collision


func _sync_anchors() -> void:
	if start_anchor != null:
		_simulation.pin(0, start_anchor.global_position)
	if end_anchor != null:
		_simulation.pin(_simulation.get_point_count() - 1, end_anchor.global_position)


static func _anchor_position(anchor: Node3D, fallback: Vector3) -> Vector3:
	return anchor.global_position if anchor != null else fallback
