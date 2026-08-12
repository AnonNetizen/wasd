extends Node


const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")

const BOOT_FRAMES: int = 3
const SMOKE_SLOT: String = "slot_save_smoke"
const RUN_KIND: String = SAVE_KINDS.RUN
const META_KIND: String = SAVE_KINDS.META

enum PrimaryFixtureState {
	MISSING,
	CORRUPT,
	INCOMPATIBLE,
}

enum BackupFixtureState {
	VALID,
	CORRUPT,
	INCOMPATIBLE,
}

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
	_expect_primary_backup_matrix()
	_expect_isolation_failure_blocks_backup()
	_expect_environment_mismatch_primary_blocks_valid_backup()
	_expect_meta_migration_chain()
	_expect_run_v19_is_preserved_and_rejected()
	_expect_mod_environment_mismatches_are_preserved()
	_expect_hash_damage_wins_over_environment_mismatch()
	await _expect_formal_boot_preserves_incompatible_backup()

	_set_mod_environment([])
	_cleanup_smoke_files()
	_cleanup_default_run_files()
	_finish()


func _expect_basic_roundtrip() -> void:
	var payload: Dictionary = _run_payload("roundtrip", 3)
	_expect(SaveManager.save(SMOKE_SLOT, RUN_KIND, payload), "run save should write smoke payload")

	var envelope: Dictionary = SaveManager.load_envelope(SMOKE_SLOT, RUN_KIND)
	_expect(not envelope.is_empty(), "run save envelope should load")
	if envelope.is_empty():
		return

	var saved_payload: Dictionary = envelope.get("payload", {}) as Dictionary
	_expect(int(envelope.get("version", 0)) == 20, "run envelope should use Run v20")
	_expect(String(envelope.get("kind", "")) == RUN_KIND, "run envelope kind should match")
	_expect(String(envelope.get("slot", "")) == SMOKE_SLOT, "run envelope slot should match")
	_expect(String(envelope.get("game_version", "")) == "v1.19", "run envelope should use game version v1.19")
	_expect(String(envelope.get("data_hash", "")).length() == 64, "run envelope should contain sha256 data_hash")
	_expect(int(saved_payload.get("schema_version", 0)) == 20, "run payload should be normalized to schema v20")
	_expect(saved_payload.get("mod_environment", null) is Array, "run payload should contain an exact mod_environment array")
	_expect(
		(saved_payload.get("mod_environment", []) as Array) == ModLoader.mod_environment(),
		"run payload mod_environment should match the immutable loader snapshot"
	)
	_expect(String(saved_payload.get("marker", "")) == "roundtrip", "run payload fields should roundtrip")
	_expect(_loaded_versions.has(20), "run load should emit save_loaded v20")


func _expect_primary_backup_matrix() -> void:
	for primary_state: int in [
		PrimaryFixtureState.MISSING,
		PrimaryFixtureState.CORRUPT,
		PrimaryFixtureState.INCOMPATIBLE,
	]:
		for backup_state: int in [
			BackupFixtureState.VALID,
			BackupFixtureState.CORRUPT,
			BackupFixtureState.INCOMPATIBLE,
		]:
			_expect_primary_backup_matrix_case(primary_state, backup_state)


