class_name SurfaceWalker
extends RefCounted
## Adhesion locomotion over the signed-distance geometry the rope already uses.
##
## Position plus surface normal form a local frame; movement intent is projected
## onto that frame's tangent plane, advanced in strides smaller than the thinnest
## limb and re-snapped to the surface each stride. Because the surface normal
## turns continuously across a convex silhouette, walking over an edge wraps
## around it instead of launching off, which is what makes a body climbable
## without authored climb volumes.
##
## No physics server, no CharacterBody3D, no second copy of the collision
## geometry: RopeCollision is the authority, so the walkable surface cannot
## drift away from the drawn figure or from rope contacts.

enum Contact { AIR, FLOOR, BODY }

var position := Vector3.ZERO
var up := Vector3.UP
var facing := Vector3.FORWARD
var contact := Contact.AIR
var velocity := Vector3.ZERO

var _config: OctopusConfig
var _collision: RopeCollision


func configure(config: OctopusConfig, collision: RopeCollision) -> void:
	_config = config
	_collision = collision


## Snaps onto the nearest surface at or near the requested point, or leaves the
## body airborne when nothing is in range.
func place(point: Vector3, heading := Vector3.FORWARD) -> void:
	velocity = Vector3.ZERO
	position = point
	_snap(point)
	facing = tangent(heading, up)


func is_attached() -> bool:
	return contact != Contact.AIR


## Local frame for the skin: -Z along the facing tangent, +Y along the surface
## normal, so the body lies flat on whatever it is holding onto.
func get_basis() -> Basis:
	var forward := tangent(facing, up)
	if forward == Vector3.ZERO:
		forward = tangent(Vector3.FORWARD, up)
	if forward == Vector3.ZERO:
		forward = tangent(Vector3.RIGHT, up)
	return Basis(up.cross(-forward), up, -forward).orthonormalized()


## intent is a world-space heading whose length is the 0..1 input magnitude.
func step(delta: float, intent: Vector3) -> void:
	if delta <= 0.0 or _collision == null or _config == null:
		return
	if contact == Contact.AIR:
		_step_air(delta)
	else:
		_step_surface(delta, intent)
	_turn(delta, intent)


func _step_surface(delta: float, intent: Vector3) -> void:
	velocity = Vector3.ZERO
	var strength := clampf(intent.length(), 0.0, 1.0)
	if strength < 0.0001:
		return
	var travel := _config.move_speed * strength * delta
	var stride := maxf(_config.body_radius * 0.5, 0.002)
	var strides := mini(16, maxi(1, ceili(travel / stride)))
	var heading := intent / maxf(intent.length(), 0.0001)
	for i in strides:
		var direction := tangent(heading, up)
		if direction == Vector3.ZERO:
			return
		_snap(position + direction * (travel / float(strides)))
		if contact == Contact.AIR:
			# Walked off a ledge with forward momentum rather than stopping dead.
			velocity = direction * (_config.move_speed * strength)
			return
		heading = direction


func _step_air(delta: float) -> void:
	velocity += _config.gravity * delta
	_snap(_collision.constrain_motion(position, position + velocity * delta, _config.body_radius))
	if contact != Contact.AIR:
		velocity = Vector3.ZERO


## Pulls the body onto the surface within reach and adopts its normal as the
## local up axis.
##
## The normal blends between the figure and the floor across a band the width of
## the body, so the crease where a foot meets the floor has a diagonal normal
## and a continuous tangent plane. Taking either surface on its own leaves the
## two corrections fighting in that wedge and the body stops dead.
func _snap(point: Vector3) -> void:
	var reach := _config.get_reach_distance()
	if _clearance(point) > reach:
		position = point
		contact = Contact.AIR
		return
	var settled := point
	var normal := Vector3.ZERO
	for pass_index in 3:
		normal = _normal(settled)
		if normal == Vector3.ZERO:
			break
		var correction := _config.body_radius - _clearance(settled)
		if absf(correction) < 0.00001:
			break
		settled += normal * correction
	if normal == Vector3.ZERO:
		position = point
		contact = Contact.AIR
		return
	position = settled
	up = normal
	contact = Contact.BODY if _body_weight(settled) > 0.5 else Contact.FLOOR


