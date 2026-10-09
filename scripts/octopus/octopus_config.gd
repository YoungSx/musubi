class_name OctopusConfig
extends Resource
## Tunables for the climbing octopus. Variants (heavier, longer reach, faster
## reel) are new OctopusConfig resources, not new code.

@export_group("Body")
## Adhesion radius: the distance the body center keeps from every surface.
## The mannequin's thinnest limbs are 0.042 m, so this stays well below them.
@export_range(0.01, 0.2, 0.001, "suffix:m") var body_radius: float = 0.03
## Visual mantle radius. Larger than the adhesion radius so the body reads as
## soft tissue pressed against the surface instead of a floating sphere.
@export_range(0.01, 0.3, 0.001, "suffix:m") var mantle_radius: float = 0.055
@export_range(0.1, 3.0, 0.01, "suffix:m/s") var move_speed: float = 0.55
## Extra distance within which a surface still captures the body. This is what
## lets the octopus crawl around a convex edge instead of launching off it.
@export_range(0.0, 0.2, 0.001, "suffix:m") var cling_range: float = 0.045
@export_range(90.0, 1440.0, 1.0, "suffix:deg/s") var turn_speed_degrees: float = 540.0
@export var gravity: Vector3 = Vector3(0.0, -9.8, 0.0)

@export_group("Arms")
@export_range(3, 12, 1) var arm_count: int = 8
## Beads per arm. All arms share one MultiMesh, so this costs instances rather
## than draw calls; too few leaves visible gaps along a stretched arm.
@export_range(2, 16, 1) var arm_beads: int = 11
## Seconds for the grabbing arm to stretch from the body out to its target.
@export_range(0.02, 1.0, 0.01, "suffix:s") var reach_time: float = 0.18
@export_range(0.02, 1.0, 0.01, "suffix:s") var retract_time: float = 0.12
## Lateral bow of the stretched arm, as a fraction of its span.
@export_range(0.0, 0.6, 0.01) var arm_bow: float = 0.22
## Fraction of `arm_bow` the arm keeps once its hold is taut. The hold is nearly
## rigid, so the arm should not read as a slack rope; kept above zero so it still
## reads as tissue rather than a rod.
@export_range(0.0, 1.0, 0.01) var taut_arm_bow: float = 0.12
## Half-angle of the aim cone used to pick a target along the stick direction.
@export_range(5.0, 90.0, 1.0, "suffix:deg") var aim_cone_degrees: float = 35.0

@export_group("Carry")
## Distance the grabbed material is held from the body center while carried.
@export_range(0.02, 0.6, 0.01, "suffix:m") var carry_offset: float = 0.09
## Rate at which a distant grabbed point is drawn in toward the carry offset.
## This bounds the initial draw-in only: once the hold has closed on the carry
## point it stops rate limiting, so a far grab reels in instead of teleporting
## while a settled hold does not keep trailing the body. The rope solver clamps
## its own grip correction as well, so this is an intent limit rather than a
## guarantee.
@export_range(0.05, 3.0, 0.01, "suffix:m/s") var reel_speed: float = 0.7
## Compliance of the carried grip: inverse stiffness, so smaller is firmer.
## This is the arm's only give once the rope is drawn in. It overrides the
## rope's own `drag_compliance`, which is tuned for a fingertip that should
## yield; an arm clamped onto the rope should not. Kept nonzero so the hold
## still reads as tissue under load rather than a weld.
@export_range(0.000001, 0.001, 0.000001) var carry_compliance: float = 0.00002

@export_group("Camera")
## Height of the camera focus above the body along its local up axis.
@export_range(0.0, 1.0, 0.01, "suffix:m") var focus_height: float = 0.18
## Rate at which the view yaw eases behind sustained movement.
@export_range(0.0, 360.0, 1.0, "suffix:deg/s") var follow_turn_speed_degrees: float = 90.0
## Stick magnitude below which the view holds its current yaw.
@export_range(0.0, 1.0, 0.01) var follow_turn_threshold: float = 0.4


func get_reach_distance() -> float:
	return body_radius + cling_range


func get_aim_cone_cosine() -> float:
	return cos(deg_to_rad(aim_cone_degrees))
