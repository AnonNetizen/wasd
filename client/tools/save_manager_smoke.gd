extends Node


const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")

const BOOT_FRAMES: int = 3
const SMOKE_SLOT: String = "slot_save_smoke"
const RUN_KIND: String = SAVE_KINDS.RUN

var _corrupted_count: int = 0
var _failures: Array[String] = []
var _loaded_versions: Array[int] = []
var _migrated_steps: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	_connect_signals()
	_cleanup_smoke_files()

	for _index: int in range(BOOT_FRAMES):
		await get_tree().process_frame

	_expect_basic_roundtrip()
	_expect_backup_fallback_and_broken_isolation()
	_expect_migration_chain()

	_cleanup_smoke_files()
	_finish()


func _expect_basic_roundtrip() -> void:
	var payload: Dictionary = _run_payload("roundtrip", 3)
	_expect(SaveManager.save(SMOKE_SLOT, RUN_KIND, payload), "run save should write smoke payload")

	var envelope: Dictionary = SaveManager.load_envelope(SMOKE_SLOT, RUN_KIND)
	_expect(not envelope.is_empty(), "run save envelope should load")
	if envelope.is_empty():
		return

	_expect(int(envelope.get("version", 0)) == SaveManager.current_version(RUN_KIND), "run envelope should use current version")
	_expect(String(envelope.get("kind", "")) == RUN_KIND, "run envelope kind should match")
	_expect(String(envelope.get("slot", "")) == SMOKE_SLOT, "run envelope slot should match")
	_expect(String(envelope.get("data_hash", "")).length() == 64, "run envelope should contain sha256 data_hash")
	_expect(_payloads_match(envelope.get("payload", {}), payload), "run payload should roundtrip with stable hash")
	_expect(_loaded_versions.has(SaveManager.current_version(RUN_KIND)), "run load should emit save_loaded")


func _expect_backup_fallback_and_broken_isolation() -> void:
	var backup_payload: Dictionary = _run_payload("backup", 4)
	var primary_payload: Dictionary = _run_payload("primary", 5)
	_expect(SaveManager.save(SMOKE_SLOT, RUN_KIND, backup_payload), "first run save should create primary file")
	_expect(SaveManager.save(SMOKE_SLOT, RUN_KIND, primary_payload), "second run save should create backup")
	_expect(FileAccess.file_exists(_save_path()), "primary run save should exist")
	_expect(FileAccess.file_exists(_backup_path()), "backup run save should exist")

	_write_text(_save_path(), "{broken")
	var recovered_payload: Dictionary = SaveManager.load(SMOKE_SLOT, RUN_KIND)
	_expect(_payloads_match(recovered_payload, backup_payload), "bad primary should fall back to backup payload")

	var before_corrupted_count: int = _corrupted_count
	_write_text(_backup_path(), "{also_broken")
	var failed_payload: Dictionary = SaveManager.load(SMOKE_SLOT, RUN_KIND)
	_expect(failed_payload.is_empty(), "bad primary and bad backup should fail closed")
	_expect(_corrupted_count >= before_corrupted_count + 2, "bad primary and backup should emit two corruption signals")
	_expect(not FileAccess.file_exists(_save_path()), "bad primary should be moved out of slot")
	_expect(not FileAccess.file_exists(_backup_path()), "bad backup should be moved out of slot")
	_expect(_broken_file_count() >= 2, "bad primary and backup should both be isolated with unique broken names")


func _expect_migration_chain() -> void:
	_cleanup_smoke_files()

	var old_payload: Dictionary = _run_payload("migration", 6)
	_expect(SaveManager.save(SMOKE_SLOT, RUN_KIND, old_payload), "old-version run save should write")
	var old_envelope: Dictionary = SaveManager.load_envelope(SMOKE_SLOT, RUN_KIND)
	old_envelope["version"] = 1
	var legacy_payload: Dictionary = old_payload.duplicate(true)
	legacy_payload.erase("pickups")
	old_envelope["payload"] = legacy_payload
	old_envelope["data_hash"] = SaveManager.call("_payload_hash", legacy_payload)
	_write_json(_save_path(), old_envelope)

	var migrated_envelope: Dictionary = SaveManager.load_envelope(SMOKE_SLOT, RUN_KIND)
	_expect(not migrated_envelope.is_empty(), "old-version run save should load through migration")
	if migrated_envelope.is_empty():
		return

	var migrated_payload: Dictionary = migrated_envelope.get("payload", {}) as Dictionary
	_expect(int(migrated_envelope.get("version", 0)) == SaveManager.current_version(RUN_KIND), "migrated envelope should report target version")
	_expect(migrated_payload.get("pickups", null) is Array, "run v1->v2 migration should normalize missing pickup snapshots")
	_expect(_migrated_steps.has("%s:%d:%d" % [RUN_KIND, 1, SaveManager.current_version(RUN_KIND)]), "run migration should emit save_migrated")


