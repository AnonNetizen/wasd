# Doc: docs/代码/formal_client_boot.md
# Authority: docs/代码/formal_client_boot.md, docs/游戏设计文档.md §9
class_name FormalClientBoot
extends Node


const APPLICATION_QUIT_MODAL_SCENE := preload(
	"res://scenes/ui/application_quit_modal.tscn"
)
const BOOT_LOG_PREFIX: String = "[FormalClientBoot]"
const CHARACTER_IDS := preload("res://scripts/contracts/character_ids.gd")
const GEAR_MOD_PICKUP_CAPTURE_SCRIPT_PATH: String = (
	"res://tools/capture_gear_mod_pickup_runtime.gd"
)
const CODEX_PANEL_SCENE := preload("res://scenes/ui/codex_panel.tscn")
const DEBUG_CONSOLE_SCRIPT_PATH: String = "res://scripts/debug/debug_console.gd"
const GAMEPLAY_RUN_LOOP_SCENE := preload("res://scenes/gameplay/gameplay_run_loop.tscn")
const GOLDEN_REPLAY_CAPTURE_SCRIPT_PATH: String = "res://tools/golden_replay_capture.gd"
const HERO_COMPOSITION_PANEL_SCENE := preload("res://scenes/ui/hero_composition_panel.tscn")
const LOADING_SCREEN_SCENE := preload("res://scenes/ui/loading_screen.tscn")
const MOD_PANEL_SCENE := preload("res://scenes/ui/mod_panel.tscn")
const TITLE_MENU_SCENE := preload("res://scenes/ui/title_menu.tscn")
const PERF_PROBE_SCRIPT_PATH: String = "res://tools/perf_probe.gd"
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const REPLAY_RUNNER_SCRIPT_PATH: String = "res://tools/replay_runner.gd"
const RNG_AUDIT_SCRIPT_PATH: String = "res://tools/rng_audit.gd"
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")
const SETTINGS_PANEL_SCENE := preload("res://scenes/ui/settings_panel.tscn")
const SMOKE_COMMAND_CATALOG_PATH: String = "res://tools/smoke_commands.json"
const SMOKE_COMMAND_CATALOG_SCHEMA_VERSION: int = 1
const STARTUP_PROBE_SCRIPT_PATH: String = "res://tools/startup_probe.gd"
const UI_QUIT_CONFIRM_BODY: String = "ui_quit_confirm_body"
const UI_QUIT_SAVE_FAILED_BODY: String = "ui_quit_save_failed_body"

enum PlayerLoadMode {
	NEW_RUN,
	CONTINUE_RUN,
}

var _application_quit_body_key: String = UI_QUIT_CONFIRM_BODY
var _application_quit_deferred_for_loading: bool = false
var _application_quit_modal: ConfirmationModal = null
var _application_quit_waiting_for_confirmation: bool = false
var _run_loop: Node = null
var _open_warzone_launch: bool = false
var _module_world_technical_slice_launch: bool = false
var _codex_panel: CanvasLayer = null
var _debug_console: CanvasLayer = null
var _hero_composition_panel: CanvasLayer = null
var _last_main_hero_id: String = ""
var _last_sub_hero_id: String = ""
var _settings_panel: CanvasLayer = null
var _title_menu: CanvasLayer = null
var _loading_screen: CanvasLayer = null
var _mod_panel: CanvasLayer = null
var _player_load_in_progress: bool = false
var _active_difficulty_profile_id: String = ""


