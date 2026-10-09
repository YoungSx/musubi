class_name OctopusGrab
extends RefCounted
## One rope grip owned by the octopus.
##
## It addresses the rope through the same begin_grip/update_drag_target/end_drag
## seam a finger uses, so the solver applies the same kind of positional
## constraint, length limits and contacts. Nothing here reaches into the
## simulation's internals.
##
## Where it differs from a finger is stiffness and intent. The grip runs at
## `carry_compliance` instead of the rope's fingertip default, and the carry
## target is the arm's own rather than a step ahead of the material, so the hold
## reads as an arm clamped onto the rope instead of a rubber band trailing it.

## Outside the touch-index range InteractionManager assigns, so the two input
## schemes can never collide over one grip slot.
const GRIP_ID := 4096

var _config: OctopusConfig
var _rope: Rope
var _active := false
var _carry_target := Vector3.ZERO
var _drawn_in := false


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
	_carry_target = _rope.get_simulation().get_grip_position(GRIP_ID)
	_drawn_in = false
	_rope.get_simulation().set_grip_compliance(GRIP_ID, _config.carry_compliance)
	return true


func get_position() -> Vector3:
	if not _active:
		return Vector3.ZERO
	return _rope.get_simulation().get_grip_position(GRIP_ID)


## Draws the held material in to the carry point, then holds it there.
##
## The target is the arm's own, advanced toward the goal at `reel_speed` until it
## arrives and pinned to the goal from then on. It is deliberately not derived
## from where the material currently is: a target that is always one step ahead
## of the material can never ask for more than one step of pull, so the arm would
## trail the body for as long as it walked, which reads as a rubber band rather
## than a held rope. Advancing a target of its own separates the two claims --
## reeling a far grab in takes `distance / reel_speed` whatever the rope does
## about it, and a hold that has arrived asks for the carry point exactly.
##
## Arrival latches for the life of the grip. Walking is slower than reeling, so
## a settled hold would stay settled either way, but latching means no stick
## input or surface can put the rate limit back and make the arm elastic again.
## What give remains is the solver's own, at `carry_compliance`.
func carry(goal: Vector3, delta: float) -> void:
	if not _active:
		return
	if _drawn_in:
		_carry_target = goal
	else:
		var remaining := goal - _carry_target
		var step := _config.reel_speed * maxf(delta, 0.0)
		if remaining.length() <= step:
			_carry_target = goal
			_drawn_in = true
		else:
			_carry_target += remaining.normalized() * step
	_rope.update_drag_target(_carry_target, GRIP_ID)


## Whether the initial draw-in has finished, after which the arm holds the carry
## point rigidly apart from the solver's own compliance.
func is_drawn_in() -> bool:
	return _active and _drawn_in


## Where the arm is asking its material to be. This is the arm's ask, before the
## rope clamps it to what the material can physically reach around its pinned
## ends, so it is the thing to read when the question is what the arm wants
## rather than what the rope allowed.
func get_carry_target() -> Vector3:
	return _carry_target if _active else Vector3.ZERO


func release() -> void:
	if not _active:
		return
	_active = false
	_drawn_in = false
	_carry_target = Vector3.ZERO
	_rope.end_drag(GRIP_ID)
