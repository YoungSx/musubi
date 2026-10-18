class_name OctopusLocomotion
extends RefCounted
## Procedural locomotion animation for the octopus mascot model.
##
## Implements squash & stretch, vertical bobbing, crawl-stride waddle,
## motion tilt/pitch, landing impact compression, and idle organic breathing cycles.

var stride_length: float = 0.16
var squash_amount: float = 0.14
var bob_height: float = 0.0035
var waddle_roll_deg: float = 6.5
var forward_pitch_deg: float = 5.0
var idle_breathe_freq: float = 2.4
var idle_breathe_amount: float = 0.035

var _walk_phase: float = 0.0
var _idle_time: float = 0.0
var _move_weight: float = 0.0
var landing_impact: float = 0.0


func trigger_landing_impact(intensity: float = 0.18) -> void:
	landing_impact = intensity


func step(delta: float, speed: float, mascot: Node3D, base_transform: Transform3D, vertical_velocity: float = 0.0, is_airborne: bool = false) -> void:
	if delta <= 0.0 or mascot == null:
		return

	# Smoothly decay landing impact
	if landing_impact > 0.0:
		landing_impact = move_toward(landing_impact, 0.0, 1.2 * delta)

	var is_moving := speed > 0.01
	if is_moving:
		_move_weight = lerpf(_move_weight, clampf(speed / 0.35, 0.25, 1.0), 1.0 - exp(-12.0 * delta))
		_walk_phase += (speed / stride_length) * TAU * delta
	else:
		_move_weight = lerpf(_move_weight, 0.0, 1.0 - exp(-8.0 * delta))

	_idle_time += delta

	# Squash & stretch (volume-preserving)
	var crawl_squash := -sin(_walk_phase) * squash_amount * _move_weight
	var breathe_squash := sin(_idle_time * idle_breathe_freq) * idle_breathe_amount * (1.0 - _move_weight)
	var air_squash := 0.0
	if is_airborne:
		air_squash = -clampf(vertical_velocity * 0.04, -0.15, 0.15)
	var total_squash := crawl_squash + breathe_squash + air_squash + landing_impact
	var sy := clampf(1.0 - total_squash, 0.75, 1.35)
	var sxz := sqrt(1.0 / sy)

	# Vertical bobbing
	var bob_y := absf(sin(_walk_phase)) * bob_height * _move_weight

	# Waddle roll and pitch tilt
	var roll := sin(_walk_phase * 0.5) * deg_to_rad(waddle_roll_deg) * _move_weight
	var pitch := (-deg_to_rad(forward_pitch_deg) + sin(_walk_phase) * deg_to_rad(2.5)) * _move_weight

	# Apply to mascot transform relative to its base transform
	var base_scale := base_transform.basis.get_scale()
	var base_rot := base_transform.basis.orthonormalized()
	var base_origin := base_transform.origin

	var anim_rot := Basis.from_euler(Vector3(pitch, 0.0, roll)) * base_rot
	var scale_vec := Vector3(base_scale.x * sxz, base_scale.y * sy, base_scale.z * sxz)
	var new_basis := anim_rot.scaled(scale_vec)
	var new_origin := base_origin + Vector3(0.0, bob_y, 0.0)

	mascot.transform = Transform3D(new_basis, new_origin)


func get_walk_phase() -> float:
	return _walk_phase


func get_move_weight() -> float:
	return _move_weight


func reset() -> void:
	_walk_phase = 0.0
	_idle_time = 0.0
	_move_weight = 0.0
	landing_impact = 0.0