func _ready() -> void:
	get_tree().auto_accept_quit = false
	if _is_startup_probe_enabled():
		print("[StartupProbe] BOOT_BEGIN")
	_module_world_technical_slice_launch = _is_module_world_technical_slice_launch_enabled()
	var data_schema_ok: bool = DataLoader.validate_project_data()
	var schema_counts: Dictionary = DataLoader.schema_counts()
	var contract_count: int = DataLoader.contracts().size()
	var stream_count: int = DataLoader.contract_values("rng_streams").size()
	var settings_count: int = Settings.values().size()
	var analytics_event_count: int = Analytics.registered_events().size()
	var pool_id_count: int = PoolManager.registered_pool_ids().size()
	var save_kind_count: int = SaveManager.registered_save_kinds().size()
	var audio_prefix_count: int = AudioManager.registered_audio_prefixes().size()
	var state_name: StringName = GameState.current()
	_load_last_composition_from_meta()
	print("%s formal client boot scene loaded; contracts=%d rng_streams=%d data_schema_ok=%s mods=%d player_stats=%d weapons=%d enemies=%d hazards=%d spawn_waves=%d active_items=%d consumables=%d skills=%d credits=%d credit_sections=%d characters=%d locale_keys=%d level_progression_profiles=%d reward_choice_pools=%d game_modes=%d map_layouts=%d warzone_directors=%d module_worlds=%d module_templates=%d settings=%d analytics_events=%d analytics_enabled=%s replay_enabled=%s replay_recording=%s platform_provider=%s platform_available=%s pool_ids=%d active_pools=%d save_kinds=%d save_slots=%d audio_prefixes=%d audio_streams=%d audio_buses_ready=%s locale=%s ui_stack=%d state=%s seed=%d" % [
		BOOT_LOG_PREFIX,
		contract_count,
		stream_count,
		str(data_schema_ok),
		int(schema_counts.get("mods", 0)),
		int(schema_counts.get("player_stats", 0)),
		int(schema_counts.get("weapons", 0)),
		int(schema_counts.get("enemies", 0)),
		int(schema_counts.get("hazards", 0)),
		int(schema_counts.get("spawn_waves", 0)),
		int(schema_counts.get("active_items", 0)),
		int(schema_counts.get("consumables", 0)),
		int(schema_counts.get("skills", 0)),
		int(schema_counts.get("credit_entries", 0)),
		int(schema_counts.get("credit_sections", 0)),
		int(schema_counts.get("characters", 0)),
		int(schema_counts.get("locale_keys", 0)),
		int(schema_counts.get("level_progression_profiles", 0)),
		int(schema_counts.get("reward_choice_pools", 0)),
		int(schema_counts.get("game_modes", 0)),
		int(schema_counts.get("map_layouts", 0)),
		int(schema_counts.get("warzone_directors", 0)),
		int(schema_counts.get("module_worlds", 0)),
		int(schema_counts.get("module_templates", 0)),
		settings_count,
		analytics_event_count,
		str(Analytics.is_enabled()),
		str(Replay.is_enabled()),
		str(Replay.is_recording()),
		PlatformServices.active_provider(),
		str(PlatformServices.is_available()),
		pool_id_count,
		PoolManager.pool_count(),
		save_kind_count,
		SaveManager.list_slots().size(),
		audio_prefix_count,
		AudioManager.registered_stream_count(),
		str(AudioManager.required_buses_ready()),
		Localization.current_locale(),
		UIManager.stack_size(),
		String(state_name),
		RNG.run_seed(),
	])

	var test_command_request: Dictionary = _resolve_test_command_request()
	if not bool(test_command_request.get("valid", false)):
		return
	if bool(test_command_request.get("requested", false)):
		var test_command_id: String = String(test_command_request.get("id", ""))
		var test_command: Dictionary = _load_formal_test_command(test_command_id)
		if test_command.is_empty():
			return
		_launch_formal_test_command(test_command, data_schema_ok)
	elif _is_replay_runner_enabled():
		_install_dynamic_runner(REPLAY_RUNNER_SCRIPT_PATH, "ReplayRunner")
	elif _is_rng_audit_enabled():
		_install_dynamic_runner(RNG_AUDIT_SCRIPT_PATH, "RNGAudit")
	elif _is_golden_replay_capture_enabled():
		_install_dynamic_runner(
			GOLDEN_REPLAY_CAPTURE_SCRIPT_PATH,
			"GoldenReplayCapture"
		)
	elif _is_perf_probe_enabled():
		if data_schema_ok:
			_start_gameplay_run()
		_install_dynamic_runner(PERF_PROBE_SCRIPT_PATH, "PerfProbe")
	elif _is_startup_probe_enabled():
		if data_schema_ok:
			_start_gameplay_run()
		_install_dynamic_runner(STARTUP_PROBE_SCRIPT_PATH, "StartupProbe")
	elif _is_gear_mod_pickup_capture_enabled():
		if data_schema_ok:
			_open_warzone_launch = true
			_start_gameplay_run({}, true)
		_install_dynamic_runner(
			GEAR_MOD_PICKUP_CAPTURE_SCRIPT_PATH,
			"GearModPickupCapture"
		)
	elif _module_world_technical_slice_launch:
		if data_schema_ok:
			_start_gameplay_run()
		else:
			_show_title_menu()
	elif _is_open_warzone_launch_enabled():
		_open_warzone_launch = true
		if data_schema_ok:
			_start_gameplay_run({}, true)
		else:
			_show_title_menu()
	elif data_schema_ok:
		_show_title_menu()

	_install_debug_console()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_inside_tree():
		call_deferred("_request_application_quit")


func debug_tools_enabled() -> bool:
	return _debug_tools_enabled()


func debug_active_run_loop() -> Node:
	return _run_loop if _run_loop != null and is_instance_valid(_run_loop) else null


func _resolve_test_command_request() -> Dictionary:
	var requested: bool = false
	var command_id: String = ""
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(user_args.size()):
		if user_args[index] != "--test-command":
			continue
		if requested:
			_fail_test_command("--test-command may only be provided once")
			return {"requested": true, "valid": false}
		requested = true
		if index + 1 >= user_args.size():
			_fail_test_command("--test-command requires a command id")
			return {"requested": true, "valid": false}
		command_id = user_args[index + 1].strip_edges()
		if command_id.is_empty() or command_id.begins_with("--"):
			_fail_test_command("--test-command requires a command id")
			return {"requested": true, "valid": false}
	return {
		"requested": requested,
		"valid": true,
		"id": command_id,
	}