func _expect_isolation_failure_blocks_backup() -> void:
	_cleanup_smoke_files()
	_set_mod_environment([])
	var broken_dir: String = SaveManager.save_root().path_join(".broken")
	if DirAccess.dir_exists_absolute(broken_dir):
		var remove_error: Error = DirAccess.remove_absolute(broken_dir)
		_expect(
			remove_error == OK,
			"isolation-failure fixture should remove the empty broken directory"
		)
		if remove_error != OK:
			return
	_write_text(broken_dir, "broken-directory-blocker")
	var primary_source: String = "{isolation_failure_primary"
	var backup_source: String = _backup_fixture_source(
		BackupFixtureState.VALID
	)
	_write_text(_save_path(), primary_source)
	_write_text(_backup_path(), backup_source)
	var corrupted_before: int = _corrupted_count

	var print_errors_before_load: bool = Engine.print_error_messages
	Engine.print_error_messages = false
	var loaded: Dictionary = SaveManager.load(SMOKE_SLOT, RUN_KIND)
	Engine.print_error_messages = print_errors_before_load
	_expect(
		loaded.is_empty()
		and SaveManager.last_error()
		== "[SaveManager] failed to isolate corrupt save file: %s"
		% _save_path(),
		"failed primary isolation should fail closed before backup fallback"
	)
	_expect(
		_read_text(_save_path()) == primary_source
		and _read_text(_backup_path()) == backup_source,
		"failed primary isolation should preserve primary and backup bytes"
	)
	_expect(
		_corrupted_count == corrupted_before,
		"failed isolation should not claim a corrupt file was quarantined"
	)

	_remove_if_exists(broken_dir)
	_cleanup_smoke_files()


func _expect_primary_backup_matrix_case(
	primary_state: int,
	backup_state: int
	) -> void:
	_cleanup_smoke_files()
	_set_mod_environment([])
	var label: String = "%s primary + %s backup" % [
		_primary_state_label(primary_state),
		_backup_state_label(backup_state),
	]
	var primary_source: String = _primary_fixture_source(primary_state)
	var backup_source: String = _backup_fixture_source(backup_state)
	if not primary_source.is_empty():
		_write_text(_save_path(), primary_source)
	_write_text(_backup_path(), backup_source)
	var before_corrupted_count: int = _corrupted_count

	var loaded: Dictionary = SaveManager.load(SMOKE_SLOT, RUN_KIND)
	var backup_was_attempted: bool = (
		primary_state != PrimaryFixtureState.INCOMPATIBLE
	)
	if backup_state == BackupFixtureState.VALID and backup_was_attempted:
		_expect(
			String(loaded.get("marker", "")) == "matrix_backup_valid",
			"%s should load the valid backup" % label
		)
		_expect(
			SaveManager.last_error().is_empty(),
			"%s should clear last_error after successful fallback" % label
		)
	else:
		_expect(loaded.is_empty(), "%s should fail closed" % label)
		_expect(
			SaveManager.last_error() == _matrix_expected_error(
				primary_state,
				backup_state
			),
			"%s should report the final attempted source error" % label
		)

	var broken_contents: Array[String] = _broken_file_contents()
	var expected_corrupted_delta: int = 0
	match primary_state:
		PrimaryFixtureState.MISSING:
			_expect(
				not FileAccess.file_exists(_save_path()),
				"%s should keep the primary missing" % label
			)
		PrimaryFixtureState.CORRUPT:
			expected_corrupted_delta += 1
			_expect(
				not FileAccess.file_exists(_save_path())
				and broken_contents.has(primary_source),
				"%s should isolate the corrupt primary before fallback" % label
			)
		PrimaryFixtureState.INCOMPATIBLE:
			_expect(
				_read_text(_save_path()) == primary_source,
				"%s should preserve the incompatible primary byte-for-byte"
				% label
			)

	if not backup_was_attempted:
		_expect(
			_read_text(_backup_path()) == backup_source,
			"%s should leave the unattempted backup byte-for-byte unchanged"
			% label
		)
	elif backup_state == BackupFixtureState.CORRUPT:
		expected_corrupted_delta += 1
		_expect(
			not FileAccess.file_exists(_backup_path())
			and broken_contents.has(backup_source),
			"%s should isolate the corrupt backup" % label
		)
	else:
		_expect(
			_read_text(_backup_path()) == backup_source,
			"%s should preserve the valid or incompatible backup byte-for-byte"
			% label
		)
	_expect(
		_corrupted_count == before_corrupted_count + expected_corrupted_delta
		and broken_contents.size() == expected_corrupted_delta,
		"%s should isolate exactly the expected source files" % label
	)


