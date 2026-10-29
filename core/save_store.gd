extends RefCounted
const Codec = preload("res://core/save_codec.gd")
const World = preload("res://core/world.gd")
var directory: String = "user://saves"
## Deterministic test-only faults. Never configured by save data.
var failure_mode: String = ""

func initialize(path: String = "user://saves") -> void:
	directory = ProjectSettings.globalize_path(path).simplify_path()

func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}

func _path(kind: String, slot: int) -> String:
	return directory.path_join("%s_%d.json" % [kind, slot])

func _read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _error("save read failed: " + error_string(FileAccess.get_open_error()))
	var text := file.get_as_text()
	file.close()
	var decoded := Codec.decode(text)
	if not decoded.ok:
		return decoded
	var valid: Dictionary = World.validate_snapshot(decoded.snapshot)
	if not valid.ok:
		return valid
	return decoded

func _write(snapshot: Dictionary, path: String) -> Dictionary:
	var valid: Dictionary = World.validate_snapshot(snapshot)
	if not valid.ok:
		return valid
	var encoded := Codec.encode(snapshot)
	if not encoded.ok:
		return encoded
	if failure_mode in ["beforewrite", "write_denied", "disk_full"]:
		return _error("injected write permission/space failure")
	var mkdir_error := DirAccess.make_dir_recursive_absolute(directory)
	if mkdir_error != OK:
		return _error("save directory unavailable: " + error_string(mkdir_error))
	var temporary := path + ".tmp"
	var backup := path + ".backup"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _error("temporary save write failed: " + error_string(FileAccess.get_open_error()))
	file.store_string(encoded.text.substr(0, encoded.text.length() / 2) if failure_mode == "truncated" else encoded.text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return _error("temporary save flush failed: " + error_string(write_error))
	var verified := _read(temporary)
	if not verified.ok:
		return _error("temporary save validation failed: " + str(verified.error))
	# Preserve an old VALID file before replacing. Invalid prior files never replace a good backup.
	var had_valid: bool = FileAccess.file_exists(path) and _read(path).ok
	if had_valid:
		var copy_error := DirAccess.copy_absolute(path, backup + ".tmp")
		if copy_error != OK or not _read(backup + ".tmp").ok:
			return _error("cannot preserve previous valid save")
		if FileAccess.file_exists(backup):
			var removal := DirAccess.remove_absolute(backup)
			if removal != OK:
				return _error("cannot replace previous backup")
		if DirAccess.rename_absolute(backup + ".tmp", backup) != OK:
			return _error("cannot commit previous save backup")
	if failure_mode == "replacerenamefail":
		return _error("injected replacement rename failure")
	# Same-directory rename replaces the destination without a remove-then-rename gap.
	var rename_error := DirAccess.rename_absolute(temporary, path)
	if rename_error != OK:
		if had_valid:
			var restored := DirAccess.copy_absolute(backup, path)
			if restored != OK:
				return _error("replacement failed; previous valid save retained in .backup")
		return _error("replacement rename failed: " + error_string(rename_error))
	return {"ok": true, "error": "", "path": path, "snapshot_id": encoded.envelope.snapshot_id}

func save_slot(world, slot: int, overwrite_confirmed: bool = false) -> Dictionary:
	if slot < 1 or slot > 3:
		return _error("invalid manual slot (expected 1..3)")
	var path := _path("manual", slot)
	if FileAccess.file_exists(path) and not overwrite_confirmed:
		return {"ok": false, "error": "overwrite_confirmation_required", "confirmation_required": true}
	return _write(world.snapshot(), path)

func load_slot(world, slot: int, discard_confirmed: bool = false) -> Dictionary:
	if slot < 1 or slot > 3:
		return _error("invalid manual slot (expected 1..3)")
	if not discard_confirmed:
		return {"ok": false, "error": "discard_confirmation_required", "confirmation_required": true}
	var decoded := _read(_path("manual", slot))
	if not decoded.ok:
		return decoded
	return world.restore(decoded.snapshot)

func drain_autosaves(world) -> Dictionary:
	var saved := 0
	# World queues immutable snapshots taken at each real 30-day commit boundary.
	while not world.autosave_snapshots.is_empty():
		var snapshot: Dictionary = world.autosave_snapshots[0]
		var minute: int = snapshot.get("world_minute", 0)
		if snapshot.has("clock"):
			minute = snapshot.clock.get("world_minute", minute)
		var boundary: int = minute / 43200
		if minute <= 0 or minute % 43200 != 0:
			return _error("autosave snapshot is not an exact 30-day boundary")
		var slot: int = ((boundary - 1) % 3) + 1
		var result := _write(snapshot, _path("auto", slot))
		if not result.ok:
			result["saved"] = saved
			return result
		world.autosave_snapshots.pop_front()
		saved += 1
	return {"ok": true, "error": "", "saved": saved}