func _load_formal_test_command(command_id: String) -> Dictionary:
	if not FileAccess.file_exists(SMOKE_COMMAND_CATALOG_PATH):
		_fail_test_command(
			"missing smoke command catalog: %s"
			% SMOKE_COMMAND_CATALOG_PATH
		)
		return {}
	var parser := JSON.new()
	var parse_error: Error = parser.parse(
		FileAccess.get_file_as_string(SMOKE_COMMAND_CATALOG_PATH)
	)
	if parse_error != OK:
		_fail_test_command(
			"invalid smoke command catalog JSON at line %d: %s"
			% [parser.get_error_line(), parser.get_error_message()]
		)
		return {}
	if not (parser.data is Dictionary):
		_fail_test_command("smoke command catalog root must be an object")
		return {}
	var payload: Dictionary = parser.data as Dictionary
	if int(payload.get("schema_version", -1)) != SMOKE_COMMAND_CATALOG_SCHEMA_VERSION:
		_fail_test_command(
			"unsupported smoke command catalog schema: %s"
			% str(payload.get("schema_version", null))
		)
		return {}
	var raw_commands: Variant = payload.get("commands", null)
	if not (raw_commands is Array) or (raw_commands as Array).is_empty():
		_fail_test_command("smoke command catalog commands must be a non-empty array")
		return {}
	var selected: Dictionary = {}
	var seen_ids: Dictionary = {}
	for raw_descriptor: Variant in raw_commands as Array:
		if not (raw_descriptor is Dictionary):
			_fail_test_command("smoke command descriptor must be an object")
			return {}
		var descriptor: Dictionary = raw_descriptor as Dictionary
		var descriptor_id: String = String(descriptor.get("id", ""))
		if descriptor_id.is_empty():
			_fail_test_command("smoke command descriptor requires a non-empty id")
			return {}
		if seen_ids.has(descriptor_id):
			_fail_test_command("duplicate smoke command id: %s" % descriptor_id)
			return {}
		seen_ids[descriptor_id] = true
		if descriptor_id == command_id:
			selected = descriptor.duplicate(true)
	if selected.is_empty():
		_fail_test_command("unknown test command: %s" % command_id)
		return {}
	if String(selected.get("runner_type", "")) != "formal_boot":
		_fail_test_command(
			"test command is not a FormalClientBoot runner: %s" % command_id
		)
		return {}
	var runner_path: String = String(selected.get("runner_path", ""))
	if (
		not runner_path.begins_with("res://")
		or not runner_path.ends_with(".gd")
		or runner_path.contains("..")
		or not ResourceLoader.exists(runner_path)
	):
		_fail_test_command(
			"invalid FormalClientBoot runner path for %s: %s"
			% [command_id, runner_path]
		)
		return {}
	var runner_node_name: String = String(selected.get("runner_node_name", ""))
	if runner_node_name.is_empty():
		_fail_test_command("test command requires runner_node_name: %s" % command_id)
		return {}
	var setup: String = String(selected.get("formal_boot_setup", ""))
	if setup not in [
		"runner_only",
		"show_title_menu",
		"start_gameplay",
		"start_open_warzone",
		"start_module_world_technical",
	]:
		_fail_test_command(
			"unsupported FormalClientBoot setup for %s: %s"
			% [command_id, setup]
		)
		return {}
	return selected


func _launch_formal_test_command(
	descriptor: Dictionary,
	data_schema_ok: bool
) -> void:
	var setup: String = String(descriptor.get("formal_boot_setup", ""))
	match setup:
		"runner_only":
			pass
		"show_title_menu":
			if data_schema_ok:
				_show_title_menu()
		"start_gameplay", "start_module_world_technical":
			if setup == "start_module_world_technical":
				_module_world_technical_slice_launch = true
			if data_schema_ok:
				_start_gameplay_run()
		"start_open_warzone":
			if data_schema_ok:
				_open_warzone_launch = true
				_start_gameplay_run({}, true)
		_:
			_fail_test_command("unsupported FormalClientBoot setup: %s" % setup)
			return
	_install_dynamic_runner(
		String(descriptor.get("runner_path", "")),
		String(descriptor.get("runner_node_name", ""))
	)


func _fail_test_command(message: String) -> void:
	push_error("%s test command rejected: %s" % [BOOT_LOG_PREFIX, message])
	get_tree().quit(1)


func _is_module_world_technical_slice_launch_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--module-world-technical-slice")


## Debug-only regression launch for the former open-warzone carrier. The seamless module
## world is the standard path; this flag keeps F12 comparisons available without PCG overlap.
func _is_open_warzone_launch_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--open-warzone")


func _is_replay_runner_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--replay-runner")


func _is_rng_audit_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--rng-audit")


func _is_golden_replay_capture_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--capture-golden-replay")


func _is_perf_probe_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--perf-probe")


func _is_startup_probe_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--startup-probe")


func _is_gear_mod_pickup_capture_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--capture-gear-mod-pickup")


func _is_automation_progress_isolated() -> bool:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--test-command":
			return true
		if argument in [
			"--replay-runner",
			"--capture-golden-replay",
			"--capture-gear-mod-pickup",
			"--rng-audit",
			"--perf-probe",
			"--startup-probe",
		]:
			return true
	return false


