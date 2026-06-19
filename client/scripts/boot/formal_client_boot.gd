# Doc: docs/代码/formal_client_boot.md
# Authority: docs/正式项目工作规划.md F1, docs/游戏设计文档.md §9
class_name FormalClientBoot
extends Node


const BOOT_LOG_PREFIX: String = "[FormalClientBoot]"
const GAMEPLAY_RUN_LOOP := preload("res://scripts/gameplay/gameplay_run_loop.gd")
const RUNTIME_SMOKE_RUNNER := preload("res://tools/runtime_smoke.gd")
const TITLE_MENU := preload("res://scripts/ui/title_menu.gd")
const META_PROGRESSION_PANEL := preload("res://scripts/ui/meta_progression_panel.gd")
const META_SMOKE_RUNNER := preload("res://tools/meta_progression_smoke.gd")
const POOL_IDS := preload("res://scripts/contracts/pool_ids.gd")
const SAVE_KINDS := preload("res://scripts/contracts/save_kinds.gd")
const SAVE_SMOKE_RUNNER := preload("res://tools/save_manager_smoke.gd")

var _run_loop: Node = null
var _meta_progression_panel: CanvasLayer = null
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
	print("%s formal client boot scene loaded; contracts=%d rng_streams=%d data_schema_ok=%s player_stats=%d weapons=%d enemies=%d hazards=%d spawn_waves=%d relics=%d active_items=%d consumables=%d credits=%d credit_sections=%d characters=%d locale_keys=%d growth_levels=%d growth_pools=%d game_modes=%d meta_upgrades=%d meta_unlocks=%d settings=%d analytics_events=%d analytics_enabled=%s replay_enabled=%s replay_recording=%s pool_ids=%d active_pools=%d save_kinds=%d save_slots=%d audio_prefixes=%d audio_streams=%d audio_buses_ready=%s locale=%s ui_stack=%d state=%s seed=%d" % [
		BOOT_LOG_PREFIX,
		contract_count,
		stream_count,
		str(data_schema_ok),
		int(schema_counts.get("player_stats", 0)),
		int(schema_counts.get("weapons", 0)),
		int(schema_counts.get("enemies", 0)),
		int(schema_counts.get("hazards", 0)),
		int(schema_counts.get("spawn_waves", 0)),
		int(schema_counts.get("relics", 0)),
		int(schema_counts.get("active_items", 0)),
		int(schema_counts.get("consumables", 0)),
		int(schema_counts.get("credit_entries", 0)),
		int(schema_counts.get("credit_sections", 0)),
		int(schema_counts.get("characters", 0)),
		int(schema_counts.get("locale_keys", 0)),
		int(schema_counts.get("growth_levels", 0)),
		int(schema_counts.get("growth_pools", 0)),
		int(schema_counts.get("game_modes", 0)),
		int(schema_counts.get("meta_upgrade_tracks", 0)),
		int(schema_counts.get("meta_unlocks", 0)),
		settings_count,
		analytics_event_count,
		str(Analytics.is_enabled()),
		str(Replay.is_enabled()),
		str(Replay.is_recording()),
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

	if _is_runtime_smoke_enabled():
		if data_schema_ok:
			_start_gameplay_run()
		var smoke_runner: Node = RUNTIME_SMOKE_RUNNER.new()
		smoke_runner.name = "RuntimeSmoke"
		add_child(smoke_runner)
	elif _is_save_smoke_enabled():
		var save_smoke_runner: Node = SAVE_SMOKE_RUNNER.new()
		save_smoke_runner.name = "SaveManagerSmoke"
		add_child(save_smoke_runner)
	elif _is_meta_smoke_enabled():
		var meta_smoke_runner: Node = META_SMOKE_RUNNER.new()
		meta_smoke_runner.name = "MetaProgressionSmoke"
		add_child(meta_smoke_runner)
	elif data_schema_ok:
		_show_title_menu()


func _is_runtime_smoke_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--runtime-smoke") or OS.get_cmdline_user_args().has("--f4-smoke")


func _is_save_smoke_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--save-smoke")


func _is_meta_smoke_enabled() -> bool:
	return OS.get_cmdline_user_args().has("--meta-smoke")


func _show_title_menu(notice_key: String = "") -> void:
	_clear_gameplay_runtime()
	GameState.change_state(GameState.MAIN_MENU, {"source": "formal_client_boot"})
	UIManager.clear()

	var title_template: CanvasLayer = TITLE_MENU.new()
	title_template.name = "TitleMenu"
	var title_scene: PackedScene = _pack_ui_template(title_template)
	if title_scene == null:
		return
	_title_menu = UIManager.push(title_scene, {"source": "formal_client_boot"}) as CanvasLayer
	if _title_menu == null:
		return
	_title_menu.call("configure", SaveManager.has_save(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN), notice_key)
	_title_menu.connect("start_requested", Callable(self, "_on_title_start_requested"), CONNECT_ONE_SHOT)
	_title_menu.connect("continue_requested", Callable(self, "_on_title_continue_requested"), CONNECT_ONE_SHOT)
	_title_menu.connect("meta_progression_requested", Callable(self, "_on_title_meta_progression_requested"))
	_title_menu.connect("quit_requested", Callable(self, "_on_title_quit_requested"), CONNECT_ONE_SHOT)


func _start_gameplay_run(restore_snapshot: Dictionary = {}) -> void:
	UIManager.clear()
	GameState.change_state(GameState.LOADING, {"source": "formal_client_boot"})
	_clear_gameplay_runtime()

	_run_loop = GAMEPLAY_RUN_LOOP.new()
	_run_loop.name = "GameplayRunLoop"
	if not restore_snapshot.is_empty() and _run_loop.has_method("configure_restore_snapshot"):
		_run_loop.call("configure_restore_snapshot", restore_snapshot)
	_run_loop.connect("restart_requested", Callable(self, "_on_run_restart_requested"))
	_run_loop.connect("quit_to_title_requested", Callable(self, "_on_run_quit_to_title_requested"))
	add_child(_run_loop)


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
	PoolManager.clear_pool(POOL_IDS.PICKUP_ORB)


func _pack_ui_template(template: Node) -> PackedScene:
	var scene: PackedScene = PackedScene.new()
	var pack_result: Error = scene.pack(template)
	template.free()
	if pack_result != OK:
		push_error("[FormalClientBoot] failed to pack UI template: %d" % pack_result)
		return null
	return scene


func _on_title_start_requested() -> void:
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	call_deferred("_start_gameplay_run")


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


func _on_title_meta_progression_requested() -> void:
	if _meta_progression_panel != null and is_instance_valid(_meta_progression_panel):
		return
	var panel_template: CanvasLayer = META_PROGRESSION_PANEL.new()
	panel_template.name = "MetaProgressionPanel"
	var panel_scene: PackedScene = _pack_ui_template(panel_template)
	if panel_scene == null:
		return
	_meta_progression_panel = UIManager.push(panel_scene, {"source": "formal_client_boot"}) as CanvasLayer
	if _meta_progression_panel == null:
		return
	_meta_progression_panel.connect("closed_requested", Callable(self, "_on_meta_progression_closed"), CONNECT_ONE_SHOT)


func _on_title_quit_requested() -> void:
	get_tree().quit()


func _on_meta_progression_closed() -> void:
	if UIManager.top() == _meta_progression_panel:
		UIManager.pop()
	elif _meta_progression_panel != null and is_instance_valid(_meta_progression_panel):
		_meta_progression_panel.queue_free()
	_meta_progression_panel = null
	if _title_menu != null and is_instance_valid(_title_menu) and _title_menu.has_method("refresh_meta_summary"):
		_title_menu.call("refresh_meta_summary")


func _on_run_restart_requested() -> void:
	SaveManager.delete(SaveManager.DEFAULT_SLOT, SAVE_KINDS.RUN)
	call_deferred("_start_gameplay_run")


func _on_run_quit_to_title_requested() -> void:
	call_deferred("_show_title_menu")
