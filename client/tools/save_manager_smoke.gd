extends Node


const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")

const BOOT_FRAMES: int = 3
const SMOKE_SLOT: String = "slot_save_smoke"
const RUN_KIND: String = SAVE_KINDS.RUN
const META_KIND: String = SAVE_KINDS.META

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
	_expect_meta_migration_chain()
	_expect_run_v18_is_preserved_and_rejected()
	_expect_mod_environment_mismatches_are_preserved()
	_expect_hash_damage_wins_over_environment_mismatch()

	_set_mod_environment([])
	_cleanup_smoke_files()
	_finish()


func _expect_basic_roundtrip() -> void:
	var payload: Dictionary = _run_payload("roundtrip", 3)
	_expect(SaveManager.save(SMOKE_SLOT, RUN_KIND, payload), "run save should write smoke payload")

	var envelope: Dictionary = SaveManager.load_envelope(SMOKE_SLOT, RUN_KIND)
	_expect(not envelope.is_empty(), "run save envelope should load")
	if envelope.is_empty():
		return

	var saved_payload: Dictionary = envelope.get("payload", {}) as Dictionary
	_expect(int(envelope.get("version", 0)) == 19, "run envelope should use Run v19")
	_expect(String(envelope.get("kind", "")) == RUN_KIND, "run envelope kind should match")
	_expect(String(envelope.get("slot", "")) == SMOKE_SLOT, "run envelope slot should match")
	_expect(String(envelope.get("game_version", "")) == "v1.18", "run envelope should use game version v1.18")
	_expect(String(envelope.get("data_hash", "")).length() == 64, "run envelope should contain sha256 data_hash")
	_expect(int(saved_payload.get("schema_version", 0)) == 19, "run payload should be normalized to schema v19")
	_expect(saved_payload.get("mod_environment", null) is Array, "run payload should contain an exact mod_environment array")
	_expect(
		(saved_payload.get("mod_environment", []) as Array) == ModLoader.mod_environment(),
		"run payload mod_environment should match the immutable loader snapshot"
	)
	_expect(String(saved_payload.get("marker", "")) == "roundtrip", "run payload fields should roundtrip")
	_expect(_loaded_versions.has(19), "run load should emit save_loaded v19")


func _expect_backup_fallback_and_broken_isolation() -> void:
	_cleanup_smoke_files()
	var backup_payload: Dictionary = _run_payload("backup", 4)
	var primary_payload: Dictionary = _run_payload("primary", 5)
	_expect(SaveManager.save(SMOKE_SLOT, RUN_KIND, backup_payload), "first run save should create primary file")
	_expect(SaveManager.save(SMOKE_SLOT, RUN_KIND, primary_payload), "second run save should create backup")
	_expect(FileAccess.file_exists(_save_path()), "primary run save should exist")
	_expect(FileAccess.file_exists(_backup_path()), "backup run save should exist")

	_write_text(_save_path(), "{broken")
	var recovered_payload: Dictionary = SaveManager.load(SMOKE_SLOT, RUN_KIND)
	_expect(String(recovered_payload.get("marker", "")) == "backup", "bad primary should fall back to backup payload")

	var before_corrupted_count: int = _corrupted_count
	_write_text(_backup_path(), "{also_broken")
	var failed_payload: Dictionary = SaveManager.load(SMOKE_SLOT, RUN_KIND)
	_expect(failed_payload.is_empty(), "bad primary and bad backup should fail closed")
	_expect(_corrupted_count >= before_corrupted_count + 2, "bad primary and backup should emit two corruption signals")
	_expect(not FileAccess.file_exists(_save_path()), "bad primary should be moved out of slot")
	_expect(not FileAccess.file_exists(_backup_path()), "bad backup should be moved out of slot")
	_expect(_broken_file_count() >= 2, "bad primary and backup should both be isolated with unique broken names")


func _expect_meta_migration_chain() -> void:
	_cleanup_smoke_files()
	var meta_payload: Dictionary = {
		"gear_mods": {"owned": {"gear_mod_weapon_damage_test": 2}},
		"marker": "meta_v1",
	}
	_expect(SaveManager.save(SMOKE_SLOT, META_KIND, meta_payload), "meta migration fixture should create its slot directory")
	var envelope: Dictionary = SaveManager.load_envelope(SMOKE_SLOT, META_KIND)
	envelope["version"] = 1
	envelope["game_version"] = "v1.0"
	envelope["payload"] = meta_payload
	envelope["data_hash"] = SaveManager.call("_payload_hash", meta_payload)
	_write_json(_meta_save_path(), envelope)

	var migrated_meta: Dictionary = SaveManager.load(SMOKE_SLOT, META_KIND)
	var composition: Dictionary = migrated_meta.get("hero_composition", {}) as Dictionary
	_expect(String(composition.get("main_hero_id", "")) == "character_primary_a", "Meta v1->v2 should default the main hero")
	_expect(String(composition.get("sub_hero_id", "")) == "character_primary_b", "Meta v1->v2 should default the sub hero")
	_expect(not migrated_meta.has("gear_mods"), "Meta v2->v3 should remove retired account-level Gear Mod state")
	_expect(migrated_meta.get("content_progression", null) is Dictionary, "Meta v3->v4 should add sparse content progression")
	_expect(String(migrated_meta.get("marker", "")) == "meta_v1", "Meta migration should preserve unrelated fields")
	for step: String in ["meta:1:2", "meta:2:3", "meta:3:4"]:
		_expect(_migrated_steps.has(step), "Meta migration should emit save_migrated for %s" % step)