func _show_title_menu(notice_key: String = "") -> void:
	_player_load_in_progress = false
	_loading_screen = null
	_hero_composition_panel = null
	_codex_panel = null
	_mod_panel = null
	_clear_gameplay_runtime()
	ModLoader.set_runtime_activity(false, false)
	GameState.change_state(GameState.MAIN_MENU, {"source": "formal_client_boot"})
	UIManager.clear(true)

	_title_menu = UIManager.push(TITLE_MENU_SCENE, {"source": "formal_client_boot"}) as CanvasLayer
	if _title_menu == null:
		return
	var run_status: Dictionary = SaveManager.save_status(
		SaveManager.DEFAULT_SLOT,
		SAVE_KINDS.RUN
	)
	var resolved_notice_key: String = notice_key
	var preserved_incompatible: bool = bool(
		run_status.get("preserved_incompatible", false)
	)
	if (
		resolved_notice_key.is_empty()
		and bool(run_status.get("exists", false))
		and preserved_incompatible
	):
		resolved_notice_key = "ui_run_save_environment_incompatible"
	var run_can_continue: bool = (
		bool(run_status.get("compatible", false))
		or (
			bool(run_status.get("exists", false))
			and not preserved_incompatible
		)
	)
	_title_menu.call(
		"configure",
		run_can_continue,
		resolved_notice_key
	)
	_title_menu.connect("start_requested", Callable(self, "_on_title_start_requested"))
	_title_menu.connect("continue_requested", Callable(self, "_on_title_continue_requested"), CONNECT_ONE_SHOT)
	_title_menu.connect("settings_requested", Callable(self, "_on_title_settings_requested"))
	_title_menu.connect("codex_requested", Callable(self, "_on_title_codex_requested"))
	_title_menu.connect("mods_requested", Callable(self, "_on_title_mods_requested"))
	_title_menu.connect("quit_requested", Callable(self, "_on_title_quit_requested"))
	_request_deferred_application_quit_after_loading()


func _start_gameplay_run(
	restore_snapshot: Dictionary = {},
	open_warzone: bool = false,
	hero_composition: Dictionary = {},
	difficulty_profile_id: String = ""
) -> void:
	UIManager.clear(true)
	GameState.change_state(GameState.LOADING, {"source": "formal_client_boot"})
	_mount_gameplay_run(
		restore_snapshot,
		open_warzone,
		false,
		hero_composition,
		difficulty_profile_id
	)


func _mount_gameplay_run(
	restore_snapshot: Dictionary,
	open_warzone: bool,
	player_loading_mode: bool,
	hero_composition: Dictionary = {},
	difficulty_profile_id: String = ""
) -> void:
	_clear_gameplay_runtime()
	ModLoader.set_runtime_activity(true, Replay.is_recording())

	_run_loop = GAMEPLAY_RUN_LOOP_SCENE.instantiate()
	var selected_difficulty_profile_id: String = (
		difficulty_profile_id.strip_edges()
	)
	if selected_difficulty_profile_id.is_empty():
		selected_difficulty_profile_id = String(
			(
				restore_snapshot.get("difficulty", {})
				as Dictionary
			).get("profile_id", "")
		).strip_edges()
	_active_difficulty_profile_id = selected_difficulty_profile_id
	if (
		not selected_difficulty_profile_id.is_empty()
		and _run_loop.has_method("configure_difficulty_profile_id")
	):
		_run_loop.call(
			"configure_difficulty_profile_id",
			selected_difficulty_profile_id
		)
	var composition_ids: Dictionary = _composition_ids_for_run(
		restore_snapshot,
		hero_composition
	)
	var main_hero_id: String = String(composition_ids.get("main_hero_id", ""))
	var sub_hero_id: String = String(composition_ids.get("sub_hero_id", ""))
	if (
		not main_hero_id.is_empty()
		and not sub_hero_id.is_empty()
		and _run_loop.has_method("configure_hero_composition")
	):
		_run_loop.call("configure_hero_composition", main_hero_id, sub_hero_id)
	var fallback_character_id: String = main_hero_id
	if fallback_character_id.is_empty() and not CHARACTER_IDS.VALUES.is_empty():
		fallback_character_id = String(CHARACTER_IDS.VALUES[0])
	var character_id: String = String(
		restore_snapshot.get("character", fallback_character_id)
	)
	if _run_loop.has_method("configure_character_id"):
		_run_loop.call("configure_character_id", character_id)
	if _module_world_technical_slice_launch and _run_loop.has_method("debug_enable_module_world_technical_slice"):
		_run_loop.call("debug_enable_module_world_technical_slice")
	if open_warzone and _run_loop.has_method("debug_enable_open_warzone"):
		_run_loop.call("debug_enable_open_warzone")
	if not restore_snapshot.is_empty() and _run_loop.has_method("configure_restore_snapshot"):
		_run_loop.call("configure_restore_snapshot", restore_snapshot)
	if player_loading_mode and _run_loop.has_method("configure_player_loading_mode"):
		_run_loop.call("configure_player_loading_mode", true)
	var content_availability: Variant = hero_composition.get(
		"content_availability",
		null
	)
	if (
		content_availability is Dictionary
		and _run_loop.has_method("configure_content_availability")
	):
		_run_loop.call(
			"configure_content_availability",
			(content_availability as Dictionary).duplicate(true)
		)
	if _run_loop.has_method("configure_content_progress_commits_enabled"):
		var commits_enabled: bool = bool(
			hero_composition.get("content_progress_commits_enabled", true)
		)
		if _is_automation_progress_isolated():
			commits_enabled = false
		_run_loop.call(
			"configure_content_progress_commits_enabled",
			commits_enabled
		)
	_run_loop.connect("restart_requested", Callable(self, "_on_run_restart_requested"))
	_run_loop.connect("quit_to_title_requested", Callable(self, "_on_run_quit_to_title_requested"))
	if player_loading_mode:
		_run_loop.connect(
			"run_prepared",
			Callable(self, "_on_player_run_prepared"),
			CONNECT_ONE_SHOT
		)
		_run_loop.connect(
			"run_prepare_failed",
			Callable(self, "_on_player_run_prepare_failed"),
			CONNECT_ONE_SHOT
		)
	elif _run_loop.has_signal("restore_failed"):
		_run_loop.connect("restore_failed", Callable(self, "_on_run_restore_failed"), CONNECT_ONE_SHOT)
	add_child(_run_loop)