func _primary_fixture_source(state: int) -> String:
	match state:
		PrimaryFixtureState.MISSING:
			return ""
		PrimaryFixtureState.CORRUPT:
			return "{matrix_primary_corrupt"
		PrimaryFixtureState.INCOMPATIBLE:
			return _incompatible_run_source(
				SMOKE_SLOT,
				"matrix_primary_incompatible"
			)
	return ""


func _backup_fixture_source(state: int) -> String:
	match state:
		BackupFixtureState.VALID:
			var payload: Dictionary = _run_payload("matrix_backup_valid", 14)
			payload["mod_environment"] = []
			return JSON.stringify(
				_run_envelope(20, "v1.19", payload),
				"\t"
			)
		BackupFixtureState.CORRUPT:
			return "{matrix_backup_corrupt"
		BackupFixtureState.INCOMPATIBLE:
			return _incompatible_run_source(
				SMOKE_SLOT,
				"matrix_backup_incompatible"
			)
	return ""


func _incompatible_run_source(slot: String, marker: String) -> String:
	var payload: Dictionary = _run_payload(marker, 15)
	payload["schema_version"] = 19
	payload["mod_environment"] = []
	return JSON.stringify(
		_run_envelope(19, "v1.18", payload, slot),
		"\t"
	)


func _matrix_expected_error(primary_state: int, backup_state: int) -> String:
	if primary_state == PrimaryFixtureState.INCOMPATIBLE:
		return "[SaveManager] unsupported run version: 19; expected 20"
	if backup_state == BackupFixtureState.CORRUPT:
		return (
			"[SaveManager] save file is not a JSON object: %s"
			% _backup_path()
		)
	if backup_state == BackupFixtureState.INCOMPATIBLE:
		return "[SaveManager] unsupported run version: 19; expected 20"
	return ""


func _primary_state_label(state: int) -> String:
	match state:
		PrimaryFixtureState.MISSING:
			return "missing"
		PrimaryFixtureState.CORRUPT:
			return "corrupt"
		PrimaryFixtureState.INCOMPATIBLE:
			return "incompatible"
	return "unknown"


func _backup_state_label(state: int) -> String:
	match state:
		BackupFixtureState.VALID:
			return "valid"
		BackupFixtureState.CORRUPT:
			return "corrupt"
		BackupFixtureState.INCOMPATIBLE:
			return "incompatible"
	return "unknown"


func _expect_environment_mismatch_primary_blocks_valid_backup() -> void:
	_cleanup_smoke_files()
	_set_mod_environment([])
	var backup_source: String = _backup_fixture_source(
		BackupFixtureState.VALID
	)
	var payload: Dictionary = _run_payload(
		"environment_mismatch_primary",
		16
	)
	payload["mod_environment"] = [{
		"id": "fixture",
		"version": "1.0.0",
		"gameplay_hash": "recorded_hash",
	}]
	var primary_source: String = JSON.stringify(
		_run_envelope(20, "v1.19", payload),
		"\t"
	)
	_write_text(_save_path(), primary_source)
	_write_text(_backup_path(), backup_source)
	var before_corrupted_count: int = _corrupted_count

	_expect(
		SaveManager.load(SMOKE_SLOT, RUN_KIND).is_empty(),
		"mod-environment-incompatible primary should block a valid backup"
	)
	_expect(
		SaveManager.last_error().contains("run mod environment mismatch"),
		"environment-incompatible primary should keep its mismatch diagnostic"
	)
	_expect(
		_read_text(_save_path()) == primary_source
		and _read_text(_backup_path()) == backup_source,
		"environment-incompatible primary should preserve both files byte-for-byte"
	)
	_expect(
		_corrupted_count == before_corrupted_count
		and _broken_file_count() == 0,
		"environment-incompatible primary and valid backup should not be isolated"
	)


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


