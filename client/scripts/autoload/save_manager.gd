# Doc: docs/代码/save_manager.md
# Authority: docs/游戏设计文档.md §9.16, docs/决策记录.md ADR #25 / #48
class_name SaveManagerAutoload
extends Node


signal save_written(slot: String, kind: String, path: String)
signal save_loaded(slot: String, kind: String, version: int, migrated: bool)
signal save_deleted(slot: String, kind: String)
signal save_migrated(slot: String, kind: String, from_version: int, to_version: int)
signal save_corrupted(slot: String, kind: String, path: String, error: String)

const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")
const ANALYTICS_EVENTS := preload("res://scripts/contracts/analytics_events.gd")
const CHARACTER_IDS := preload("res://scripts/contracts/character_ids.gd")
const SAVE_ROOT: String = "user://saves"
const BROKEN_DIR_NAME: String = ".broken"
const DEFAULT_SLOT: String = "slot_0"
const GAME_VERSION: String = "v1.18"
const DEFAULT_MAIN_HERO_ID: String = CHARACTER_IDS.CHARACTER_PRIMARY_A
const DEFAULT_SUB_HERO_ID: String = CHARACTER_IDS.CHARACTER_PRIMARY_B
const CURRENT_KIND_VERSIONS: Dictionary = {
	SAVE_KINDS.META: 4,
	SAVE_KINDS.RUN: 19,
	SAVE_KINDS.REPLAY_INDEX: 1,
}

var _migrations: Dictionary = {}
var _last_error: String = ""


func _ready() -> void:
	register_migration(SAVE_KINDS.META, 1, 2, Callable(self, "_migrate_meta_v1_to_v2"))
	register_migration(SAVE_KINDS.META, 2, 3, Callable(self, "_migrate_meta_v2_to_v3"))
	register_migration(SAVE_KINDS.META, 3, 4, Callable(self, "_migrate_meta_v3_to_v4"))
	register_migration(SAVE_KINDS.RUN, 1, 2, Callable(self, "_migrate_run_v1_to_v2"))
	register_migration(SAVE_KINDS.RUN, 2, 3, Callable(self, "_migrate_run_v2_to_v3"))
	register_migration(SAVE_KINDS.RUN, 3, 4, Callable(self, "_migrate_run_v3_to_v4"))
	register_migration(SAVE_KINDS.RUN, 4, 5, Callable(self, "_migrate_run_v4_to_v5"))
	register_migration(SAVE_KINDS.RUN, 5, 6, Callable(self, "_migrate_run_v5_to_v6"))
	register_migration(SAVE_KINDS.RUN, 6, 7, Callable(self, "_migrate_run_v6_to_v7"))
	register_migration(SAVE_KINDS.RUN, 7, 8, Callable(self, "_migrate_run_v7_to_v8"))
	register_migration(SAVE_KINDS.RUN, 8, 9, Callable(self, "_migrate_run_v8_to_v9"))
	register_migration(SAVE_KINDS.RUN, 9, 10, Callable(self, "_migrate_run_v9_to_v10"))
	register_migration(SAVE_KINDS.RUN, 10, 11, Callable(self, "_migrate_run_v10_to_v11"))
	register_migration(SAVE_KINDS.RUN, 11, 12, Callable(self, "_migrate_run_v11_to_v12"))
	register_migration(SAVE_KINDS.RUN, 12, 13, Callable(self, "_migrate_run_v12_to_v13"))
	register_migration(SAVE_KINDS.RUN, 13, 14, Callable(self, "_migrate_run_v13_to_v14"))
	register_migration(SAVE_KINDS.RUN, 14, 15, Callable(self, "_migrate_run_v14_to_v15"))
	register_migration(SAVE_KINDS.RUN, 15, 16, Callable(self, "_migrate_run_v15_to_v16"))
	register_migration(SAVE_KINDS.RUN, 16, 17, Callable(self, "_migrate_run_v16_to_v17"))
	register_migration(SAVE_KINDS.RUN, 17, 18, Callable(self, "_migrate_run_v17_to_v18"))