func _begin_player_gameplay_load(
	load_mode: PlayerLoadMode,
	open_warzone: bool = false,
	hero_composition: Dictionary = {},
	difficulty_profile_id: String = ""
) -> void:
	if _player_load_in_progress:
		return
	_player_load_in_progress = true
	GameState.change_state(GameState.LOADING, {"source": "formal_client_boot"})
	UIManager.clear(true)
	_loading_screen = UIManager.push(
		LOADING_SCREEN_SCENE,
		{"source": "formal_client_boot"}
	) as CanvasLayer
	if _loading_screen == null:
		_player_load_in_progress = false
		call_deferred("_show_title_menu", "ui_loading_failed")
		return
	call_deferred(
		"_perform_player_gameplay_load",
		load_mode,
		open_warzone,
		hero_composition,
		difficulty_profile_id
	)


func _composition_ids_for_run(
	restore_snapshot: Dictionary,
	hero_composition: Dictionary = {}
) -> Dictionary:
	var requested_main_id: String = String(hero_composition.get("main_hero_id", ""))
	var requested_sub_id: String = String(hero_composition.get("sub_hero_id", ""))
	if not requested_main_id.is_empty() and not requested_sub_id.is_empty():
		_last_main_hero_id = requested_main_id
		_last_sub_hero_id = requested_sub_id
		return {
			"main_hero_id": requested_main_id,
			"sub_hero_id": requested_sub_id,
		}
	if not restore_snapshot.is_empty():
		var composition: Dictionary = restore_snapshot.get("hero_composition", {}) as Dictionary
		var restored_main_id: String = String(
			composition.get(
				"main_hero_id",
				restore_snapshot.get("main_hero_id", restore_snapshot.get("character", ""))
			)
		)
		var restored_sub_id: String = String(
			composition.get("sub_hero_id", restore_snapshot.get("sub_hero_id", ""))
		)
		if not restored_main_id.is_empty() and not restored_sub_id.is_empty():
			_last_main_hero_id = restored_main_id
			_last_sub_hero_id = restored_sub_id
			return {
				"main_hero_id": restored_main_id,
				"sub_hero_id": restored_sub_id,
			}
	_ensure_default_composition()
	return {
		"main_hero_id": _last_main_hero_id,
		"sub_hero_id": _last_sub_hero_id,
	}


func _ensure_default_composition() -> void:
	var hero_rows: Array[Dictionary] = _hero_rows()
	if hero_rows.is_empty():
		return
	if _last_main_hero_id.is_empty():
		_last_main_hero_id = String(hero_rows[0].get("id", ""))
	if _last_sub_hero_id.is_empty():
		var sub_index: int = 1 if hero_rows.size() > 1 else 0
		_last_sub_hero_id = String(hero_rows[sub_index].get("id", ""))


func _load_last_composition_from_meta() -> void:
	if not SaveManager.has_save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.META):
		return
	var profile: Dictionary = SaveManager.load(
		SaveManager.DEFAULT_SLOT,
		SAVE_KINDS.META
	)
	var composition: Dictionary = profile.get("hero_composition", {}) as Dictionary
	_last_main_hero_id = String(composition.get("main_hero_id", ""))
	_last_sub_hero_id = String(composition.get("sub_hero_id", ""))


func _save_last_composition_to_meta() -> void:
	var profile: Dictionary = {}
	if SaveManager.has_save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.META):
		profile = SaveManager.load(
			SaveManager.DEFAULT_SLOT,
			SAVE_KINDS.META
		)
	profile["hero_composition"] = {
		"main_hero_id": _last_main_hero_id,
		"sub_hero_id": _last_sub_hero_id,
	}
	if not SaveManager.save(
		SaveManager.DEFAULT_SLOT,
		SAVE_KINDS.META,
		profile
	):
		push_warning(
			"[FormalClientBoot] failed to save confirmed hero composition: %s"
			% SaveManager.last_error()
		)