func _run_payload(marker: String, level: int) -> Dictionary:
	return {
		"schema_version": 1,
		"mode": "mode_standard_survival",
		"character": "character_default",
		"level": level,
		"xp": level * 10,
		"kills": level - 1,
		"game_clock": {
			"elapsed": float(level),
			"tick": level * 60,
			"time_scale": 1.0,
		},
		"rng": {
			"run_seed": 4242,
			"streams": {
				"spawn": {
					"seed": "123456789012345",
					"state": "987654321098765",
				},
			},
		},
		"spawn_states": {
			"wave_%s" % marker: {
				"next_time": float(level),
				"spawned": level,
				"alive": 1,
			},
		},
		"player": {
			"position": [float(level), float(level + 1)],
			"life": float(level),
			"max_life": float(level + 2),
		},
		"weapon": {
			"cooldown": 0.25,
		},
		"enemies": [],
		"bullets": [],
		"pickups": [],
	}


func _connect_signals() -> void:
	if not SaveManager.save_loaded.is_connected(_on_save_loaded):
		SaveManager.save_loaded.connect(_on_save_loaded)
	if not SaveManager.save_migrated.is_connected(_on_save_migrated):
		SaveManager.save_migrated.connect(_on_save_migrated)
	if not SaveManager.save_corrupted.is_connected(_on_save_corrupted):
		SaveManager.save_corrupted.connect(_on_save_corrupted)


func _on_save_loaded(slot: String, kind: String, version: int, _migrated: bool) -> void:
	if slot == SMOKE_SLOT and kind == RUN_KIND:
		_loaded_versions.append(version)


func _on_save_migrated(slot: String, kind: String, from_version: int, to_version: int) -> void:
	if slot == SMOKE_SLOT and kind == RUN_KIND:
		_migrated_steps.append("%s:%d:%d" % [kind, from_version, to_version])


func _on_save_corrupted(slot: String, kind: String, _path: String, _error: String) -> void:
	if slot == SMOKE_SLOT and kind == RUN_KIND:
		_corrupted_count += 1


func _cleanup_smoke_files() -> void:
	SaveManager.delete(SMOKE_SLOT, RUN_KIND)
	_remove_if_exists(_save_path())
	_remove_if_exists(_backup_path())
	_remove_if_exists(_tmp_path())
	_remove_broken_smoke_files()


func _remove_broken_smoke_files() -> void:
	var broken_dir: String = SaveManager.save_root().path_join(".broken")
	var dir: DirAccess = DirAccess.open(broken_dir)
	if dir == null:
		return

	dir.list_dir_begin()
	var entry_name: String = dir.get_next()
	while not entry_name.is_empty():
		if not dir.current_is_dir() and entry_name.begins_with("%s_%s_" % [SMOKE_SLOT, RUN_KIND]):
			DirAccess.remove_absolute(broken_dir.path_join(entry_name))
		entry_name = dir.get_next()
	dir.list_dir_end()


func _broken_file_count() -> int:
	var broken_dir: String = SaveManager.save_root().path_join(".broken")
	var dir: DirAccess = DirAccess.open(broken_dir)
	if dir == null:
		return 0

	var count: int = 0
	dir.list_dir_begin()
	var entry_name: String = dir.get_next()
	while not entry_name.is_empty():
		if not dir.current_is_dir() and entry_name.begins_with("%s_%s_" % [SMOKE_SLOT, RUN_KIND]):
			count += 1
		entry_name = dir.get_next()
	dir.list_dir_end()
	return count


func _write_text(path: String, content: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_expect(false, "smoke should open save path for corruption: %s" % path)
		return
	file.store_string(content)
	file.flush()


func _write_json(path: String, value: Dictionary) -> void:
	_write_text(path, JSON.stringify(value, "\t"))


func _payloads_match(left: Variant, right: Dictionary) -> bool:
	if not left is Dictionary:
		return false
	return String(SaveManager.call("_payload_hash", left as Dictionary)) == String(SaveManager.call("_payload_hash", right))


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _save_path() -> String:
	return SaveManager.save_root().path_join(SMOKE_SLOT).path_join("%s.save" % RUN_KIND)


func _backup_path() -> String:
	return "%s.bak" % _save_path()


func _tmp_path() -> String:
	return "%s.tmp" % _save_path()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[SaveSmoke] %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("[SaveSmoke] passed; loaded=%d migrated=%d corrupted=%d" % [
			_loaded_versions.size(),
			_migrated_steps.size(),
			_corrupted_count,
		])
		get_tree().quit(0)
		return

	print("[SaveSmoke] failed; failures=%d" % _failures.size())
	get_tree().quit(1)
