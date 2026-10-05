class_name RopeHistory
extends RefCounted
## Whole editing transactions, bounded by count and encoded snapshot bytes.
## Physics frames and camera movement never create history entries.
const MAX_ENTRIES := 32
const MAX_BYTES := 4 * 1024 * 1024
var _entries: Array[Dictionary] = []
var _cursor := 0
var _bytes := 0


func record(before: Dictionary, after: Dictionary) -> void:
	if before.is_empty() or after.is_empty() or before == after:
		return
	while _entries.size() > _cursor:
		_bytes -= _entries.pop_back().bytes
	var cost := var_to_bytes(before).size() + var_to_bytes(after).size()
	if cost > MAX_BYTES:
		clear()
		return
	_entries.append({"before": before.duplicate(true), "after": after.duplicate(true), "bytes": cost})
	_bytes += cost
	while _entries.size() > MAX_ENTRIES or _bytes > MAX_BYTES:
		_bytes -= _entries.pop_front().bytes
	_cursor = _entries.size()


func undo(app: Node) -> bool:
	if not can_undo() or not _restore(app, _entries[_cursor - 1].before):
		return false
	_cursor -= 1
	return true


func redo(app: Node) -> bool:
	if not can_redo() or not _restore(app, _entries[_cursor].after):
		return false
	_cursor += 1
	return true


func _restore(app: Node, state: Dictionary) -> bool:
	var restored := state.duplicate(true)
	# Rebuild the matching obstacle pose but keep the user's current view.
	restored.camera = app.camera_rig.capture_state()
	if not MusubiSceneState.apply(app, restored):
		return false
	app.rope_debug.refresh_collision(app.mannequin)
	return true


func can_undo() -> bool:
	return _cursor > 0


func can_redo() -> bool:
	return _cursor < _entries.size()


func clear() -> void:
	_entries.clear()
	_cursor = 0
	_bytes = 0


func get_entry_count() -> int:
	return _entries.size()


func get_encoded_bytes() -> int:
	return _bytes