func _hero_rows() -> Array[Dictionary]:
	var payload: Dictionary = DataLoader.load_json(DataLoader.CHARACTERS_PATH) as Dictionary
	var rows: Array[Dictionary] = []
	for row: Variant in payload.get("characters", []):
		if row is Dictionary:
			rows.append((row as Dictionary).duplicate(true))
	return rows


func _perform_player_gameplay_load(
	load_mode: PlayerLoadMode,
	open_warzone: bool,
	hero_composition: Dictionary,
	difficulty_profile_id: String
) -> void:
	await get_tree().process_frame
	if not is_instance_valid(self) or not _player_load_in_progress:
		return

	var restore_snapshot: Dictionary = {}
	match load_mode:
		PlayerLoadMode.NEW_RUN:
			SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
			RNG.set_random_run_seed()
		PlayerLoadMode.CONTINUE_RUN:
			var envelope: Dictionary = SaveManager.load_envelope(
				SaveManager.DEFAULT_SLOT,
				SAVE_KINDS.RUN
			)
			if envelope.is_empty():
				var load_error: String = SaveManager.last_error()
				push_warning(
					"[FormalClientBoot] run save unavailable: %s"
					% load_error
				)
				_abort_player_gameplay_load(
					_run_save_unavailable_notice_key({})
				)
				return
			restore_snapshot = envelope.get("payload", {}) as Dictionary
			if bool(restore_snapshot.get("legacy_run_incompatible", false)):
				var notice_key: String = _run_save_unavailable_notice_key(
					restore_snapshot
				)
				SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
				push_warning("[FormalClientBoot] run save unavailable: legacy run schema is incompatible")
				_abort_player_gameplay_load(notice_key)
				return
			if restore_snapshot.is_empty():
				push_warning(
					"[FormalClientBoot] run save unavailable: empty payload"
				)
				_abort_player_gameplay_load(
					_run_save_unavailable_notice_key(restore_snapshot)
				)
				return
		_:
			_abort_player_gameplay_load("ui_loading_failed")
			return

	_mount_gameplay_run(
		restore_snapshot,
		open_warzone,
		true,
		hero_composition,
		difficulty_profile_id
	)


func _on_player_run_prepared() -> void:
	if not _player_load_in_progress or _run_loop == null:
		return
	var loading_screen: CanvasLayer = _loading_screen
	if UIManager.top() == _loading_screen:
		UIManager.pop_expected(_loading_screen)
	elif _loading_screen != null and is_instance_valid(_loading_screen):
		push_error("[FormalClientBoot] loading screen is not the top UI")
		_abort_player_gameplay_load("ui_loading_failed")
		return
	while (
		loading_screen != null
		and is_instance_valid(loading_screen)
		and UIManager.ui_state(loading_screen) != UIManager.UIState.REMOVED
	):
		var removed_node: Node = await UIManager.ui_removed
		if removed_node == loading_screen:
			break
	_loading_screen = null
	_player_load_in_progress = false
	if (
		not _run_loop.has_method("activate_prepared_run")
		or not bool(_run_loop.call("activate_prepared_run"))
	):
		_abort_player_gameplay_load("ui_loading_failed")
		return
	_request_deferred_application_quit_after_loading()


func _on_player_run_prepare_failed(reason: String, restoring: bool) -> void:
	push_warning("[FormalClientBoot] gameplay preparation failed: %s" % reason)
	var save_unavailable: bool = restoring and _is_restore_snapshot_unavailable(reason)
	if save_unavailable:
		SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	call_deferred(
		"_abort_player_gameplay_load",
		"ui_run_save_unavailable" if save_unavailable else "ui_loading_failed"
	)


func _is_restore_snapshot_unavailable(reason: String) -> bool:
	return (
		reason.begins_with("unknown character id:")
		or reason.begins_with("invalid hero composition:")
		or reason == "hero composition contains locked content"
		or reason == "run snapshot restore failed"
	)


func _abort_player_gameplay_load(notice_key: String) -> void:
	_player_load_in_progress = false
	_loading_screen = null
	_clear_gameplay_runtime()
	call_deferred("_show_title_menu", notice_key)


func _clear_gameplay_runtime() -> void:
	if _run_loop != null and is_instance_valid(_run_loop):
		var parent: Node = _run_loop.get_parent()
		if parent != null:
			parent.remove_child(_run_loop)
		_run_loop.queue_free()
	_run_loop = null
	ModLoader.set_runtime_activity(false, false)
	PoolManager.clear_pool(POOL_IDS.BULLET_BASIC)
	for enemy_row: Dictionary in DataLoader.load_csv(DataLoader.ENEMIES_PATH):
		var pool_id: String = String(enemy_row.get("pool_id", ""))
		if not pool_id.is_empty():
			PoolManager.clear_pool(pool_id)
	PoolManager.clear_pool(POOL_IDS.HAZARD_SPIKE)
	PoolManager.clear_pool(POOL_IDS.HIT_SPARK)
	PoolManager.clear_pool(POOL_IDS.DAMAGE_NUMBER)
	PoolManager.clear_pool(POOL_IDS.GOLD_ORB)
	PoolManager.clear_pool(POOL_IDS.ENERGY_ORB)
	PoolManager.clear_pool(POOL_IDS.GEAR_MOD_PICKUP)
	PoolManager.clear_pool(POOL_IDS.PROJECTILE_BARRIER)
	PoolManager.clear_pool(POOL_IDS.VFX_ENEMY_EXPLOSION_TELEGRAPH)
	PoolManager.clear_pool(POOL_IDS.VFX_ENEMY_MELEE_TELEGRAPH)
	PoolManager.clear_pool(POOL_IDS.VFX_ENEMY_CHARGE_TELEGRAPH)
	PoolManager.clear_pool(POOL_IDS.VFX_ENEMY_EXPLOSION_IMPACT)