func registered_save_kinds() -> Array[String]:
	var result: Array[String] = []
	for kind: String in SAVE_KINDS.VALUES:
		result.append(kind)
	return result


func current_version(kind: String) -> int:
	if not _is_registered_kind(kind):
		return 0
	return int(CURRENT_KIND_VERSIONS.get(kind, 1))


func save(slot: String, kind: String, payload: Dictionary) -> bool:
	_last_error = ""
	if not _validate_slot_and_kind(slot, kind):
		return false

	var slot_dir: String = _slot_dir(slot)
	if not _ensure_dir(slot_dir):
		return false

	var path: String = _save_path(slot, kind)
	var tmp_path: String = "%s.tmp" % path
	var bak_path: String = "%s.bak" % path
	var now: String = _now_string()
	var created_at: String = _existing_created_at(slot, kind, now)
	var normalized_payload: Variant = _json_normalized_payload(payload.duplicate(true))
	if not normalized_payload is Dictionary:
		_set_error("[SaveManager] save payload is not JSON-serializable")
		return false
	var payload_copy: Dictionary = normalized_payload as Dictionary
	if kind == SAVE_KINDS.RUN:
		payload_copy["schema_version"] = current_version(kind)
		payload_copy["mod_environment"] = _current_mod_environment()
	var envelope: Dictionary = {
		"version": current_version(kind),
		"kind": kind,
		"slot": slot,
		"created_at": created_at,
		"updated_at": now,
		"game_version": GAME_VERSION,
		"data_hash": _payload_hash(payload_copy),
		"payload": payload_copy,
	}

	if not _write_json_file(tmp_path, envelope):
		return false

	if FileAccess.file_exists(path):
		var copy_error: Error = DirAccess.copy_absolute(path, bak_path)
		if copy_error != OK:
			_set_error("[SaveManager] failed to create backup: %s" % bak_path)
			DirAccess.remove_absolute(tmp_path)
			return false
		DirAccess.remove_absolute(path)

	var rename_error: Error = DirAccess.rename_absolute(tmp_path, path)
	if rename_error != OK:
		_set_error("[SaveManager] failed to replace save file: %s" % path)
		if FileAccess.file_exists(bak_path) and not FileAccess.file_exists(path):
			DirAccess.copy_absolute(bak_path, path)
		DirAccess.remove_absolute(tmp_path)
		return false

	save_written.emit(slot, kind, path)
	Analytics.track_event(ANALYTICS_EVENTS.SAVE_WRITTEN, {
		"slot": slot,
		"kind": kind,
		"version": current_version(kind),
		"path": path,
	})
	return true


func load(slot: String, kind: String) -> Dictionary:
	var envelope: Dictionary = load_envelope(slot, kind)
	if envelope.is_empty():
		return {}
	return (envelope.get("payload", {}) as Dictionary).duplicate(true)


func load_envelope(slot: String, kind: String) -> Dictionary:
	_last_error = ""
	if not _validate_slot_and_kind(slot, kind):
		return {}

	var path: String = _save_path(slot, kind)
	var bak_path: String = "%s.bak" % path
	var primary_result: Dictionary = _read_save_file(path, slot, kind)
	if bool(primary_result.get("ok", false)):
		var primary_envelope: Dictionary = primary_result["envelope"]
		save_loaded.emit(slot, kind, int(primary_envelope["version"]), bool(primary_result.get("migrated", false)))
		Analytics.track_event(ANALYTICS_EVENTS.SAVE_LOADED, {
			"slot": slot,
			"kind": kind,
			"version": int(primary_envelope["version"]),
			"migrated": bool(primary_result.get("migrated", false)),
		})
		return primary_envelope.duplicate(true)

	var backup_result: Dictionary = _read_save_file(bak_path, slot, kind)
	if bool(backup_result.get("ok", false)):
		var backup_envelope: Dictionary = backup_result["envelope"]
		save_loaded.emit(slot, kind, int(backup_envelope["version"]), bool(backup_result.get("migrated", false)))
		Analytics.track_event(ANALYTICS_EVENTS.SAVE_LOADED, {
			"slot": slot,
			"kind": kind,
			"version": int(backup_envelope["version"]),
			"migrated": bool(backup_result.get("migrated", false)),
			"from_backup": true,
		})
		return backup_envelope.duplicate(true)

	var error: String = String(primary_result.get("error", "save file not found"))
	if FileAccess.file_exists(path) and not bool(primary_result.get("preserve", false)):
		_isolate_broken_file(path, slot, kind, error)
	if FileAccess.file_exists(bak_path) and not bool(backup_result.get("preserve", false)):
		_isolate_broken_file(bak_path, slot, kind, String(backup_result.get("error", "backup save is invalid")))
	_set_error(error)
	return {}


