class_name RopeVisibility
extends RefCounted
## Shared visibility query for picking and context-only occlusion feedback.

static func is_visible(origin: Vector3, point: Vector3, collision: RopeCollision) -> bool:
	if collision == null:
		return true
	var delta := point - origin
	var length := delta.length()
	if length <= 0.0001:
		return true
	var direction := delta / length
	var travelled := 0.0
	for step_index in 128:
		if travelled >= length:
			return true
		var clearance := collision.get_clearance(origin + direction * travelled)
		if clearance < 0.0001:
			return false
		travelled += maxf(clearance * 0.8, 0.0001)
	return false