func _expect_run_v19_is_preserved_and_rejected() -> void:
	_cleanup_smoke_files()
	_set_mod_environment([])
	var payload: Dictionary = _run_payload("legacy_v19", 6)
	payload["schema_version"] = 19
	payload["mod_environment"] = []
	var envelope: Dictionary = _run_envelope(19, "v1.18", payload)
	var source_text: String = JSON.stringify(envelope, "\t")
	_write_text(_save_path(), source_text)
	var before_corrupted_count: int = _corrupted_count

	_expect(SaveManager.load(SMOKE_SLOT, RUN_KIND).is_empty(), "Run v19 should be rejected without migration")
	_expect(
		SaveManager.last_error() == "[SaveManager] unsupported run version: 19; expected 20",
		"Run v19 rejection should report the exact clean-cut version mismatch"
	)
	_expect(not SaveManager.has_save(SMOKE_SLOT, RUN_KIND), "Run v19 should not appear as continuable")
	var status: Dictionary = SaveManager.save_status(SMOKE_SLOT, RUN_KIND)
	_expect(
		bool(status.get("exists", false))
		and not bool(status.get("compatible", true))
		and bool(status.get("preserved_incompatible", false)),
		"Run v19 status should remain present and explicitly preserved-incompatible"
	)
	_expect(_read_text(_save_path()) == source_text, "Run v19 rejection should preserve the original file")
	_expect(_corrupted_count == before_corrupted_count, "Run v19 rejection should not isolate the source as corrupted")
	_expect(_broken_file_count() == 0, "Run v19 rejection should not create a broken-file copy")


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
	payload["schema_version"] = 20
	payload["mod_environment"] = environment.duplicate(true)
	var envelope: Dictionary = _run_envelope(20, "v1.19", payload)
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
	payload["schema_version"] = 20
	payload["mod_environment"] = recorded_environment
	var envelope: Dictionary = _run_envelope(20, "v1.19", payload)
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


func _expect_formal_boot_preserves_incompatible_backup() -> void:
	_cleanup_default_run_files()
	_set_mod_environment([])
	var primary_path: String = _save_path(SaveManager.DEFAULT_SLOT)
	var backup_path: String = _backup_path(SaveManager.DEFAULT_SLOT)
	var primary_source: String = "{formal_boot_primary_corrupt"
	var backup_source: String = _incompatible_run_source(
		SaveManager.DEFAULT_SLOT,
		"formal_boot_backup_incompatible"
	)
	_write_text(primary_path, primary_source)
	_write_text(backup_path, backup_source)

	var boot: Node = get_parent()
	_expect(
		boot != null
		and boot.has_method("_show_title_menu"),
		"save smoke should run under FormalClientBoot"
	)
	if boot == null or not boot.has_method("_show_title_menu"):
		_cleanup_default_run_files()
		return

	boot.call("_show_title_menu")
	await get_tree().process_frame
	var initial_title_value: Variant = boot.get("_title_menu")
	var continue_button_value: Variant = (
		(initial_title_value as Node).get("_continue_button")
		if initial_title_value is Node
		else null
	)
	_expect(
		initial_title_value is Node
		and is_instance_valid(initial_title_value as Node)
		and continue_button_value is Button
		and (continue_button_value as Button).visible
		and not (continue_button_value as Button).disabled,
		"FormalBoot should expose an enabled title continue button"
	)
	if (
		not initial_title_value is Node
		or not is_instance_valid(initial_title_value as Node)
		or not continue_button_value is Button
		or not (continue_button_value as Button).visible
		or (continue_button_value as Button).disabled
	):
		_cleanup_default_run_files()
		return
	(continue_button_value as Button).emit_signal("pressed")
	_expect(
		GameState.current() == GameState.LOADING,
		"clicking FormalBoot continue should enter LOADING before reading the run"
	)
	var returned_to_title: bool = false
	for _frame: int in range(30):
		await get_tree().process_frame
		if (
			GameState.current() == GameState.MAIN_MENU
			and not bool(boot.get("_player_load_in_progress"))
		):
			returned_to_title = true
			break
	_expect(
		returned_to_title,
		"FormalBoot continue failure should exit LOADING and return to title"
	)
	_expect(
		not FileAccess.file_exists(primary_path)
		and _broken_file_contents(SaveManager.DEFAULT_SLOT).has(primary_source),
		"FormalBoot continue should leave SaveManager's corrupt-primary isolation intact"
	)
	_expect(
		_read_text(backup_path) == backup_source,
		"FormalBoot continue should preserve an incompatible backup byte-for-byte"
	)
	_expect(
		SaveManager.last_error()
		== "[SaveManager] unsupported run version: 19; expected 20",
		"FormalBoot continue should preserve the incompatible-backup diagnostic"
	)
	var title_menu_value: Variant = boot.get("_title_menu")
	_expect(
		title_menu_value is Node
		and is_instance_valid(title_menu_value as Node)
		and String((title_menu_value as Node).get("_notice_key"))
		== "ui_run_save_unavailable",
		"FormalBoot continue should show the unavailable-save notice"
	)
	_cleanup_default_run_files()