func delete(slot: String, kind: String) -> bool:
	_last_error = ""
	if not _validate_slot_and_kind(slot, kind):
		return false

	var deleted_any: bool = false
	for path: String in [_save_path(slot, kind), "%s.bak" % _save_path(slot, kind), "%s.tmp" % _save_path(slot, kind)]:
		if FileAccess.file_exists(path):
			var error: Error = DirAccess.remove_absolute(path)
			if error != OK:
				_set_error("[SaveManager] failed to delete save file: %s" % path)
				return false
			deleted_any = true

	_remove_slot_dir_if_empty(slot)
	if deleted_any:
		save_deleted.emit(slot, kind)
		Analytics.track_event(ANALYTICS_EVENTS.SAVE_DELETED, {
			"slot": slot,
			"kind": kind,
			"reason": "delete_api",
		})
	return deleted_any


func has_save(slot: String, kind: String) -> bool:
	if not _is_valid_slot(slot) or not _is_registered_kind(kind):
		return false
	var path: String = _save_path(slot, kind)
	if not FileAccess.file_exists(path):
		return false
	if kind != SAVE_KINDS.RUN:
		return true
	var result: Dictionary = _read_save_file(path, slot, kind)
	return (
		bool(result.get("ok", false))
		or not bool(result.get("preserve", false))
	)


func save_status(slot: String, kind: String) -> Dictionary:
	if not _is_valid_slot(slot) or not _is_registered_kind(kind):
		return {"exists": false, "compatible": false, "error": _last_error}
	var path: String = _save_path(slot, kind)
	if not FileAccess.file_exists(path):
		return {"exists": false, "compatible": false, "error": ""}
	var result: Dictionary = _read_save_file(path, slot, kind)
	return {
		"exists": true,
		"compatible": bool(result.get("ok", false)),
		"preserved_incompatible": bool(result.get("preserve", false)),
		"error": String(result.get("error", "")),
	}


func list_slots() -> Array[String]:
	var slots: Array[String] = []
	var root: DirAccess = DirAccess.open(SAVE_ROOT)
	if root == null:
		return slots

	root.list_dir_begin()
	var entry_name: String = root.get_next()
	while not entry_name.is_empty():
		if root.current_is_dir() and entry_name != BROKEN_DIR_NAME and not entry_name.begins_with("."):
			slots.append(entry_name)
		entry_name = root.get_next()
	root.list_dir_end()
	slots.sort()
	return slots


func register_migration(kind: String, from_version: int, to_version: int, migration: Callable) -> bool:
	if not _is_registered_kind(kind):
		push_error("[SaveManager] unknown save kind: %s" % kind)
		return false
	if from_version < 1 or to_version <= from_version:
		push_error("[SaveManager] invalid migration versions: %s %d->%d" % [kind, from_version, to_version])
		return false
	if not migration.is_valid():
		push_error("[SaveManager] invalid migration callable: %s %d->%d" % [kind, from_version, to_version])
		return false

	_migrations[_migration_key(kind, from_version, to_version)] = migration
	return true


func save_root() -> String:
	return SAVE_ROOT


func last_error() -> String:
	return _last_error


func _read_save_file(path: String, slot: String, kind: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "[SaveManager] save file not found: %s" % path}

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "[SaveManager] save file is not readable: %s" % path}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {"ok": false, "error": "[SaveManager] save file is not a JSON object: %s" % path}

	var envelope: Dictionary = parsed as Dictionary
	var validation_error: String = _validate_envelope(envelope, slot, kind)
	if not validation_error.is_empty():
		return {
			"ok": false,
			"error": validation_error,
			"preserve": _should_preserve_incompatible_save(
				envelope,
				kind,
				validation_error
			),
		}

	var migration_result: Dictionary = _migrate_envelope(envelope)
	if not bool(migration_result.get("ok", false)):
		return {"ok": false, "error": String(migration_result.get("error", "migration failed"))}

	return {
		"ok": true,
		"envelope": migration_result["envelope"],
		"migrated": bool(migration_result.get("migrated", false)),
	}


func _validate_envelope(envelope: Dictionary, slot: String, kind: String) -> String:
	for field_name: String in ["version", "kind", "slot", "created_at", "updated_at", "game_version", "data_hash", "payload"]:
		if not envelope.has(field_name):
			return "[SaveManager] save missing field: %s" % field_name

	if not envelope["version"] is float and not envelope["version"] is int:
		return "[SaveManager] save version must be an int"
	if String(envelope["kind"]) != kind:
		return "[SaveManager] save kind mismatch: expected %s got %s" % [kind, String(envelope["kind"])]
	if String(envelope["slot"]) != slot:
		return "[SaveManager] save slot mismatch: expected %s got %s" % [slot, String(envelope["slot"])]
	if not envelope["payload"] is Dictionary:
		return "[SaveManager] save payload must be a Dictionary"

	var version: int = int(envelope["version"])
	if kind == SAVE_KINDS.RUN and version != current_version(kind):
		return (
			"[SaveManager] unsupported run version: %d; expected %d"
			% [version, current_version(kind)]
		)
	if version > current_version(kind):
		return "[SaveManager] save version is newer than supported: %d > %d" % [version, current_version(kind)]

	var payload: Dictionary = envelope["payload"] as Dictionary
	var expected_hash: String = _payload_hash(payload)
	if String(envelope["data_hash"]) != expected_hash:
		return "[SaveManager] save data_hash mismatch"
	if kind == SAVE_KINDS.RUN:
		var environment_error: String = _validate_mod_environment(
			payload.get("mod_environment", null)
		)
		if not environment_error.is_empty():
			return environment_error

	return ""


func _should_preserve_incompatible_save(
	envelope: Dictionary,
	kind: String,
	validation_error: String
) -> bool:
	if kind != SAVE_KINDS.RUN:
		return false
	var raw_version: Variant = envelope.get("version", null)
	if raw_version is int or raw_version is float:
		if (
			int(raw_version) != current_version(kind)
			and validation_error.begins_with(
				"[SaveManager] unsupported run version:"
			)
		):
			return true
	var payload_raw: Variant = envelope.get("payload", null)
	if payload_raw is Dictionary:
		var environment_error: String = _validate_mod_environment(
			(payload_raw as Dictionary).get("mod_environment", null)
		)
		return (
			not environment_error.is_empty()
			and validation_error == environment_error
		)
	return false


func _current_mod_environment() -> Array[Dictionary]:
	var loader: Node = get_node_or_null("/root/ModLoader")
	if loader == null or not loader.has_method("mod_environment"):
		return []
	var raw_environment: Variant = loader.call("mod_environment")
	if not raw_environment is Array:
		return []
	var environment: Array[Dictionary] = []
	for raw_entry: Variant in raw_environment as Array:
		if raw_entry is Dictionary:
			environment.append((raw_entry as Dictionary).duplicate(true))
	return environment


func _validate_mod_environment(raw_environment: Variant) -> String:
	if not raw_environment is Array:
		return "[SaveManager] run mod_environment must be an Array"
	var loader: Node = get_node_or_null("/root/ModLoader")
	if loader == null or not loader.has_method("validate_environment"):
		return "" if (raw_environment as Array).is_empty() else "[SaveManager] ModLoader unavailable for saved mod environment"
	var result: Variant = loader.call("validate_environment", raw_environment)
	if not result is Dictionary:
		return "[SaveManager] ModLoader returned an invalid environment validation result"
	if bool((result as Dictionary).get("ok", false)):
		return ""
	return "[SaveManager] run mod environment mismatch: %s" % String(
		(result as Dictionary).get("reason", "unknown mismatch")
	)


func _migrate_envelope(envelope: Dictionary) -> Dictionary:
	var kind: String = String(envelope["kind"])
	var version: int = int(envelope["version"])
	var target_version: int = current_version(kind)
	var migrated: bool = false
	var payload: Dictionary = (envelope["payload"] as Dictionary).duplicate(true)

	while version < target_version:
		var next_version: int = version + 1
		var key: String = _migration_key(kind, version, next_version)
		if not _migrations.has(key):
			return {"ok": false, "error": "[SaveManager] missing migration: %s %d->%d" % [kind, version, next_version]}

		var migration: Callable = _migrations[key]
		var migrated_payload: Variant = migration.call(payload.duplicate(true))
		if not migrated_payload is Dictionary:
			return {"ok": false, "error": "[SaveManager] migration did not return Dictionary: %s" % key}

		payload = migrated_payload as Dictionary
		save_migrated.emit(String(envelope["slot"]), kind, version, next_version)
		Analytics.track_event(ANALYTICS_EVENTS.SAVE_MIGRATED, {
			"slot": String(envelope["slot"]),
			"kind": kind,
			"from_version": version,
			"to_version": next_version,
		})
		version = next_version
		migrated = true

	var migrated_envelope: Dictionary = envelope.duplicate(true)
	migrated_envelope["version"] = version
	migrated_envelope["payload"] = payload
	migrated_envelope["data_hash"] = _payload_hash(payload)
	return {"ok": true, "envelope": migrated_envelope, "migrated": migrated}


func _migrate_run_v1_to_v2(payload: Dictionary) -> Dictionary:
	var result: Dictionary = payload.duplicate(true)
	if not result.has("schema_version"):
		result["schema_version"] = 1
	for key: String in ["spawn_states", "player", "weapon", "game_clock", "rng", "map"]:
		if not result.has(key) or not result.get(key, {}) is Dictionary:
			result[key] = {}
	for key: String in ["hazards", "enemies", "bullets", "pickups"]:
		if not result.has(key) or not result.get(key, []) is Array:
			result[key] = []
	return result


func _migrate_meta_v1_to_v2(payload: Dictionary) -> Dictionary:
	var result: Dictionary = payload.duplicate(true)
	if not result.get("hero_composition", {}) is Dictionary:
		result["hero_composition"] = {}
	var composition: Dictionary = (result.get("hero_composition", {}) as Dictionary).duplicate(true)
	composition["main_hero_id"] = String(
		composition.get("main_hero_id", DEFAULT_MAIN_HERO_ID)
	)
	composition["sub_hero_id"] = String(
		composition.get("sub_hero_id", DEFAULT_SUB_HERO_ID)
	)
	result["hero_composition"] = composition
	return result


func _migrate_meta_v2_to_v3(payload: Dictionary) -> Dictionary:
	# Gear Mods are now run-scoped. Keep the player's last confirmed hero
	# composition, but remove the retired account-level inventory and loadouts.
	var result: Dictionary = _migrate_meta_v1_to_v2(payload)
	result.erase("gear_mods")
	return result


func _migrate_meta_v3_to_v4(payload: Dictionary) -> Dictionary:
	var result: Dictionary = _migrate_meta_v2_to_v3(payload)
	var progression: Dictionary = {}
	if result.get("content_progression", {}) is Dictionary:
		progression = (result.get("content_progression", {}) as Dictionary).duplicate(true)
	if (
		not progression.has("unlocked")
		or not progression.get("unlocked") is Dictionary
	):
		progression["unlocked"] = {}
	if (
		not progression.has("counters")
		or not progression.get("counters") is Dictionary
	):
		progression["counters"] = {}
	result["content_progression"] = progression
	return result


func _migrate_run_v2_to_v3(payload: Dictionary) -> Dictionary:
	# v3 adds the F13 room carrier state. Pre-F13 (open-warzone) runs migrate to an empty
	# room block, which restore reads as "no room carrier" and keeps the open-warzone path.
	var result: Dictionary = payload.duplicate(true)
	if not result.has("room") or not result.get("room", {}) is Dictionary:
		result["room"] = {}
	return result


func _migrate_run_v3_to_v4(payload: Dictionary) -> Dictionary:
	# The seamless module world cannot safely restore room/open-warzone entity topology.
	# Keep the envelope readable so boot can show an explicit incompatibility notice and
	# delete only the run payload; meta progression is stored under a separate save kind.
	var result: Dictionary = payload.duplicate(true)
	result["schema_version"] = 4
	result["legacy_run_incompatible"] = true
	result["module_world"] = {}
	return result


func _migrate_run_v4_to_v5(payload: Dictionary) -> Dictionary:
	# Single-character snapshots do not contain enough information to infer a valid
	# composition, element defense, shared energy, or slot-keyed cooldown state.
	var result: Dictionary = payload.duplicate(true)
	result["schema_version"] = 5
	result["legacy_run_incompatible"] = true
	result["hero_composition"] = {}
	return result


func _migrate_run_v5_to_v6(payload: Dictionary) -> Dictionary:
	# v5 cannot recover time spent in the start module or the exact difficulty
	# multipliers captured by each enemy at spawn time. Keep the envelope readable
	# so boot deletes only the run payload while preserving the separate meta save.
	var result: Dictionary = payload.duplicate(true)
	result["schema_version"] = 6
	result["legacy_run_incompatible"] = true
	result["difficulty_progression"] = {}
	return result


func _migrate_run_v6_to_v7(payload: Dictionary) -> Dictionary:
	# XP totals and pending automatic level-up choices cannot be converted into the
	# spendable/monotonic gold pair without inventing economic state. Keep the
	# envelope readable so boot deletes only the run and preserves Meta v2.
	var result: Dictionary = payload.duplicate(true)
	result.erase("level")
	result.erase("xp")
	result.erase("pickups")
	result["schema_version"] = 7
	result["legacy_run_incompatible"] = true
	result["gold_progression"] = {}
	result["reward_choice"] = {}
	result["gold_orbs"] = []
	return result


func _migrate_run_v7_to_v8(payload: Dictionary) -> Dictionary:
	# v7 enemy snapshots contain contact timers and no committed attack state,
	# spawn serial, armed explosion state, or external player knockback. Do not
	# guess whether a loaded overlap should deal damage or detonate.
	var result: Dictionary = payload.duplicate(true)
	result["schema_version"] = 8
	result["legacy_run_incompatible"] = true
	result["enemies"] = []
	result["next_enemy_spawn_serial"] = 1
	return result


func _migrate_run_v8_to_v9(payload: Dictionary) -> Dictionary:
	# v8 has no durable world-event state, pinned module ownership, fixed event
	# wave plan, or transaction guards. Do not restore a partially inferred event.
	var result: Dictionary = payload.duplicate(true)
	result["schema_version"] = 9
	result["legacy_run_incompatible"] = true
	result["world_events"] = {}
	return result


func _migrate_run_v9_to_v10(payload: Dictionary) -> Dictionary:
	# v9 enemies have no spawn-locked reward amount or multiplier breakdown, and
	# the RNG snapshot has no economy stream. Recalculation would duplicate or
	# shift rewards, so boot must discard only the run and preserve Meta v2.
	var result: Dictionary = payload.duplicate(true)
	result["schema_version"] = 10
	result["legacy_run_incompatible"] = true
	result["enemies"] = []
	return result


func _migrate_run_v10_to_v11(payload: Dictionary) -> Dictionary:
	var result: Dictionary = payload.duplicate(true)
	result["schema_version"] = 11
	result["legacy_run_incompatible"] = true
	return result


func _migrate_run_v11_to_v12(payload: Dictionary) -> Dictionary:
	# v11 weapon and world snapshots encode ammunition state that no longer has
	# runtime meaning. Preserve Meta v2 and discard only the incompatible Run.
	var result: Dictionary = payload.duplicate(true)
	result["schema_version"] = 12
	result["legacy_run_incompatible"] = true
	result.erase("ammo_drop_misses")
	result.erase("ammo_magazines")
	var rng_snapshot: Dictionary = (
		(result.get("rng", {}) as Dictionary).duplicate(true)
		if result.get("rng", {}) is Dictionary
		else {}
	)
	var rng_streams: Dictionary = (
		(rng_snapshot.get("streams", {}) as Dictionary).duplicate(true)
		if rng_snapshot.get("streams", {}) is Dictionary
		else {}
	)
	rng_streams.erase("ammo")
	rng_snapshot["streams"] = rng_streams
	result["rng"] = rng_snapshot
	var weapon: Dictionary = (
		(result.get("weapon", {}) as Dictionary).duplicate(true)
		if result.get("weapon", {}) is Dictionary
		else {}
	)
	for retired_field: String in [
		"magazine",
		"magazine_ammo",
		"reserve",
		"reserve_ammo",
		"is_reloading",
		"reload_remaining",
	]:
		weapon.erase(retired_field)
	result["weapon"] = weapon
	return result


func _migrate_run_v12_to_v13(payload: Dictionary) -> Dictionary:
	# v12 can contain extraction settlement state and account-level Gear Mod
	# snapshots that have no safe meaning in the run-scoped system. Keep the
	# envelope readable so FormalClientBoot shows the established notice and
	# deletes only this incompatible run.
	var result: Dictionary = payload.duplicate(true)
	result["schema_version"] = 13
	result["legacy_run_incompatible"] = true
	result.erase("pending_loot")
	result.erase("extraction")
	for retired_field: String in [
		"gear_mods",
		"gear_mod_inventory",
		"gear_mod_loadout",
		"gear_mod_profile",
		"gear_mod_resources",
		"hero_gear_mods",
		"weapon_gear_mods",
	]:
		result.erase(retired_field)
	return result


func _migrate_run_v13_to_v14(payload: Dictionary) -> Dictionary:
	# v13 has no run-owned unlock delta carrier. It cannot prove whether end-of-run
	# counters were already committed to Meta, so restoring it could double count.
	var result: Dictionary = payload.duplicate(true)
	result["schema_version"] = 14
	result["legacy_run_incompatible"] = true
	return result


func _migrate_run_v14_to_v15(payload: Dictionary) -> Dictionary:
	# v14 module snapshots encode the retired 9 x 9 world. Restoring them into
	# the 7 x 7 coordinate system would invalidate assignments and entity cells.
	var result: Dictionary = payload.duplicate(true)
	result["schema_version"] = 15
	result["legacy_run_incompatible"] = true
	return result


func _migrate_run_v15_to_v16(payload: Dictionary) -> Dictionary:
	var result: Dictionary = payload.duplicate(true)
	result["schema_version"] = 16
	result["gear_mod_pickups"] = []
	return result


func _migrate_run_v16_to_v17(payload: Dictionary) -> Dictionary:
	# v16 Gear Mod ranks encode effect strength and duplicate-pickup history.
	# There is no lossless mapping to the fixed-effect Mod list model, so keep
	# the payload inspectable and let FormalClientBoot delete only this run.
	var result: Dictionary = payload.duplicate(true)
	result["schema_version"] = 17
	result["legacy_run_incompatible"] = true
	return result


func _migrate_run_v17_to_v18(payload: Dictionary) -> Dictionary:
	# v17 only stores an unordered list of Mod ids. The spatial board requires
	# per-instance coordinates and cannot infer them without changing the build.
	var result: Dictionary = payload.duplicate(true)
	result["schema_version"] = 18
	result["legacy_run_incompatible"] = true
	return result