func _on_title_start_requested() -> void:
	if _hero_composition_panel != null and is_instance_valid(_hero_composition_panel):
		return
	_ensure_default_composition()
	_hero_composition_panel = UIManager.push(
		HERO_COMPOSITION_PANEL_SCENE,
		{"source": "title_menu"}
	) as CanvasLayer
	if _hero_composition_panel == null:
		return
	_hero_composition_panel.call(
		"configure",
		_hero_rows(),
		_last_main_hero_id,
		_last_sub_hero_id
	)
	_hero_composition_panel.connect(
		"composition_confirmed",
		Callable(self, "_on_composition_confirmed"),
		CONNECT_ONE_SHOT
	)
	_hero_composition_panel.connect(
		"cancel_requested",
		Callable(self, "_on_composition_cancel_requested"),
		CONNECT_ONE_SHOT
	)


func _on_composition_confirmed(main_hero_id: String, sub_hero_id: String) -> void:
	if main_hero_id.is_empty() or sub_hero_id.is_empty() or main_hero_id == sub_hero_id:
		return
	_last_main_hero_id = main_hero_id
	_last_sub_hero_id = sub_hero_id
	_save_last_composition_to_meta()
	_hero_composition_panel = null
	_begin_player_gameplay_load(
		PlayerLoadMode.NEW_RUN,
		_open_warzone_launch,
		{
			"main_hero_id": main_hero_id,
			"sub_hero_id": sub_hero_id,
		}
	)


func _on_composition_cancel_requested() -> void:
	if _hero_composition_panel != null and is_instance_valid(_hero_composition_panel):
		UIManager.remove_expected(_hero_composition_panel)
	_hero_composition_panel = null


func _on_title_continue_requested() -> void:
	_begin_player_gameplay_load(
		PlayerLoadMode.CONTINUE_RUN,
		_open_warzone_launch
	)


func _run_save_unavailable_notice_key(payload: Dictionary) -> String:
	if bool(payload.get("legacy_run_incompatible", false)):
		return "ui_run_save_legacy_incompatible"
	return "ui_run_save_unavailable"


func _on_title_quit_requested() -> void:
	_request_application_quit()


func _request_application_quit() -> void:
	if _player_load_in_progress:
		_application_quit_deferred_for_loading = true
		return
	if _application_quit_modal != null and is_instance_valid(_application_quit_modal):
		return
	if _application_quit_waiting_for_confirmation:
		return
	var top_node: Node = UIManager.top()
	if top_node is ConfirmationModal:
		_application_quit_waiting_for_confirmation = true
		(top_node as ConfirmationModal).request_cancel()
		_wait_for_confirmation_then_request_application_quit(
			top_node as ConfirmationModal
		)
		return
	_application_quit_modal = UIManager.push(
		APPLICATION_QUIT_MODAL_SCENE,
		{"source": "application_quit"}
	) as ConfirmationModal
	if _application_quit_modal == null:
		return
	_application_quit_modal.configure(
		tr("ui_quit_confirm_title"),
		tr(_application_quit_body_key),
		tr("ui_save_and_quit"),
		tr("ui_cancel")
	)
	_application_quit_body_key = UI_QUIT_CONFIRM_BODY
	_application_quit_modal.confirmed.connect(
		_on_application_quit_confirmed,
		CONNECT_ONE_SHOT
	)
	_application_quit_modal.cancelled.connect(
		_on_application_quit_cancelled,
		CONNECT_ONE_SHOT
	)


func _request_deferred_application_quit_after_loading() -> void:
	if not _application_quit_deferred_for_loading:
		return
	_application_quit_deferred_for_loading = false
	call_deferred("_request_application_quit")


func _wait_for_confirmation_then_request_application_quit(
		modal: ConfirmationModal
	) -> void:
	while (
		modal != null
		and is_instance_valid(modal)
		and UIManager.ui_state(modal) != UIManager.UIState.REMOVED
	):
		var removed_node: Node = await UIManager.ui_removed
		if not is_instance_valid(self):
			return
		if removed_node == modal:
			break
	_application_quit_waiting_for_confirmation = false
	_request_application_quit()


