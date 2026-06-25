# Doc: docs/代码/formal_client_boot.md
# Authority: docs/正式项目工作规划.md F1, docs/游戏设计文档.md §9
class_name FormalClientBoot
extends Node


const BOOT_LOG_PREFIX: String = "[FormalClientBoot]"
const DEBUG_CONSOLE_SCRIPT_PATH: String = "res://scripts/debug/debug_console.gd"
const DEBUG_TOOLS_SMOKE_RUNNER := preload("res://tools/debug_tools_smoke.gd")
const F9_DEMO_SMOKE_RUNNER := preload("res://tools/f9_demo_smoke.gd")
const GAMEPLAY_RUN_LOOP_SCENE := preload("res://scenes/gameplay/gameplay_run_loop.tscn")
const GEAR_MOD_PANEL_SCENE := preload("res://scenes/ui/gear_mod_panel.tscn")
const GEAR_MOD_SMOKE_RUNNER := preload("res://tools/gear_mod_smoke.gd")
const GOLDEN_REPLAY_CAPTURE_RUNNER := preload("res://tools/golden_replay_capture.gd")
const L1_SMOKE_RUNNER := preload("res://tools/l1_smoke.gd")
const RUNTIME_SMOKE_RUNNER := preload("res://tools/runtime_smoke.gd")
const TITLE_MENU_SCENE := preload("res://scenes/ui/title_menu.tscn")
const PERF_PROBE_RUNNER := preload("res://tools/perf_probe.gd")
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const REPLAY_INPUT_SMOKE_RUNNER := preload("res://tools/replay_input_smoke.gd")
const REPLAY_RUNNER := preload("res://tools/replay_runner.gd")
const REPLAY_SMOKE_RUNNER := preload("res://tools/replay_smoke.gd")
const RNG_AUDIT_RUNNER := preload("res://tools/rng_audit.gd")
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")
const SAVE_SMOKE_RUNNER := preload("res://tools/save_manager_smoke.gd")
const SETTINGS_SMOKE_RUNNER := preload("res://tools/settings_smoke.gd")
const SETTINGS_PANEL_SCENE := preload("res://scenes/ui/settings_panel.tscn")

var _run_loop: Node = null
var _debug_console: CanvasLayer = null
var _gear_mod_panel: CanvasLayer = null
var _settings_panel: CanvasLayer = null
var _title_menu: CanvasLayer = null