func _run_envelope(
	version: int,
	game_version: String,
	payload: Dictionary,
	slot: String = SMOKE_SLOT
	) -> Dictionary:
	return {
		"version": version,
		"kind": RUN_KIND,
		"slot": slot,
		"created_at": "2026-08-10T00:00:00",
		"updated_at": "2026-08-10T00:00:00",
		"game_version": game_version,
		"data_hash": SaveManager.call("_payload_hash", payload),
		"payload": payload,
	}


func _run_payload(marker: String, level: int) -> Dictionary:
	return {
		"schema_version": 20,
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
	_remove_broken_files(SMOKE_SLOT)


func _cleanup_default_run_files() -> void:
	SaveManager.delete(SaveManager.DEFAULT_SLOT, RUN_KIND)
	_remove_if_exists(_save_path(SaveManager.DEFAULT_SLOT))
	_remove_if_exists(_backup_path(SaveManager.DEFAULT_SLOT))
	_remove_if_exists(_tmp_path(SaveManager.DEFAULT_SLOT))
	_remove_broken_files(SaveManager.DEFAULT_SLOT)


func _remove_broken_files(slot: String) -> void:
	var broken_dir: String = SaveManager.save_root().path_join(".broken")
	var dir: DirAccess = DirAccess.open(broken_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry_name: String = dir.get_next()
	while not entry_name.is_empty():
		if (
			not dir.current_is_dir()
			and entry_name.begins_with("%s_%s_" % [slot, RUN_KIND])
		):
			DirAccess.remove_absolute(broken_dir.path_join(entry_name))
		entry_name = dir.get_next()
	dir.list_dir_end()


func _broken_file_count(slot: String = SMOKE_SLOT) -> int:
	return _broken_file_contents(slot).size()


func _broken_file_contents(slot: String = SMOKE_SLOT) -> Array[String]:
	var broken_dir: String = SaveManager.save_root().path_join(".broken")
	var contents: Array[String] = []
	var dir: DirAccess = DirAccess.open(broken_dir)
	if dir == null:
		return contents
	dir.list_dir_begin()
	var entry_name: String = dir.get_next()
	while not entry_name.is_empty():
		if (
			not dir.current_is_dir()
			and entry_name.begins_with("%s_%s_" % [slot, RUN_KIND])
		):
			contents.append(_read_text(broken_dir.path_join(entry_name)))
		entry_name = dir.get_next()
	dir.list_dir_end()
	return contents


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


func _save_path(slot: String = SMOKE_SLOT) -> String:
	return SaveManager.save_root().path_join(slot).path_join("%s.save" % RUN_KIND)


func _meta_save_path() -> String:
	return SaveManager.save_root().path_join(SMOKE_SLOT).path_join("%s.save" % META_KIND)


func _backup_path(slot: String = SMOKE_SLOT) -> String:
	return "%s.bak" % _save_path(slot)


func _tmp_path(slot: String = SMOKE_SLOT) -> String:
	return "%s.tmp" % _save_path(slot)


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