func _expect_run_v18_is_preserved_and_rejected() -> void:
	_cleanup_smoke_files()
	_set_mod_environment([])
	var payload: Dictionary = _run_payload("legacy_v18", 6)
	payload["schema_version"] = 18
	payload["mod_environment"] = []
	var envelope: Dictionary = _run_envelope(18, "v1.17", payload)
	var source_text: String = JSON.stringify(envelope, "\t")
	_write_text(_save_path(), source_text)
	var before_corrupted_count: int = _corrupted_count

	_expect(SaveManager.load(SMOKE_SLOT, RUN_KIND).is_empty(), "Run v18 should be rejected without migration")
	_expect(
		SaveManager.last_error() == "[SaveManager] unsupported run version: 18; expected 19",
		"Run v18 rejection should report the exact clean-cut version mismatch"
	)
	_expect(not SaveManager.has_save(SMOKE_SLOT, RUN_KIND), "Run v18 should not appear as continuable")
	var status: Dictionary = SaveManager.save_status(SMOKE_SLOT, RUN_KIND)
	_expect(
		bool(status.get("exists", false))
		and not bool(status.get("compatible", true))
		and bool(status.get("preserved_incompatible", false)),
		"Run v18 status should remain present and explicitly preserved-incompatible"
	)
	_expect(_read_text(_save_path()) == source_text, "Run v18 rejection should preserve the original file")
	_expect(_corrupted_count == before_corrupted_count, "Run v18 rejection should not isolate the source as corrupted")
	_expect(_broken_file_count() == 0, "Run v18 rejection should not create a broken-file copy")


func _expect_mod_environment_mismatches_are_preserved() -> void:
	var installed: Dictionary = {
		"id": "fixture",
		"version": "2.0.0",
		"gameplay_hash": "installed_hash",
	}
	var expected: Dictionary = {
		"id": "fixture",
		"version": "2.0.0",
		"gameplay_hash": "installed_hash",
	}

	_set_mod_environment([])
	_expect_preserved_environment_rejection([expected], "missing package")

	_set_mod_environment([installed])
	var wrong_version: Dictionary = expected.duplicate(true)
	wrong_version["version"] = "1.0.0"
	_expect_preserved_environment_rejection([wrong_version], "version mismatch")

	var wrong_hash: Dictionary = expected.duplicate(true)
	wrong_hash["gameplay_hash"] = "recorded_hash"
	_expect_preserved_environment_rejection([wrong_hash], "gameplay hash mismatch")


func _expect_preserved_environment_rejection(environment: Array, label: String) -> void:
	_cleanup_smoke_files()
	var payload: Dictionary = _run_payload("environment_%s" % label.replace(" ", "_"), 7)
	payload["schema_version"] = 19
	payload["mod_environment"] = environment.duplicate(true)
	var envelope: Dictionary = _run_envelope(19, "v1.18", payload)
	var source_text: String = JSON.stringify(envelope, "\t")
	_write_text(_save_path(), source_text)
	var before_corrupted_count: int = _corrupted_count

	_expect(SaveManager.load(SMOKE_SLOT, RUN_KIND).is_empty(), "Run with %s should be rejected" % label)
	_expect(SaveManager.last_error().contains("run mod environment mismatch"), "Run %s should report a mod environment diagnostic" % label)
	_expect(not SaveManager.has_save(SMOKE_SLOT, RUN_KIND), "Run with %s should not appear as continuable" % label)
	var status: Dictionary = SaveManager.save_status(SMOKE_SLOT, RUN_KIND)
	_expect(
		bool(status.get("exists", false))
		and not bool(status.get("compatible", true))
		and bool(status.get("preserved_incompatible", false)),
		"Run with %s should expose preserved_incompatible status" % label
	)
	_expect(_read_text(_save_path()) == source_text, "Run with %s should preserve the original file" % label)
	_expect(_corrupted_count == before_corrupted_count, "Run with %s should not emit corruption" % label)
	_expect(_broken_file_count() == 0, "Run with %s should not be isolated" % label)


