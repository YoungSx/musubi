class_name OctopusGrab
extends RefCounted
## One rope grip owned by the octopus.
##
## It addresses the rope through the same begin_grip/update_drag_target/end_drag
## seam a finger uses, so the solver applies the identical soft positional
## constraint, length limits and contacts. Nothing here reaches into the
## simulation's internals.

## Outside the touch-index range InteractionManager assigns, so the two input
## schemes can never collide over one grip slot.
const GRIP_ID := 4096

var _config: OctopusConfig
var _rope: Rope
var _active := false


func configure(config: OctopusConfig, rope: Rope) -> void:
	_config = config
	_rope = rope


func is_active() -> bool:
	return _active


## Nearest draggable, visible rope point inside the aim cone. Returns -1.0 when
## nothing qualifies. A zero direction drops the cone test and simply takes the
## nearest visible point, which is the conventional twin-stick fallback for a
## tap with no aim.
##
## `view_normal` is the axis the aim carries no information about: a stick has two
## degrees of freedom, so an aim built from one spans the view plane and says
## nothing about depth. Given that axis, the cone is measured on the plane the
## gesture lives in, which is what the player is aiming on. Measuring it against
## the full offset instead would reject material the flick points straight at
## whenever it also sits far up the view axis, at any cone width. Ranking stays
## in world space, because "nearest" is a property of the world, not the screen.
static func pick(rope: Rope, origin: Vector3, direction: Vector3, cone_cosine: float, view_normal := Vector3.ZERO) -> float:
	var simulation := rope.get_simulation()
	if simulation == null:
		return -1.0
	var count := simulation.get_point_count()
	if count < 2:
		return -1.0
	var collision := rope.get_collision()
	var aim := direction.normalized() if direction.length_squared() > 1e-8 else Vector3.ZERO
	var normal := view_normal.normalized() if view_normal.length_squared() > 1e-8 else Vector3.ZERO
	var best := -1
	var best_distance := INF
	for i in count:
		if not rope.can_drag(i):
			continue
		var point := simulation.get_point(i)
		var offset := point - origin
		var distance := offset.length()
		if distance >= best_distance:
			continue
		if aim != Vector3.ZERO and distance > 1e-4 and not _within_cone(offset, aim, normal, cone_cosine):
			continue
		if collision != null and not RopeVisibility.is_visible(origin, point, collision):
			continue
		best = i
		best_distance = distance
	return float(best) / float(count - 1) if best >= 0 else -1.0


## Whether an offset lies inside the aim cone. Without a view normal the test is
## the plain spatial one. With it, both vectors are flattened onto the view plane
## first; an offset that vanishes there projects onto the body itself, so no flick
## direction can disagree with it and it is accepted.
static func _within_cone(offset: Vector3, aim: Vector3, view_normal: Vector3, cone_cosine: float) -> bool:
	if view_normal == Vector3.ZERO:
		return offset.dot(aim) / offset.length() >= cone_cosine
	var planar := offset - view_normal * offset.dot(view_normal)
	if planar.length_squared() <= 1e-8:
		return true
	var planar_aim := aim - view_normal * aim.dot(view_normal)
	if planar_aim.length_squared() <= 1e-8:
		return true
	return planar.normalized().dot(planar_aim.normalized()) >= cone_cosine


## Grabs the picked material. Returns false when the aim finds nothing or the
## rope refuses the grip. `view_normal` is the axis the aim omits; see pick().
func grab(origin: Vector3, direction: Vector3, view_normal := Vector3.ZERO) -> bool:
	if _active or _rope == null or _config == null:
		return false
	var material_u := pick(_rope, origin, direction, _config.get_aim_cone_cosine(), view_normal)
	if material_u < 0.0:
		return false
	if not _rope.begin_grip(material_u, GRIP_ID):
		return false
	_active = true
	return true


func get_position() -> Vector3:
	if not _active:
		return Vector3.ZERO
	return _rope.get_simulation().get_grip_position(GRIP_ID)


## Draws the held material toward the carry point at a bounded rate. The solver
## clamps its own correction as well, so a far grab reels in instead of
## teleporting the rope to the body.
func carry(goal: Vector3, delta: float) -> void:
	if not _active:
		return
	var current := get_position()
	var step := (goal - current).limit_length(_config.reel_speed * maxf(delta, 0.0))
	_rope.update_drag_target(current + step, GRIP_ID)


func release() -> void:
	if not _active:
		return
	_active = false
	_rope.end_drag(GRIP_ID)
