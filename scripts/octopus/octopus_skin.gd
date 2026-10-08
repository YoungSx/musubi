class_name OctopusSkin
extends MultiMeshInstance3D
## Draws every arm as one tapering bead chain in a single MultiMesh.
##
## Presentation only: it holds no simulation state and never decides anything.
## Reusing MultiMesh keeps all arms in one draw call on mobile and avoids a
## second tube-mesh builder alongside the rope's.

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


## The reaching arm follows the supplied curve; the rest idle around the body.
func update_arms(body: Transform3D, reach_curve: PackedVector3Array) -> void:
	if _config == null or multimesh == null:
		return
	var beads := _config.arm_beads
	for arm in _config.arm_count:
		var curve := reach_curve if arm == 0 and reach_curve.size() == beads else idle_curve(body, arm, _config, _time)
		for bead in beads:
			var t := float(bead) / float(maxi(beads - 1, 1))
			# Strong taper: a chain of equal beads reads as a string of pearls, so
			# the root stays thick and the tip nearly vanishes.
			var radius := _config.mantle_radius * lerpf(0.5, 0.06, t * t)
			multimesh.set_instance_transform(arm * beads + bead, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * radius), curve[bead]))


## Relaxed arm fanned out around the mantle, with a slow phase-offset curl so a
## resting octopus is not rigid.
##
## The fan is biased behind the body and the arms curl back down onto the
## surface, which reads as an octopus. Spacing them evenly on a flat tangent
## plane instead draws a radial star: the arms are several times longer than the
## body's clearance, so they have to bend to stay on the surface they cling to.
static func idle_curve(body: Transform3D, arm: int, config: OctopusConfig, time: float) -> PackedVector3Array:
	var beads := config.arm_beads
	var count := maxi(config.arm_count, 1)
	# Sweep the fan to the rear: -Z is facing, so the arms trail the walk.
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
		# The tip bends toward the surface and then flicks up, so the arm has a
		# silhouette instead of lying straight out.
		var droop := config.body_radius * (2.4 * t * t - 0.5 * t) * (1.0 + 0.3 * phase)
		var side := body.basis.y.cross(outward) * (span * curl * t)
		points[bead] = body.origin + outward * span + side - body.basis.y * droop
	return points


static func _bead_mesh() -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	return mesh
