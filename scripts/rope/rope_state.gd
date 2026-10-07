class_name RopeState
extends RefCounted
## Versioned JSON data only. Scene transforms and collision configuration are
## owned by the application and must be reattached after restoring a simulation.

const VERSION := 7
const CONFIG_RANGES := {
	"length": Vector2(0.1, 10.0), "segment_count": Vector2(2, 256),
	"radius": Vector2(0.002, 0.05), "damping": Vector2(0, 20),
	"stretch_compliance": Vector2(0, 0.01), "substeps": Vector2(1, 32),
	"solver_iterations": Vector2(1, 64), "collision_iterations": Vector2(1, 8),
	"friction": Vector2(0, 1), "simulation_rate": Vector2(30, 480),
	"max_steps_per_tick": Vector2(1, 16), "drag_compliance": Vector2(0.00001, 0.01),
	"drag_speed": Vector2(0.1, 5),
	"self_friction": Vector2(0, 1),
	"distance_sweeps": Vector2(1, 8),
}


static func encode(config: RopeConfig, positions: PackedVector3Array, previous: PackedVector3Array,
		masses: PackedFloat32Array, last_substep: float, drag_index: int, target: Vector3,
		drag_fraction := 0.0, release_u := -1.0, release_remaining := 0.0) -> Dictionary:
	var parameters := {}
	for key in CONFIG_RANGES:
		parameters[key] = config.get(key)
	parameters["gravity"] = _vector(config.gravity)
	parameters["self_collision_enabled"] = config.self_collision_enabled
	var points: Array = []
	var history: Array = []
	for i in positions.size():
		points.append(_vector(positions[i]))
		history.append(_vector(previous[i]))
	return {"version": VERSION, "config": parameters, "positions": points,
		"previous": history, "inverse_mass": Array(masses), "last_substep": last_substep,
		"drag_index": drag_index, "drag_target": _vector(target), "drag_fraction": drag_fraction,
		"release_u": release_u, "release_remaining": release_remaining, "support": {}, "transport": [], "transport_grip_id": -1, "touch_grips": []}


