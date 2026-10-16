class_name OctopusSkin
extends MultiMeshInstance3D
## Draws the dynamic reaching arm when extending/holding rope, while the
## mascot's integrated 3D model displays the resting tentacle feet.
##
## Presentation only: it holds no simulation state and never decides anything.
## Reusing MultiMesh keeps arm draw calls minimal.

## World-space instance transforms; the body transform arrives as a parameter.
@export var top_level_arms := true

var _config: OctopusConfig
var _time := 0.0


func configure(config: OctopusConfig) -> void:
	_config = config
	top_level = top_level_arms
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = _bead_mesh()
	multimesh.instance_count = config.arm_count * config.arm_beads


func _process(delta: float) -> void:
	_time += delta


## The reaching arm follows the supplied curve; resting arms are tucked
## away so the mascot model's integrated tentacle feet are cleanly shown.
func update_arms(body: Transform3D, reach_curve: PackedVector3Array) -> void:
	if _config == null or multimesh == null:
		return
	var beads := _config.arm_beads
	var is_reaching := (reach_curve.size() == beads)
	for arm in _config.arm_count:
		if arm == 0 and is_reaching:
			for bead in beads:
				var t := float(bead) / float(maxi(beads - 1, 1))
				var radius := _config.mantle_radius * lerpf(0.32, 0.06, t * t)
				multimesh.set_instance_transform(
					bead,
					Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * radius), reach_curve[bead])
				)
		else:
			for bead in beads:
				multimesh.set_instance_transform(
					arm * beads + bead,
					Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), body.origin)
				)


static func idle_curve(body: Transform3D, arm: int, config: OctopusConfig, time: float) -> PackedVector3Array:
	var beads := config.arm_beads
	var count := maxi(config.arm_count, 1)
	var angle := PI + TAU * (float(arm) + 0.5) / float(count) * 0.78
	var outward := (body.basis.x * sin(angle) - body.basis.z * cos(angle)).normalized()
	var phase := sin(time * 1.7 + float(arm) * 1.9)
	var curl := phase * 0.3
	var length := config.mantle_radius * (2.1 + 0.45 * sin(float(arm) * 2.3))
	var points := PackedVector3Array()
	points.resize(beads)
	for bead in beads:
		var t := float(bead) / float(maxi(beads - 1, 1))
		var span := config.mantle_radius * 0.5 + length * t
		var droop := config.body_radius * (2.4 * t * t - 0.5 * t) * (1.0 + 0.3 * phase)
		var side := body.basis.y.cross(outward) * (span * curl * t)
		points[bead] = body.origin + outward * span + side - body.basis.y * droop
	return points


static func _bead_mesh() -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh
