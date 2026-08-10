extends Node


const ACTIONS := preload("res://scripts/contracts/actions.gd")
const ANALYTICS_EVENTS := preload("res://scripts/contracts/analytics_events.gd")

const REPLAY_FILE_NAME: String = "smoke_basic_run.replay"
const UNSUPPORTED_REPLAY_FILE_NAME: String = "smoke_unsupported_input.replay"
const REPLAY_SEED: int = 20260619
const RECORD_FRAMES: int = 3

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	_cleanup_smoke_file()
	Replay.set_enabled(true)
	Replay.clear_recording()
	RNG.set_run_seed(REPLAY_SEED)
	GameClock.reset()

	GameState.change_state(GameState.PLAYING, {
		"source": "replay_smoke",
		"scenario": "golden_basic_run",
		"main_hero_id": "character_primary_a",
		"sub_hero_id": "character_primary_b",
		"content_availability": (
			ContentUnlockSystem.build_run_availability_snapshot()
		),
	})
	for _index: int in range(RECORD_FRAMES):
		await get_tree().physics_frame
		await get_tree().process_frame

	_expect(Replay.is_recording(), "Replay should start recording from PLAYING state")
	_expect(Replay.record_input_value(ACTIONS.MOVE, Vector2(0.6, -0.8), "player_0"), "Replay should record Vector2 movement")
	_expect(Replay.record_input_value(ACTIONS.AIM, Vector2.RIGHT, "player_0"), "Replay should record Vector2 aim")
	_expect(Replay.record_input_value(ACTIONS.FIRE, true, "player_0"), "Replay should record bool action press")
	_expect(Replay.record_input_value(ACTIONS.FIRE, false, "player_0"), "Replay should record bool action release")
	_expect(Replay.record_decision(ANALYTICS_EVENTS.REWARD_CHOICE, {
		"trigger_id": "debug_command",
		"pool_id": "default_reward_choice",
		"choices": ["reward_damage_small", "reward_fire_rate_small", "reward_pickup_range_small"],
		"selected": "reward_damage_small",
	}), "Replay should record registered decision events")
	_expect(
		Replay.record_input_value(ACTIONS.UI_CONFIRM, true, "player_0"),
		"Replay should initially observe the placement confirm input edge"
	)
	_expect(Replay.record_decision(ANALYTICS_EVENTS.GEAR_MOD_PLACEMENT, {
		"instance_id": 41,
		"mod_id": "gear_mod_grid_rock",
		"outcome": "placed",
		"x": 3,
		"y": 2,
	}), "Replay should record a valid Gear Mod placement decision")
	_expect(
		Replay.record_input_value(ACTIONS.UI_BACK, true, "player_0"),
		"Replay should initially observe the placement cancel input edge"
	)
	_expect(Replay.record_decision(ANALYTICS_EVENTS.GEAR_MOD_PLACEMENT, {
		"instance_id": 42,
		"mod_id": "gear_mod_grid_rock",
		"outcome": "cancelled",
	}), "Replay should record a valid Gear Mod cancellation decision")
	_expect(
		not bool(Replay.call("_is_valid_decision_event", {
			"event": ANALYTICS_EVENTS.GEAR_MOD_PLACEMENT,
			"payload": {
				"instance_id": 41,
				"mod_id": "gear_mod_grid_rock",
				"outcome": "placed",
				"x": 7,
				"y": 2,
			},
			"tick": GameClock.tick(),
			"time": GameClock.now(),
		})),
		"Replay should reject out-of-bounds Gear Mod placement payloads"
	)

	GameState.change_state(GameState.GAME_OVER, {"source": "replay_smoke"})
	var completed: Dictionary = Replay.snapshot()
	_expect(not Replay.is_recording(), "Replay should stop recording on GAME_OVER")
	_expect(String(completed.get("reason", "")) == String(GameState.GAME_OVER), "Replay should store stop reason")

	var path: String = Replay.save_recording(completed, REPLAY_FILE_NAME)
	_expect(not path.is_empty(), "Replay should save a .replay file")
	_expect(FileAccess.file_exists(path), "Replay file should exist after save")

	var loaded: Dictionary = Replay.load_recording(path)
	_expect(not loaded.is_empty(), "Replay should load a saved .replay file")
	_expect(_summaries_match(Replay.recording_summary(completed), Replay.recording_summary(loaded)), "Replay summary should roundtrip through disk")

	var envelope: Dictionary = Replay.load_replay_file(path)
	_expect(String(envelope.get("data_fingerprint", "")) == Replay.current_data_fingerprint(), "Replay envelope should include the current data fingerprint")
	_expect(String(envelope.get("game_version", "")) == "v1.18", "Replay envelope should use game version v1.18")
	_expect(int(envelope.get("file_schema_version", 0)) == 9, "Replay envelope should use file schema v9")
	_expect(int(loaded.get("schema_version", 0)) == 9, "Replay recording should use schema v9")
	_expect(envelope.get("mod_environment", null) is Array, "Replay v9 envelope should contain mod_environment")
	_expect(
		(envelope.get("mod_environment", []) as Array) == ModLoader.mod_environment(),
		"Replay v9 envelope should freeze the exact local mod environment"
	)
	_expect_gear_mod_gameplay_fingerprint()
	_expect(_has_typed_event(loaded, ACTIONS.MOVE, "vector2"), "Replay should persist typed Vector2 events")
	_expect(_has_typed_event(loaded, ACTIONS.FIRE, "bool"), "Replay should persist typed bool events")
	_expect(
		not _has_typed_event(loaded, ACTIONS.UI_CONFIRM, "bool"),
		"semantic Gear Mod placement should replace its raw confirm input edge"
	)
	_expect(
		not _has_typed_event(loaded, ACTIONS.UI_BACK, "bool"),
		"semantic Gear Mod cancellation should replace its raw back input edge"
	)
	_expect(
		_has_decision(loaded, ANALYTICS_EVENTS.GEAR_MOD_PLACEMENT),
		"Replay should persist Gear Mod placement decisions"
	)
	_expect_unsupported_schemas_are_rejected(envelope)
	_expect_mod_environment_mismatches_are_rejected(envelope)
	_expect_semantic_trigger_capacity_boundary()

	_cleanup_smoke_file()
	GameState.change_state(GameState.MAIN_MENU, {"source": "replay_smoke"})
	_finish()


func _summaries_match(left: Dictionary, right: Dictionary) -> bool:
	return JSON.stringify(left) == JSON.stringify(right)


func _expect_semantic_trigger_capacity_boundary() -> void:
	Replay.clear_recording()
	_expect(
		Replay.start_recording({"source": "replay_smoke_capacity"}),
		"Replay should start the semantic trigger capacity fixture"
	)
	for index: int in range(4096):
		Replay.record_input_value(
			ACTIONS.FIRE,
			index % 2 == 0,
			"player_0"
		)
	_expect(
		Replay.record_input_value(ACTIONS.UI_CONFIRM, true, "player_0"),
		"Replay should temporarily retain a full-buffer semantic trigger"
	)
	_expect(
		Replay.record_decision(ANALYTICS_EVENTS.GEAR_MOD_PLACEMENT, {
			"instance_id": 4097,
			"mod_id": "gear_mod_grid_rock",
			"outcome": "placed",
			"x": 3,
			"y": 2,
		}),
		"Replay should replace the full-buffer trigger with a placement decision"
	)
	var snapshot: Dictionary = Replay.snapshot()
	_expect(
		(snapshot.get("input_events", []) as Array).size() == 4096
		and int(snapshot.get("dropped_input_events", -1)) == 0,
		"semantic replacement at MAX_INPUT_EVENTS should not drop the oldest input"
	)
	Replay.stop_recording("capacity_complete")


func _has_typed_event(recording: Dictionary, action_name: String, value_type: String) -> bool:
	for raw_event: Variant in recording.get("input_events", []) as Array:
		if not raw_event is Dictionary:
			continue
		var event: Dictionary = raw_event as Dictionary
		if String(event.get("action", "")) == action_name and String(event.get("value_type", "")) == value_type:
			return true
	return false


func _has_decision(recording: Dictionary, event_name: String) -> bool:
	for raw_event: Variant in recording.get("decision_events", []) as Array:
		if (
			raw_event is Dictionary
			and String((raw_event as Dictionary).get("event", ""))
			== event_name
		):
			return true
	return false


func _expect_unsupported_schemas_are_rejected(current_envelope: Dictionary) -> void:
	var path: String = Replay.replay_root().path_join(UNSUPPORTED_REPLAY_FILE_NAME)
	for unsupported_version: int in [1, 2, 3, 4, 5, 6, 7, 8, 10]:
		var unsupported: Dictionary = current_envelope.duplicate(true)
		unsupported["file_schema_version"] = unsupported_version
		var source_text: String = JSON.stringify(unsupported, "\t")
		_expect(_write_replay_text(path, source_text), "smoke should write unsupported replay schema fixture")
		var loaded: Dictionary = Replay.load_replay_file(path)
		_expect(loaded.is_empty(), "replay schema %d should be rejected" % unsupported_version)
		_expect(
			Replay.last_error() == "[Replay] unsupported replay file schema: %d; expected 9" % unsupported_version,
			"unsupported replay schema should report the exact version mismatch"
		)
		_expect(_read_replay_text(path) == source_text, "rejected replay schema should not rewrite the source file")
	for unsupported_version: int in [1, 2, 3, 4, 5, 6, 7, 8, 10]:
		var unsupported: Dictionary = current_envelope.duplicate(true)
		var recording: Dictionary = (unsupported.get("recording", {}) as Dictionary).duplicate(true)
		recording["schema_version"] = unsupported_version
		unsupported["recording"] = recording
		var source_text: String = JSON.stringify(unsupported, "\t")
		_expect(_write_replay_text(path, source_text), "smoke should write unsupported recording schema fixture")
		var loaded: Dictionary = Replay.load_replay_file(path)
		_expect(loaded.is_empty(), "recording schema %d should be rejected" % unsupported_version)
		_expect(
			Replay.last_error() == "[Replay] unsupported replay recording schema: %d; expected 9" % unsupported_version,
			"unsupported recording schema should report the exact version mismatch"
		)
		_expect(_read_replay_text(path) == source_text, "rejected recording schema should not rewrite the source file")


func _expect_mod_environment_mismatches_are_rejected(current_envelope: Dictionary) -> void:
	var path: String = Replay.replay_root().path_join(UNSUPPORTED_REPLAY_FILE_NAME)
	var installed: Dictionary = {
		"id": "fixture",
		"version": "2.0.0",
		"gameplay_hash": "installed_hash",
	}
	var recorded: Dictionary = installed.duplicate(true)

	_set_mod_environment([])
	_expect_preserved_environment_rejection(current_envelope, [recorded], path, "missing package")

	_set_mod_environment([installed])
	var wrong_version: Dictionary = recorded.duplicate(true)
	wrong_version["version"] = "1.0.0"
	_expect_preserved_environment_rejection(current_envelope, [wrong_version], path, "version mismatch")

	var wrong_hash: Dictionary = recorded.duplicate(true)
	wrong_hash["gameplay_hash"] = "recorded_hash"
	_expect_preserved_environment_rejection(current_envelope, [wrong_hash], path, "gameplay hash mismatch")
	_set_mod_environment([])


func _expect_preserved_environment_rejection(
	current_envelope: Dictionary,
	environment: Array,
	path: String,
	label: String
	) -> void:
	var incompatible: Dictionary = current_envelope.duplicate(true)
	incompatible["mod_environment"] = environment.duplicate(true)
	var source_text: String = JSON.stringify(incompatible, "\t")
	_expect(_write_replay_text(path, source_text), "smoke should write %s replay fixture" % label)
	_expect(Replay.load_replay_file(path).is_empty(), "Replay with %s should be rejected" % label)
	_expect(Replay.last_error().contains("mod environment mismatch"), "Replay %s should report a mod environment diagnostic" % label)
	_expect(_read_replay_text(path) == source_text, "Replay with %s should preserve the original file" % label)


func _expect_gear_mod_gameplay_fingerprint() -> void:
	var gear_mod_payload: Dictionary = (
		DataLoader.gear_mod_gameplay_fingerprint_payload()
	)
	_expect(
		int(gear_mod_payload.get("schema_version", 0)) == 6,
		"Replay fingerprint should include Gear Mod data schema v6"
	)
	_expect(
		gear_mod_payload.get("board", null) is Dictionary
		and gear_mod_payload.get("pickup", null) is Dictionary
		and gear_mod_payload.get("reward_pools", null) is Array
		and gear_mod_payload.get("reward_pool_contributions", null) is Array
		and gear_mod_payload.get("mods", null) is Array
		and gear_mod_payload.get("drop_rows", null) is Array,
		"Replay fingerprint should include normalized Gear Mod gameplay data"
	)
	var source_data: Dictionary = (
		DataLoader.load_json(DataLoader.GEAR_MODS_PATH) as Dictionary
	)
	var source_reward_pools: Array = source_data.get("reward_pools", []) as Array
	var fingerprint_reward_pools: Array = (
		gear_mod_payload.get("reward_pools", []) as Array
	)
	_expect(
		source_reward_pools.size() == fingerprint_reward_pools.size(),
		"Replay fingerprint should include every Gear Mod reward pool"
	)
	for pool_index: int in range(
		mini(source_reward_pools.size(), fingerprint_reward_pools.size())
	):
		var source_pool: Dictionary = source_reward_pools[pool_index] as Dictionary
		var fingerprint_pool: Dictionary = (
			fingerprint_reward_pools[pool_index] as Dictionary
		)
		_expect(
			String(source_pool.get("id", ""))
			== String(fingerprint_pool.get("id", ""))
			and source_pool.get("mod_ids", [])
			== fingerprint_pool.get("mod_ids", []),
			"Replay fingerprint should preserve reward-pool and Mod-ID order"
		)
	var source_drop_rows: Array[Dictionary] = DataLoader.load_csv(
		DataLoader.GEAR_MOD_DROP_TABLES_PATH
	)
	var fingerprint_drop_rows: Array = gear_mod_payload.get("drop_rows", []) as Array
	_expect(
		source_drop_rows.size() == fingerprint_drop_rows.size(),
		"Replay fingerprint should include every Gear Mod drop row"
	)
	for row_index: int in range(
		mini(source_drop_rows.size(), fingerprint_drop_rows.size())
	):
		var source_row: Dictionary = source_drop_rows[row_index]
		var fingerprint_row: Dictionary = fingerprint_drop_rows[row_index] as Dictionary
		_expect(
			String(source_row.get("source_enemy_id", ""))
			== String(fingerprint_row.get("source_enemy_id", ""))
			and String(source_row.get("mod_id", ""))
			== String(fingerprint_row.get("mod_id", "")),
			"Replay fingerprint should preserve Gear Mod drop-row order"
		)
	for raw_mod: Variant in gear_mod_payload.get("mods", []) as Array:
		if not raw_mod is Dictionary:
			_expect(false, "Replay Gear Mod fingerprint entries should be Dictionaries")
			continue
		var mod: Dictionary = raw_mod as Dictionary
		for display_field: String in [
			"name_key",
			"desc_key",
			"codex_icon_path",
		]:
			_expect(
				not mod.has(display_field),
				"Replay Gear Mod fingerprint should exclude display field %s"
				% display_field
			)
		for gameplay_field: String in [
			"id",
			"default_unlocked",
			"rarity",
			"components",
		]:
			_expect(
				mod.has(gameplay_field),
				"Replay Gear Mod fingerprint should include gameplay field %s"
				% gameplay_field
			)
		var components: Array = mod.get("components", []) as Array
		_expect(not components.is_empty(), "Replay Gear Mod fingerprint should include ordered components")
		for raw_component: Variant in components:
			_expect(
				raw_component is Dictionary
				and (raw_component as Dictionary).has("component_id")
				and (raw_component as Dictionary).has("type"),
				"Replay Gear Mod component fingerprint should preserve component identity and type"
			)
	var effect_payload: Dictionary = DataLoader.effect_gameplay_fingerprint_payload()
	_expect(
		(effect_payload.get("skills", {}) as Dictionary).get("schema_version", 0) == 3,
		"Replay fingerprint should include Skills v3 effect programs"
	)
	_expect(
		effect_payload.get("gear_mods", {}) == gear_mod_payload,
		"Replay effect fingerprint should include the exact Gear Mod gameplay payload"
	)
	var expected_fingerprint: String = String(Replay.call("_payload_hash", {
		"contracts": DataLoader.contracts(),
		"schema_counts": DataLoader.schema_counts(),
		"effect_gameplay": effect_payload,
		"gear_mod_gameplay": gear_mod_payload,
		"mod_environment": ModLoader.mod_environment(),
	}))
	_expect(
		Replay.current_data_fingerprint() == expected_fingerprint,
		"Replay data fingerprint should hash the Gear Mod gameplay payload"
	)


func _set_mod_environment(entries: Array) -> void:
	var enabled_mods: Array[Dictionary] = []
	for raw_entry: Variant in entries:
		if raw_entry is Dictionary:
			enabled_mods.append((raw_entry as Dictionary).duplicate(true))
	ModLoader.set("_enabled_mods", enabled_mods)


func _cleanup_smoke_file() -> void:
	for file_name: String in [REPLAY_FILE_NAME, UNSUPPORTED_REPLAY_FILE_NAME]:
		var path: String = Replay.replay_root().path_join(file_name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _write_replay_text(path: String, content: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.flush()
	return true


func _read_replay_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[ReplaySmoke] %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("[ReplaySmoke] passed")
		get_tree().quit(0)
		return

	print("[ReplaySmoke] failed; failures=%d" % _failures.size())
	get_tree().quit(1)