## Validate before allocating a simulation; malformed payloads return empty.
static func decode(data: Dictionary) -> Dictionary:
	if not _number(data.get("version")) or data.version < 1 or data.version > VERSION or data.version != floor(data.version):
		return {}
	if not data.get("config") is Dictionary:
		return {}
	var config := RopeConfig.new()
	# Old files retain their original simulation behavior on load.
	var enabled: Variant = data.config.get("self_collision_enabled", false if data.version == 1 else null)
	if not enabled is bool:
		return {}
	config.self_collision_enabled = enabled
	for key in CONFIG_RANGES:
		var value: Variant = data.config.get(key, 0.18 if key == "self_friction" and data.version == 1 else null)
		if key == "distance_sweeps" and data.version < 6 and not data.config.has(key): value = 1
		var limits: Vector2 = CONFIG_RANGES[key]
		if not _number(value) or value < limits.x - 1e-9 or value > limits.y + 1e-9:
			return {}
		if config.get(key) is int:
			if value != floor(value):
				return {}
			config.set(key, int(value))
		else:
			config.set(key, float(value))
	if not _valid_vector(data.config.get("gravity")) or not _valid_vector(data.get("drag_target")):
		return {}
	config.gravity = _read_vector(data.config.gravity)
	var count := config.segment_count + 1
	for key in ["positions", "previous", "inverse_mass"]:
		if not data.get(key) is Array or data[key].size() != count:
			return {}
	if not _number(data.get("last_substep")) or data.last_substep < 0:
		return {}
	var drag: Variant = data.get("drag_index")
	if not _number(drag) or drag != floor(drag) or drag < -1 or drag >= count:
		return {}
	var positions := PackedVector3Array()
	var previous := PackedVector3Array()
	var masses := PackedFloat32Array()
	for i in count:
		if not _valid_vector(data.positions[i]) or not _valid_vector(data.previous[i]):
			return {}
		var mass: Variant = data.inverse_mass[i]
		if not _number(mass) or (mass != 0.0 and mass != 1.0):
			return {}
		positions.append(_read_vector(data.positions[i]))
		previous.append(_read_vector(data.previous[i]))
		masses.append(mass)
	var fraction: Variant = data.get("drag_fraction", 0.0 if data.version < 3 else null)
	var release_u: Variant = data.get("release_u", -1.0 if data.version < 3 else null)
	var release_remaining: Variant = data.get("release_remaining", 0.0 if data.version < 3 else null)
	if not _number(fraction) or fraction < 0 or fraction >= 1 or ((drag < 0 or drag == count - 1) and fraction != 0):
		return {}
	if not _number(release_u) or release_u < -1 or release_u > 1 or not _number(release_remaining) or release_remaining < 0 or release_remaining > 0.12:
		return {}
	if release_remaining > 0 and release_u < 0:
		return {}
	if drag >= 0 and masses[int(drag)] * (1.0 - fraction) + masses[mini(int(drag) + 1, count - 1)] * fraction <= 0.0:
		return {}
	var support: Variant = data.get("support", {} if data.version < 4 else null)
	if not support is Dictionary:
		return {}
	var decoded_support := {}
	if not support.is_empty():
		if not _number(support.get("u")) or support.u < 0 or support.u > 1 or not _valid_vector(support.get("target")):
			return {}
		var coordinate: float = support.u * (count - 1)
		var index := floori(coordinate)
		var t := coordinate - index
		if masses[index] * (1.0 - t) + masses[mini(index + 1, count - 1)] * t <= 0 or (drag >= 0 and absf(coordinate - drag - fraction) < 2.0):
			return {}
		decoded_support = {"u": float(support.u), "target": _read_vector(support.target)}
	var transport: Variant = data.get("transport",[] if data.version < 5 else null)
	if not transport is Array or (not transport.is_empty() and transport.size() != count): return {}
	var decoded_transport := PackedVector3Array()
	for point in transport:
		if not _valid_vector(point): return {}
		decoded_transport.append(_read_vector(point))
	var touch_grips: Variant = data.get("touch_grips", [] if data.version < 7 else null)
	if not touch_grips is Array or touch_grips.size() > 32: return {}
	var decoded_grips: Array[Dictionary] = []
	var ids := {}
	for grip: Variant in touch_grips:
		if not grip is Dictionary or not _number(grip.get("id")) or grip.id < 0 or grip.id != floor(grip.id) or grip.id > 2147483647: return {}
		if ids.has(int(grip.id)) or not _number(grip.get("u")) or grip.u < 0 or grip.u > 1 or not _valid_vector(grip.get("target")): return {}
		var coordinate: float = grip.u * (count - 1)
		var index := floori(coordinate)
		var t := coordinate - index
		if masses[index] * (1.0 - t) + masses[mini(index + 1, count - 1)] * t <= 0: return {}
		if not decoded_support.is_empty() and absf(grip.u - decoded_support.u) * (count - 1) < 2.0: return {}
		ids[int(grip.id)] = true
		decoded_grips.append({"id": int(grip.id), "u": float(grip.u), "target": _read_vector(grip.target)})
	var transport_owner: Variant = data.get("transport_grip_id", -1 if data.version < 7 else null)
	if not _number(transport_owner) or transport_owner != floor(transport_owner) or transport_owner < -1: return {}
	if not transport.is_empty() and ((transport_owner == -1 and drag < 0) or (transport_owner >= 0 and not ids.has(int(transport_owner)))): return {}
	if transport.is_empty() and transport_owner != -1: return {}
	return {"config": config, "positions": positions, "previous": previous, "support": decoded_support,"transport":decoded_transport,
		"touch_grips": decoded_grips, "transport_grip_id": int(transport_owner),
		"inverse_mass": masses, "last_substep": float(data.last_substep),
		"drag_index": int(drag), "drag_target": _read_vector(data.drag_target), "drag_fraction": float(fraction),
		"release_u": float(release_u), "release_remaining": float(release_remaining)}


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _valid_vector(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for component in value:
		if not _number(component) or absf(float(component)) > 1000000.0:
			return false
	return true


static func _vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func _read_vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