## Signed distance to the nearest surface, figure or floor.
func _clearance(point: Vector3) -> float:
	var body := _collision.get_body_clearance(point)
	if not _collision.floor_enabled:
		return body
	return minf(body, point.y - _collision.floor_height)


## 1 where the figure is the nearer surface, 0 where the floor is, interpolated
## across a body-width band so the crease between them is smooth.
func _body_weight(point: Vector3) -> float:
	if not _collision.floor_enabled:
		return 1.0
	var band := maxf(_config.body_radius, 0.001)
	return smoothstep(-band, band, (point.y - _collision.floor_height) - _collision.get_body_clearance(point))


func _normal(point: Vector3) -> Vector3:
	var weight := _body_weight(point)
	if weight <= 0.0:
		return Vector3.UP
	var body := _collision.get_body_normal(point)
	if body == Vector3.ZERO:
		return Vector3.UP if _collision.floor_enabled else Vector3.ZERO
	if weight >= 1.0 or not _collision.floor_enabled:
		return body
	var blended := body * weight + Vector3.UP * (1.0 - weight)
	return blended.normalized() if blended.length_squared() > 1e-12 else body


func _turn(delta: float, intent: Vector3) -> void:
	var target := tangent(intent, up)
	if target == Vector3.ZERO:
		facing = tangent(facing, up)
		if facing == Vector3.ZERO:
			facing = tangent(Vector3.FORWARD, up)
		return
	var current := tangent(facing, up)
	if current == Vector3.ZERO:
		facing = target
		return
	var limit := deg_to_rad(_config.turn_speed_degrees) * delta
	var angle := current.signed_angle_to(target, up)
	facing = current.rotated(up, clampf(angle, -limit, limit)) if absf(angle) > limit else target


## Maps a stick vector in screen axes onto the surface the body is holding.
##
## The reference direction blends from the camera's forward on flat ground to
## world up on a vertical face, so pushing the stick away from the camera walks
## forward on the floor and climbs straight up a leg instead of pressing
## uselessly into it. Without the blend, stick-forward projects to nothing the
## moment the surface normal faces the camera and the body stops at the first
## vertical surface it meets.
static func camera_intent(stick: Vector2, yaw: float, surface_up: Vector3) -> Vector3:
	if stick.is_zero_approx():
		return Vector3.ZERO
	var view := CameraRig.orbit_basis(yaw, 0.0)
	# Two candidate "stick down" directions, each projected onto the surface and
	# then blended: view.z, which runs from the focus back toward the camera and
	# is what flat ground wants; and world down, which is what a climbable face
	# wants. Blending the projected directions rather than the raw references
	# matters, because a reference can project to nothing on some surface
	# orientation while its projection is always well defined where its weight
	# is high. The camera candidate is aligned with the gravity one first, so
	# the two reinforce across the middle of the range instead of cancelling.
	var flatness := absf(surface_up.dot(Vector3.UP))
	var descent := tangent(Vector3.DOWN, surface_up)
	var screen := tangent(view.z, surface_up)
	if screen != Vector3.ZERO and descent != Vector3.ZERO and screen.dot(descent) < 0.0:
		screen = -screen
	var forward := (screen * flatness + descent * (1.0 - flatness))
	if forward.length_squared() < 1e-8:
		forward = tangent(view.y, surface_up)
	else:
		forward = forward.normalized()
	if forward == Vector3.ZERO:
		return Vector3.ZERO
	# The frame is orthonormal, so the stick vector keeps its own magnitude and
	# only an overlong one is clamped.
	return (surface_up.cross(forward) * stick.x + forward * stick.y).limit_length(1.0)


## Normalized component of a vector in the plane perpendicular to an axis, or
## zero when the vector is parallel to it. Shared by the skin and camera so the
## surface frame is derived in exactly one place.
static func tangent(vector: Vector3, normal: Vector3) -> Vector3:
	var flat := vector - normal * vector.dot(normal)
	if flat.length_squared() < 1e-12:
		return Vector3.ZERO
	return flat.normalized()
