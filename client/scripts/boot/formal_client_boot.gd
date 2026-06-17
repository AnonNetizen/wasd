# Doc: docs/代码/formal_client_boot.md
# Authority: docs/正式项目工作规划.md F1, docs/游戏设计文档.md §9
class_name FormalClientBoot
extends Node


const BOOT_LOG_PREFIX: String = "[FormalClientBoot]"


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
	print("%s formal client boot scene loaded; contracts=%d rng_streams=%d data_schema_ok=%s player_stats=%d weapons=%d enemies=%d hazards=%d relics=%d credits=%d credit_sections=%d characters=%d locale_keys=%d growth_levels=%d growth_pools=%d game_modes=%d meta_upgrades=%d meta_unlocks=%d settings=%d analytics_events=%d analytics_enabled=%s replay_enabled=%s replay_recording=%s pool_ids=%d active_pools=%d save_kinds=%d save_slots=%d audio_prefixes=%d audio_streams=%d audio_buses_ready=%s locale=%s ui_stack=%d state=%s seed=%d" % [
		BOOT_LOG_PREFIX,
		contract_count,
		stream_count,
		str(data_schema_ok),
		int(schema_counts.get("player_stats", 0)),
		int(schema_counts.get("weapons", 0)),
		int(schema_counts.get("enemies", 0)),
		int(schema_counts.get("hazards", 0)),
		int(schema_counts.get("relics", 0)),
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
