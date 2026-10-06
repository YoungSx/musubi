class_name PassFixture
extends RefCounted
## Unit/integration aperture fixture; never replaces the main mannequin scene.
static func points(center := Vector3(0, 1, 0), loop_radius := 0.14) -> PackedVector3Array:
	var p := PackedVector3Array([
		center + Vector3(0, 0, 0.14), center + Vector3(0.25, 0.25, 0.16),
		center + Vector3(0.3, 0.2, 0.1), center + Vector3(0.2, 0, 0.02)])
	for i in 25:
		var angle := (TAU - minf(0.2, 0.028 / loop_radius)) * float(i) / 24.0
		p.append(center + Vector3(cos(angle), sin(angle), 0) * loop_radius)
	p.append(center + Vector3(0.3, -0.1, -0.12))
	p.append(center + Vector3(0.4, -0.15, -0.15))
	return p
