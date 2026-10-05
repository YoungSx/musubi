class_name RopeConfig
extends Resource
## Physical parameters of a rope. Rope presets (soft, stiff, cord, thick) are
## new RopeConfig resources, not new code.

@export_range(0.1, 10.0, 0.01, "suffix:m") var length: float = 1.4
@export_range(2, 256, 1) var segment_count: int = 48
@export_range(0.002, 0.05, 0.001, "suffix:m") var radius: float = 0.012
@export var gravity: Vector3 = Vector3(0.0, -9.8, 0.0)
## A soft grab yields to rope length and collision constraints.
@export_range(0.00001, 0.01, 0.00001) var drag_compliance: float = 0.001
@export_range(0.1, 5.0, 0.1, "suffix:m/s") var drag_speed: float = 1.5
## Exponential velocity decay rate per second. 0 keeps all momentum.
@export_range(0.0, 20.0, 0.01) var damping: float = 0.8
## XPBD compliance of the distance constraints (inverse stiffness).
## 0 is inextensible; larger values let the rope stretch under load.
@export_range(0.0, 0.01, 0.000001) var stretch_compliance: float = 0.0
## Substeps per simulation step. Each substep integrates and solves on its own,
## which stiffens long ropes far more cheaply than extra iterations.
@export_range(1, 32, 1) var substeps: int = 6
## Constraint iterations per substep.
@export_range(1, 64, 1) var solver_iterations: int = 2
## Contact passes after each distance sweep. Primitive contacts are static.
@export_range(1, 8, 1) var collision_iterations: int = 1
## Fraction of tangential velocity removed when a particle contacts a surface.
@export_range(0.0, 1.0, 0.01) var friction: float = 0.18
@export var self_collision_enabled: bool = true
@export_range(0.0, 1.0, 0.01) var self_friction: float = 0.18
@export_range(30, 480, 1, "suffix:Hz") var simulation_rate: int = 120
## Upper bound on simulation steps per physics tick, so a long frame hitch
## slows the rope down instead of stalling the app.
@export_range(1, 16, 1) var max_steps_per_tick: int = 4


func get_rest_length() -> float:
	return length / float(segment_count)


func get_time_step() -> float:
	return 1.0 / float(simulation_rate)


static func for_length(length_m: float) -> RopeConfig:
	var result := RopeConfig.new()
	if is_equal_approx(length_m, 1.4):
		result.segment_count = 48
	elif is_equal_approx(length_m, 2.2):
		result.segment_count = 72
	elif is_equal_approx(length_m, 3.0):
		result.segment_count = 96
	else:
		return null
	result.length = length_m
	return result


## Numeric ranges are validated by RopeState before this workload check.
func is_scene_supported() -> bool:
	return segment_count * substeps * solver_iterations * collision_iterations <= 8192