func _active_run_can_save_for_application_quit() -> bool:
	if _run_loop == null or not is_instance_valid(_run_loop):
		return false
	match GameState.current():
		GameState.PLAYING, GameState.PAUSED, GameState.REWARD_CHOICE:
			return true
		_:
			return false


func _on_application_quit_confirmed() -> void:
	var modal: ConfirmationModal = _application_quit_modal
	_application_quit_modal = null
	if modal != null and is_instance_valid(modal):
		UIManager.remove_expected(modal, true)
	var should_save_run: bool = _active_run_can_save_for_application_quit()
	if should_save_run and not _save_active_run_for_application_quit():
		_application_quit_body_key = UI_QUIT_SAVE_FAILED_BODY
		_request_application_quit()
		return
	get_tree().quit()


func _on_application_quit_cancelled() -> void:
	var modal: ConfirmationModal = _application_quit_modal
	_application_quit_modal = null
	_application_quit_body_key = UI_QUIT_CONFIRM_BODY
	if modal != null and is_instance_valid(modal):
		UIManager.remove_expected(modal)


func _save_active_run_for_application_quit() -> bool:
	if (
		_run_loop == null
		or not is_instance_valid(_run_loop)
		or not _run_loop.has_method("save_run_snapshot")
	):
		push_error("[FormalClientBoot] active run cannot create a quit save")
		return false
	return bool(_run_loop.call("save_run_snapshot"))


func _on_title_codex_requested() -> void:
	if _codex_panel != null and is_instance_valid(_codex_panel):
		return
	_codex_panel = UIManager.push(
		CODEX_PANEL_SCENE,
		{"source": "title_menu"}
	) as CanvasLayer
	if _codex_panel == null:
		return
	_codex_panel.connect(
		"closed_requested",
		Callable(self, "_on_codex_panel_closed"),
		CONNECT_ONE_SHOT
	)


func _on_codex_panel_closed() -> void:
	if UIManager.top() == _codex_panel:
		UIManager.pop_expected(_codex_panel)
	_codex_panel = null


func _on_title_mods_requested() -> void:
	if _mod_panel != null and is_instance_valid(_mod_panel):
		return
	_mod_panel = UIManager.push(
		MOD_PANEL_SCENE,
		{"source": "title_menu"}
	) as CanvasLayer
	if _mod_panel == null:
		return
	_mod_panel.connect(
		"closed_requested",
		Callable(self, "_on_mod_panel_closed"),
		CONNECT_ONE_SHOT
	)


func _on_mod_panel_closed() -> void:
	if UIManager.top() == _mod_panel:
		UIManager.pop_expected(_mod_panel)
	_mod_panel = null


func _on_title_settings_requested() -> void:
	if _settings_panel != null and is_instance_valid(_settings_panel):
		return
	_settings_panel = UIManager.push(SETTINGS_PANEL_SCENE, {"source": "title_menu"}) as CanvasLayer
	if _settings_panel == null:
		return
	_settings_panel.connect("closed_requested", Callable(self, "_on_settings_panel_closed"), CONNECT_ONE_SHOT)


func _on_settings_panel_closed() -> void:
	if UIManager.top() == _settings_panel:
		UIManager.pop()
	_settings_panel = null


func _on_run_restart_requested() -> void:
	_begin_player_gameplay_load(
		PlayerLoadMode.NEW_RUN,
		_open_warzone_launch,
		{
			"main_hero_id": _last_main_hero_id,
			"sub_hero_id": _last_sub_hero_id,
		},
		_active_difficulty_profile_id
	)


func _on_run_quit_to_title_requested() -> void:
	call_deferred("_show_title_menu")


func _on_run_restore_failed() -> void:
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	call_deferred("_show_title_menu", "ui_run_save_unavailable")


func _install_dynamic_runner(
	script_path: String,
	node_name: String
) -> void:
	var runner_script: GDScript = load(script_path) as GDScript
	if runner_script == null:
		push_error(
			"[FormalClientBoot] missing runner script: %s"
			% script_path
		)
		get_tree().quit(1)
		return
	var runner: Node = runner_script.new() as Node
	if runner == null:
		push_error(
			"[FormalClientBoot] runner script is not a Node: %s"
			% script_path
		)
		get_tree().quit(1)
		return
	runner.name = node_name
	add_child(runner)


func _install_debug_console() -> void:
	if not _debug_tools_enabled():
		return
	if _debug_console != null and is_instance_valid(_debug_console):
		return
	var console_script: GDScript = load(DEBUG_CONSOLE_SCRIPT_PATH) as GDScript
	if console_script == null:
		push_error("[FormalClientBoot] missing debug console script: %s" % DEBUG_CONSOLE_SCRIPT_PATH)
		return
	var console_node: CanvasLayer = console_script.new() as CanvasLayer
	if console_node == null:
		push_error("[FormalClientBoot] debug console script did not create a CanvasLayer")
		return
	console_node.name = "DebugConsole"
	add_child(console_node)
	console_node.call("setup", self, true)
	_debug_console = console_node


func _debug_tools_enabled() -> bool:
	if OS.get_cmdline_user_args().has("--force-release-debug-tools-off"):
		return false
	return OS.is_debug_build() or OS.has_feature("dev_tools")
