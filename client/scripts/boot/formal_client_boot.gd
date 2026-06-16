# Doc: docs/代码/formal_client_boot.md
# Authority: docs/正式项目工作规划.md F1, docs/游戏设计文档.md §9
extends Node
class_name FormalClientBoot


const BOOT_LOG_PREFIX: String = "[FormalClientBoot]"


func _ready() -> void:
	var contract_count: int = DataLoader.contracts().size()
	var stream_count: int = DataLoader.contract_values("rng_streams").size()
	var settings_count: int = Settings.values().size()
	var analytics_event_count: int = Analytics.registered_events().size()
	var pool_id_count: int = PoolManager.registered_pool_ids().size()
	var save_kind_count: int = SaveManager.registered_save_kinds().size()
	var state_name: StringName = GameState.current()
	print("%s formal client boot scene loaded; contracts=%d rng_streams=%d settings=%d analytics_events=%d analytics_enabled=%s replay_enabled=%s replay_recording=%s pool_ids=%d active_pools=%d save_kinds=%d save_slots=%d locale=%s ui_stack=%d state=%s seed=%d" % [
		BOOT_LOG_PREFIX,
		contract_count,
		stream_count,
		settings_count,
		analytics_event_count,
		str(Analytics.is_enabled()),
		str(Replay.is_enabled()),
		str(Replay.is_recording()),
		pool_id_count,
		PoolManager.pool_count(),
		save_kind_count,
		SaveManager.list_slots().size(),
		Localization.current_locale(),
		UIManager.stack_size(),
		String(state_name),
		RNG.run_seed(),
	])