func _ready() -> void:
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
	print("%s formal client boot scene loaded; contracts=%d rng_streams=%d data_schema_ok=%s mods=%d player_stats=%d weapons=%d enemies=%d hazards=%d spawn_waves=%d relics=%d active_items=%d consumables=%d skills=%d credits=%d credit_sections=%d characters=%d locale_keys=%d growth_levels=%d growth_pools=%d game_modes=%d map_layouts=%d warzone_directors=%d settings=%d analytics_events=%d analytics_enabled=%s replay_enabled=%s replay_recording=%s platform_provider=%s platform_available=%s pool_ids=%d active_pools=%d save_kinds=%d save_slots=%d audio_prefixes=%d audio_streams=%d audio_buses_ready=%s locale=%s ui_stack=%d state=%s seed=%d" % [
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
		int(schema_counts.get("relics", 0)),
		int(schema_counts.get("active_items", 0)),
		int(schema_counts.get("consumables", 0)),
		int(schema_counts.get("skills", 0)),
		int(schema_counts.get("credit_entries", 0)),
		int(schema_counts.get("credit_sections", 0)),
		int(schema_counts.get("characters", 0)),
		int(schema_counts.get("locale_keys", 0)),
		int(schema_counts.get("growth_levels", 0)),
		int(schema_counts.get("growth_pools", 0)),
		int(schema_counts.get("game_modes", 0)),
		int(schema_counts.get("map_layouts", 0)),
		int(schema_counts.get("warzone_directors", 0)),
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

	if _is_l1_smoke_enabled():
		var l1_smoke_runner: Node = L1_SMOKE_RUNNER.new()
		l1_smoke_runner.name = "L1Smoke"
		add_child(l1_smoke_runner)
	elif _is_replay_smoke_enabled():
		var replay_smoke_runner: Node = REPLAY_SMOKE_RUNNER.new()
		replay_smoke_runner.name = "ReplaySmoke"
		add_child(replay_smoke_runner)
	elif _is_replay_runner_enabled():
		var replay_runner: Node = REPLAY_RUNNER.new()
		replay_runner.name = "ReplayRunner"
		add_child(replay_runner)
	elif _is_replay_input_smoke_enabled():
		var replay_input_smoke_runner: Node = REPLAY_INPUT_SMOKE_RUNNER.new()
		replay_input_smoke_runner.name = "ReplayInputSmoke"
		add_child(replay_input_smoke_runner)
	elif _is_rng_audit_enabled():
		var rng_audit_runner: Node = RNG_AUDIT_RUNNER.new()
		rng_audit_runner.name = "RNGAudit"
		add_child(rng_audit_runner)
	elif _is_golden_replay_capture_enabled():
		var golden_capture_runner: Node = GOLDEN_REPLAY_CAPTURE_RUNNER.new()
		golden_capture_runner.name = "GoldenReplayCapture"
		add_child(golden_capture_runner)
	elif _is_perf_probe_enabled():
		if data_schema_ok:
			_start_gameplay_run()
		var perf_probe_runner: Node = PERF_PROBE_RUNNER.new()
		perf_probe_runner.name = "PerfProbe"
		add_child(perf_probe_runner)
	elif _is_debug_tools_smoke_enabled():
		if data_schema_ok:
			_start_gameplay_run()
		var debug_tools_smoke_runner: Node = DEBUG_TOOLS_SMOKE_RUNNER.new()
		debug_tools_smoke_runner.name = "DebugToolsSmoke"
		add_child(debug_tools_smoke_runner)
	elif _is_f9_demo_smoke_enabled():
		if data_schema_ok:
			_start_gameplay_run()
		var f9_demo_smoke_runner: Node = F9_DEMO_SMOKE_RUNNER.new()
		f9_demo_smoke_runner.name = "F9DemoSmoke"
		add_child(f9_demo_smoke_runner)
	elif _is_runtime_smoke_enabled():
		if data_schema_ok:
			_start_gameplay_run()
		var smoke_runner: Node = RUNTIME_SMOKE_RUNNER.new()
		smoke_runner.name = "RuntimeSmoke"
		add_child(smoke_runner)
	elif _is_save_smoke_enabled():
		var save_smoke_runner: Node = SAVE_SMOKE_RUNNER.new()
		save_smoke_runner.name = "SaveManagerSmoke"
		add_child(save_smoke_runner)
	elif _is_gear_mod_smoke_enabled():
		var gear_mod_smoke_runner: Node = GEAR_MOD_SMOKE_RUNNER.new()
		gear_mod_smoke_runner.name = "GearModSmoke"
		add_child(gear_mod_smoke_runner)
	elif _is_settings_smoke_enabled():
		var settings_smoke_runner: Node = SETTINGS_SMOKE_RUNNER.new()
		settings_smoke_runner.name = "SettingsSmoke"
		add_child(settings_smoke_runner)
	elif data_schema_ok:
		_show_title_menu()

	_install_debug_console()


func debug_tools_enabled() -> bool:
	return _debug_tools_enabled()


func debug_active_run_loop() -> Node:
	return _run_loop if _run_loop != null and is_instance_valid(_run_loop) else null


func _is_runtime_smoke_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--runtime-smoke") or OS.get_cmdline_user_args().has("--f4-smoke")


func _is_l1_smoke_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--l1-smoke")


func _is_replay_smoke_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--replay-smoke")


func _is_replay_runner_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--replay-runner")


func _is_replay_input_smoke_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--replay-input-smoke")


func _is_rng_audit_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--rng-audit")


func _is_golden_replay_capture_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--capture-golden-replay")


func _is_perf_probe_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--perf-probe")


func _is_debug_tools_smoke_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--debug-tools-smoke")


func _is_f9_demo_smoke_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--f9-demo-smoke")


func _is_save_smoke_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--save-smoke")


func _is_gear_mod_smoke_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--gear-mod-smoke")


func _is_settings_smoke_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--settings-smoke")


func _show_title_menu(notice_key: String = "") -> void:
	_clear_gameplay_runtime()
	GameState.change_state(GameState.MAIN_MENU, {"source": "formal_client_boot"})
	UIManager.clear()

	_title_menu = UIManager.push(TITLE_MENU_SCENE, {"source": "formal_client_boot"}) as CanvasLayer
	if _title_menu == null:
		return
	_title_menu.call("configure", SaveManager.has_save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN), notice_key)
	_title_menu.connect("start_requested", Callable(self, "_on_title_start_requested"), CONNECT_ONE_SHOT)
	_title_menu.connect("continue_requested", Callable(self, "_on_title_continue_requested"), CONNECT_ONE_SHOT)
	_title_menu.connect("gear_mod_requested", Callable(self, "_on_title_gear_mod_requested"))
	_title_menu.connect("settings_requested", Callable(self, "_on_title_settings_requested"))
	_title_menu.connect("quit_requested", Callable(self, "_on_title_quit_requested"), CONNECT_ONE_SHOT)


func _start_gameplay_run(restore_snapshot: Dictionary = {}) -> void:
	UIManager.clear()
	GameState.change_state(GameState.LOADING, {"source": "formal_client_boot"})
	_clear_gameplay_runtime()

	_run_loop = GAMEPLAY_RUN_LOOP_SCENE.instantiate()
	if not restore_snapshot.is_empty() and _run_loop.has_method("configure_restore_snapshot"):
		_run_loop.call("configure_restore_snapshot", restore_snapshot)
	_run_loop.connect("restart_requested", Callable(self, "_on_run_restart_requested"))
	_run_loop.connect("quit_to_title_requested", Callable(self, "_on_run_quit_to_title_requested"))
	add_child(_run_loop)


func _start_new_gameplay_run() -> void:
	RNG.set_random_run_seed()
	_start_gameplay_run()


func _clear_gameplay_runtime() -> void:
	if _run_loop != null and is_instance_valid(_run_loop):
		var parent: Node = _run_loop.get_parent()
		if parent != null:
			parent.remove_child(_run_loop)
		_run_loop.queue_free()
	_run_loop = null
	PoolManager.clear_pool(POOL_IDS.BULLET_BASIC)
	PoolManager.clear_pool(POOL_IDS.ENEMY_CHASER)
	PoolManager.clear_pool(POOL_IDS.ENEMY_SWARM)
	PoolManager.clear_pool(POOL_IDS.HAZARD_SPIKE)
	PoolManager.clear_pool(POOL_IDS.HIT_SPARK)
	PoolManager.clear_pool(POOL_IDS.DAMAGE_NUMBER)
	PoolManager.clear_pool(POOL_IDS.PICKUP_ORB)


func _on_title_start_requested() -> void:
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	call_deferred("_start_new_gameplay_run")


func _on_title_continue_requested() -> void:
	var envelope: Dictionary = SaveManager.load_envelope(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	var payload: Dictionary = envelope.get("payload", {}) as Dictionary
	if payload.is_empty():
		var load_error: String = SaveManager.last_error()
		SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
		push_warning("[FormalClientBoot] run save unavailable: %s" % load_error)
		call_deferred("_show_title_menu", "ui_run_save_unavailable")
		return
	call_deferred("_start_gameplay_run", payload)


func _on_title_gear_mod_requested() -> void:
	if _gear_mod_panel != null and is_instance_valid(_gear_mod_panel):
		return
	_gear_mod_panel = UIManager.push(GEAR_MOD_PANEL_SCENE, {"source": "formal_client_boot"}) as CanvasLayer
	if _gear_mod_panel == null:
		return
	_gear_mod_panel.connect("closed_requested", Callable(self, "_on_gear_mod_closed"), CONNECT_ONE_SHOT)


func _on_title_quit_requested() -> void:
	get_tree().quit()


func _on_title_settings_requested() -> void:
	if _settings_panel != null and is_instance_valid(_settings_panel):
		return
	_settings_panel = UIManager.push(SETTINGS_PANEL_SCENE, {"source": "title_menu"}) as CanvasLayer
	if _settings_panel == null:
		return
	_settings_panel.connect("closed_requested", Callable(self, "_on_settings_panel_closed"), CONNECT_ONE_SHOT)


func _on_gear_mod_closed() -> void:
	if UIManager.top() == _gear_mod_panel:
		UIManager.pop()
	elif _gear_mod_panel != null and is_instance_valid(_gear_mod_panel):
		_gear_mod_panel.queue_free()
	_gear_mod_panel = null


func _on_settings_panel_closed() -> void:
	if UIManager.top() == _settings_panel:
		UIManager.pop()
	_settings_panel = null


func _on_run_restart_requested() -> void:
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	call_deferred("_start_new_gameplay_run")


func _on_run_quit_to_title_requested() -> void:
	call_deferred("_show_title_menu")


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