func _write_json_file(path: String, value: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_error("[SaveManager] failed to open save file for writing: %s" % path)
		return false

	file.store_string(JSON.stringify(value, "\t"))
	file.flush()
	return true


func _existing_created_at(slot: String, kind: String, fallback: String) -> String:
	var result: Dictionary = _read_save_file(_save_path(slot, kind), slot, kind)
	if bool(result.get("ok", false)):
		var envelope: Dictionary = result["envelope"]
		return String(envelope.get("created_at", fallback))
	return fallback


func _payload_hash(payload: Dictionary) -> String:
	return _stable_serialize(payload).sha256_text()


func _json_normalized_payload(payload: Dictionary) -> Variant:
	return JSON.parse_string(JSON.stringify(payload))


func _stable_serialize(value: Variant) -> String:
	if value is Dictionary:
		var dictionary: Dictionary = value as Dictionary
		var keys: Array = dictionary.keys()
		keys.sort()
		var parts: Array[String] = []
		for key: Variant in keys:
			parts.append("%s:%s" % [JSON.stringify(String(key)), _stable_serialize(dictionary[key])])
		return "{%s}" % ",".join(parts)
	if value is Array:
		var array_value: Array = value as Array
		var parts: Array[String] = []
		for item: Variant in array_value:
			parts.append(_stable_serialize(item))
		return "[%s]" % ",".join(parts)
	if value is int:
		return String.num_int64(int(value))
	if value is float:
		var number: float = float(value)
		if is_equal_approx(number, roundf(number)):
			return String.num_int64(int(number))
		return String.num(number)
	return JSON.stringify(value)


func _validate_slot_and_kind(slot: String, kind: String) -> bool:
	if not _is_valid_slot(slot):
		_set_error("[SaveManager] invalid save slot: %s" % slot)
		return false
	if not _is_registered_kind(kind):
		_set_error("[SaveManager] unknown save kind: %s" % kind)
		return false
	return true


func _is_valid_slot(slot: String) -> bool:
	if slot.strip_edges().is_empty():
		return false
	if slot.contains("/") or slot.contains("\\") or slot.contains(":") or slot.contains(".."):
		return false
	return true


func _is_registered_kind(kind: String) -> bool:
	if DataLoader != null and DataLoader.has_contract_value("save_kinds", kind):
		return true
	return SAVE_KINDS.VALUES.has(kind)


func _ensure_dir(path: String) -> bool:
	var error: Error = DirAccess.make_dir_recursive_absolute(path)
	if error != OK:
		_set_error("[SaveManager] failed to create directory: %s" % path)
		return false
	return true


func _remove_slot_dir_if_empty(slot: String) -> void:
	var slot_dir: String = _slot_dir(slot)
	var dir: DirAccess = DirAccess.open(slot_dir)
	if dir == null:
		return

	dir.list_dir_begin()
	var entry_name: String = dir.get_next()
	while not entry_name.is_empty():
		if not entry_name.begins_with("."):
			dir.list_dir_end()
			return
		entry_name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(slot_dir)


func _isolate_broken_file(path: String, slot: String, kind: String, error: String) -> void:
	var broken_dir: String = SAVE_ROOT.path_join(BROKEN_DIR_NAME)
	if not _ensure_dir(broken_dir):
		return

	var broken_path: String = _unique_broken_path(broken_dir, slot, kind)
	var move_error: Error = DirAccess.rename_absolute(path, broken_path)
	if move_error != OK:
		broken_path = path

	save_corrupted.emit(slot, kind, broken_path, error)
	Analytics.track_event(ANALYTICS_EVENTS.SAVE_CORRUPTED, {
		"slot": slot,
		"kind": kind,
		"path": broken_path,
		"error": error,
	})


func _unique_broken_path(broken_dir: String, slot: String, kind: String) -> String:
	var base_name: String = "%s_%s_%s" % [slot, kind, _safe_timestamp()]
	var candidate: String = broken_dir.path_join("%s.save" % base_name)
	var suffix: int = 2
	while FileAccess.file_exists(candidate):
		candidate = broken_dir.path_join("%s_%d.save" % [base_name, suffix])
		suffix += 1
	return candidate


func _save_path(slot: String, kind: String) -> String:
	return _slot_dir(slot).path_join("%s.save" % kind)


func _slot_dir(slot: String) -> String:
	return SAVE_ROOT.path_join(slot)


func _migration_key(kind: String, from_version: int, to_version: int) -> String:
	return "%s:%d:%d" % [kind, from_version, to_version]


func _now_string() -> String:
	return Time.get_datetime_string_from_system(false, false)


func _safe_timestamp() -> String:
	return _now_string().replace(":", "-")


func _set_error(message: String) -> void:
	_last_error = message
	push_error(message)