func _expect_hash_damage_wins_over_environment_mismatch() -> void:
	_cleanup_smoke_files()
	_set_mod_environment([])
	var recorded_environment: Array[Dictionary] = [{
		"id": "fixture",
		"version": "1.0.0",
		"gameplay_hash": "recorded_hash",
	}]
	var payload: Dictionary = _run_payload("hash_and_environment_damage", 8)
	payload["schema_version"] = 19
	payload["mod_environment"] = recorded_environment
	var envelope: Dictionary = _run_envelope(19, "v1.18", payload)
	envelope["data_hash"] = "0".repeat(64)
	_write_json(_save_path(), envelope)
	var before_corrupted_count: int = _corrupted_count

	var status: Dictionary = SaveManager.save_status(SMOKE_SLOT, RUN_KIND)
	_expect(
		bool(status.get("exists", false))
		and not bool(status.get("compatible", true))
		and not bool(status.get("preserved_incompatible", true)),
		"data_hash damage should not be marked preserved even when mod environment also mismatches"
	)
	_expect(
		String(status.get("error", "")) == "[SaveManager] save data_hash mismatch",
		"data_hash damage should remain the primary diagnostic"
	)
	_expect(SaveManager.has_save(SMOKE_SLOT, RUN_KIND), "ordinary damaged Run should remain actionable before explicit load")
	_expect(SaveManager.load(SMOKE_SLOT, RUN_KIND).is_empty(), "hash-damaged Run should fail to load")
	_expect(SaveManager.last_error() == "[SaveManager] save data_hash mismatch", "hash-damaged Run should not be reclassified as an environment mismatch")
	_expect(not FileAccess.file_exists(_save_path()), "hash-damaged Run should be removed from the active slot")
	_expect(_broken_file_count() == 1, "hash-damaged Run should be isolated exactly once")
	_expect(_corrupted_count == before_corrupted_count + 1, "hash-damaged Run should emit one corruption signal")


func _run_envelope(version: int, game_version: String, payload: Dictionary) -> Dictionary:
	return {
		"version": version,
		"kind": RUN_KIND,
		"slot": SMOKE_SLOT,
		"created_at": "2026-08-10T00:00:00",
		"updated_at": "2026-08-10T00:00:00",
		"game_version": game_version,
		"data_hash": SaveManager.call("_payload_hash", payload),
		"payload": payload,
	}


func _run_payload(marker: String, level: int) -> Dictionary:
	return {
		"schema_version": 19,
		"marker": marker,
		"mode": "mode_standard_survival",
		"character": "character_default",
		"gold_progression": {
			"gold_balance": level * 10,
			"gold_earned_total": level * 10,
		},
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
		"world_events": {
			"controller": {
				"active_continuous_instance_id": "",
				"instances": [],
			},
			"wave_plans": {},
		},
		"spawn_states": {},
		"map": {},
		"module_world": {},
		"player": {},
		"weapon": {},
		"hazards": [],
		"enemies": [],
		"bullets": [],
		"gold_orbs": [],
		"gear_mod_pickups": [],
		"reward_choice": {},
		"content_availability": ContentUnlockSystem.build_run_availability_snapshot(),
		"content_progress_delta": {
			"runs_ended": 0,
			"runs_completed": 0,
			"character_run_completed": {},
			"enemy_defeated_total": 0,
			"enemy_defeated": {},
		},
		"ui_restore": {"state": "playing"},
	}


func _set_mod_environment(entries: Array) -> void:
	var enabled_mods: Array[Dictionary] = []
	for raw_entry: Variant in entries:
		if raw_entry is Dictionary:
			enabled_mods.append((raw_entry as Dictionary).duplicate(true))
	ModLoader.set("_enabled_mods", enabled_mods)


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
	if slot == SMOKE_SLOT:
		_migrated_steps.append("%s:%d:%d" % [kind, from_version, to_version])


func _on_save_corrupted(slot: String, kind: String, _path: String, _error: String) -> void:
	if slot == SMOKE_SLOT and kind == RUN_KIND:
		_corrupted_count += 1


func _cleanup_smoke_files() -> void:
	SaveManager.delete(SMOKE_SLOT, RUN_KIND)
	SaveManager.delete(SMOKE_SLOT, META_KIND)
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
	var make_dir_error: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if make_dir_error != OK:
		_expect(false, "smoke should create save directory: %s" % path.get_base_dir())
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_expect(false, "smoke should open save path: %s" % path)
		return
	file.store_string(content)
	file.flush()


func _write_json(path: String, value: Dictionary) -> void:
	_write_text(path, JSON.stringify(value, "\t"))


func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _save_path() -> String:
	return SaveManager.save_root().path_join(SMOKE_SLOT).path_join("%s.save" % RUN_KIND)


func _meta_save_path() -> String:
	return SaveManager.save_root().path_join(SMOKE_SLOT).path_join("%s.save" % META_KIND)


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
