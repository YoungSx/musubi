class_name MusubiSceneState
extends RefCounted
## Versioned local scene files. Loading validates all modules before mutation.
## Resource paths identify already loaded presets; files cannot load resources.

const VERSION := 1
const MAX_FILE_BYTES := 4 * 1024 * 1024
const OBSTACLE_PRESETS := ["res://data/mannequin/default_mannequin.tres"]


static func capture(app: Node) -> Dictionary:
	var rope_state: Dictionary = app.rope.capture_scene_state()
	if rope_state.is_empty():
		return {}
	var pose: Transform3D = app.mannequin.global_transform
	return {
		"version": VERSION,
		"rope": rope_state,
		"camera": app.camera_rig.capture_state(),
		"mannequin": {
			"config_path": app.mannequin.config.resource_path,
			"origin": _encode_vector(pose.origin),
			"basis": [_encode_vector(pose.basis.x), _encode_vector(pose.basis.y), _encode_vector(pose.basis.z)],
		},
	}


static func validate(app: Node, data: Dictionary) -> bool:
	var version: Variant = data.get("version")
	if not (version is int or version is float) or version != VERSION:
		return false
	if not data.get("rope") is Dictionary or not data.get("camera") is Dictionary or not data.get("mannequin") is Dictionary:
		return false
	if not app.rope.validate_scene_state(data.rope) or not app.camera_rig.validate_state(data.camera):
		return false
	var mannequin: Dictionary = data.mannequin
	if mannequin.get("config_path") not in OBSTACLE_PRESETS:
		return false
	if not _valid_vector(mannequin.get("origin")):
		return false
	var axes: Variant = mannequin.get("basis")
	if not axes is Array or axes.size() != 3:
		return false
	for axis in axes:
		if not _valid_vector(axis):
			return false
	var basis := _decode_transform(mannequin).basis
	var scale := Vector3(basis.x.length(), basis.y.length(), basis.z.length())
	# Collision supports rotation and positive uniform scale, not shear/mirroring.
	if not scale.is_finite() or scale.x < 0.00001 or not is_equal_approx(scale.x, scale.y) or not is_equal_approx(scale.x, scale.z):
		return false
	var normalized := basis.scaled(Vector3.ONE / scale.x)
	return normalized.is_finite() and normalized.is_conformal() and is_equal_approx(normalized.determinant(), 1.0)


static func apply(app: Node, data: Dictionary) -> bool:
	if not validate(app, data):
		return false
	# Cancel captured pointers only after the complete snapshot is accepted.
	app.interaction_manager.reset()
	if app.mannequin.config.resource_path != data.mannequin.config_path:
		app.mannequin.config = load(data.mannequin.config_path) as MannequinConfig
	app.mannequin.global_transform = _decode_transform(data.mannequin)
	var collision := RopeCollision.new()
	collision.configure(app.mannequin.config, app.mannequin.global_transform)
	app.rope.set_collision(collision)
	app.rope.restore_scene_state(data.rope)
	app.set_play_mode(app.rope.initial_layout != Rope.InitialLayout.HANGING)
	app.camera_rig.restore_state(data.camera)
	return true


## Writes alongside the destination, then replaces it after a successful flush.
static func write_file(path: String, data: Dictionary) -> Error:
	if data.is_empty():
		return ERR_INVALID_DATA
	var text := JSON.stringify(data, "\t", true, true)
	if text.to_utf8_buffer().size() > MAX_FILE_BYTES:
		return ERR_OUT_OF_MEMORY
	var temporary := "%s.tmp-%s-%s" % [path, OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
	return error


static func read_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	if file.get_length() > MAX_FILE_BYTES:
		file.close()
		return {}
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	return json.data if error == OK and json.data is Dictionary else {}


static func _encode_vector(point: Vector3) -> Array:
	return [point.x, point.y, point.z]


static func _valid_vector(value: Variant) -> bool:
	if not value is Array or value.size() != 3:
		return false
	for coordinate in value:
		if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)):
			return false
	return Vector3(value[0], value[1], value[2]).is_finite()


static func _decode_transform(data: Dictionary) -> Transform3D:
	var basis := Basis()
	for index in 3:
		basis[index] = Vector3(data.basis[index][0], data.basis[index][1], data.basis[index][2])
	return Transform3D(basis, Vector3(data.origin[0], data.origin[1], data.origin[2]))
