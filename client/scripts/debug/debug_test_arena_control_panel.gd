# Doc: docs/代码/debug_test_arena.md
# Authority: docs/决策记录.md ADR #159
class_name DebugTestArenaControlPanel
extends CanvasLayer


var pauses_game: bool = true

var _controller: Node = null
var _count_spin: SpinBox = null
var _enemy_option: OptionButton = null
var _feedback_label: Label = null
var _free_skill_check: CheckButton = null
var _god_mode_check: CheckButton = null
var _spawn_type_option: OptionButton = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_enemy_option = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/SpawnGrid/EnemyOption"
	) as OptionButton
	_spawn_type_option = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/SpawnGrid/TypeOption"
	) as OptionButton
	_count_spin = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/SpawnGrid/CountSpin"
	) as SpinBox
	_feedback_label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/FeedbackLabel"
	) as Label
	_god_mode_check = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/CheatGrid/GodModeCheck"
	) as CheckButton
	_free_skill_check = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/CheatGrid/FreeSkillCheck"
	) as CheckButton
	if (
		_enemy_option == null
		or _spawn_type_option == null
		or _count_spin == null
		or _feedback_label == null
		or _god_mode_check == null
		or _free_skill_check == null
	):
		push_error("[DebugTestArenaControlPanel] missing required scene nodes")
		return
	_connect_buttons()
	_god_mode_check.toggled.connect(_on_god_mode_toggled)
	_free_skill_check.toggled.connect(_on_free_skill_toggled)
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	refresh_texts()


func _exit_tree() -> void:
	if Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.disconnect(_on_locale_changed)


func configure(controller: Node, enemies: Array[Dictionary]) -> void:
	_controller = controller
	_enemy_option.clear()
	for enemy: Dictionary in enemies:
		var enemy_id: String = String(enemy.get("id", ""))
		_enemy_option.add_item(
			tr(String(enemy.get("name_key", enemy_id)))
		)
		_enemy_option.set_item_metadata(
			_enemy_option.item_count - 1,
			enemy_id
		)
	_spawn_type_option.clear()
	_spawn_type_option.add_item(
		tr("ui_debug_test_arena_stationary_target")
	)
	_spawn_type_option.set_item_metadata(0, "stationary")
	_spawn_type_option.add_item(tr("ui_debug_test_arena_normal_ai"))
	_spawn_type_option.set_item_metadata(1, "ai")
	_god_mode_check.button_pressed = false
	_free_skill_check.button_pressed = false
	_feedback_label.text = tr("ui_debug_test_arena_panel_ready")


func request_close() -> void:
	if _controller != null and _controller.has_method("close_panel"):
		_controller.call("close_panel")


func grab_default_focus() -> void:
	var close_button: Button = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/BottomButtons/CloseButton"
	) as Button
	if close_button != null:
		UIManager.grab_focus_for_navigation(close_button)


func refresh_texts() -> void:
	_set_label_text("TitleLabel", "ui_debug_test_arena_panel_title")
	_set_grid_label_text("SpawnGrid", "EnemyLabel", "ui_debug_test_arena_enemy")
	_set_grid_label_text("SpawnGrid", "TypeLabel", "ui_debug_test_arena_target_type")
	_set_grid_label_text("SpawnGrid", "CountLabel", "ui_debug_test_arena_count")
	_set_button_text("SpawnButton", "ui_debug_test_arena_spawn")
	_set_button_text("ClearTargetsButton", "ui_debug_test_arena_clear_targets")
	_set_button_text("ClearAiButton", "ui_debug_test_arena_clear_ai")
	_set_button_text("ClearAllButton", "ui_debug_test_arena_clear_all")
	_set_button_text("KillAiButton", "ui_debug_test_arena_kill_ai")
	_set_button_text("ResetTargetsButton", "ui_debug_test_arena_reset_targets")
	_set_button_text("HealButton", "ui_debug_test_arena_heal")
	_set_button_text("RefreshButton", "ui_debug_test_arena_refresh")
	_set_button_text("TeleportButton", "ui_debug_test_arena_teleport")
	_set_button_text("ResetArenaButton", "ui_debug_test_arena_reset_arena")
	_set_button_text("ResetStatsButton", "ui_debug_test_arena_reset_stats")
	_set_bottom_button_text("SetupButton", "ui_debug_test_arena_return_setup")
	_set_bottom_button_text("TitleButton", "ui_debug_test_arena_return_title")
	_set_bottom_button_text("CloseButton", "ui_debug_test_arena_close_panel")
	if _god_mode_check != null:
		_god_mode_check.text = tr("ui_debug_test_arena_god_mode")
	if _free_skill_check != null:
		_free_skill_check.text = tr("ui_debug_test_arena_free_skills")
	if _spawn_type_option != null and _spawn_type_option.item_count == 2:
		_spawn_type_option.set_item_text(
			0,
			tr("ui_debug_test_arena_stationary_target")
		)
		_spawn_type_option.set_item_text(
			1,
			tr("ui_debug_test_arena_normal_ai")
		)


func debug_summary() -> Dictionary:
	return {
		"pauses_game": pauses_game,
		"enemy_options": _enemy_option.item_count,
		"count_min": int(_count_spin.min_value),
		"count_max": int(_count_spin.max_value),
		"god_mode": _god_mode_check.button_pressed,
		"free_skills": _free_skill_check.button_pressed,
	}


func _connect_buttons() -> void:
	_connect_button("SpawnButton", _on_spawn_pressed)
	_connect_button("ClearTargetsButton", _on_clear_targets_pressed)
	_connect_button("ClearAiButton", _on_clear_ai_pressed)
	_connect_button("ClearAllButton", _on_clear_all_pressed)
	_connect_button("KillAiButton", _on_kill_ai_pressed)
	_connect_button("ResetTargetsButton", _on_reset_targets_pressed)
	_connect_button("HealButton", _on_heal_pressed)
	_connect_button("RefreshButton", _on_refresh_pressed)
	_connect_button("TeleportButton", _on_teleport_pressed)
	_connect_button("ResetArenaButton", _on_reset_arena_pressed)
	_connect_button("ResetStatsButton", _on_reset_stats_pressed)
	_connect_bottom_button("SetupButton", _on_setup_pressed)
	_connect_bottom_button("TitleButton", _on_title_pressed)
	_connect_bottom_button("CloseButton", request_close)


func _connect_button(node_name: String, callback: Callable) -> void:
	var button: Button = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/ActionGrid/%s" % node_name
	) as Button
	if button != null:
		button.pressed.connect(callback)


func _connect_bottom_button(
	node_name: String,
	callback: Callable
) -> void:
	var button: Button = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/BottomButtons/%s" % node_name
	) as Button
	if button != null:
		button.pressed.connect(callback)


func _selected_metadata(option: OptionButton) -> String:
	if option.selected < 0:
		return ""
	return String(option.get_item_metadata(option.selected))


func _on_spawn_pressed() -> void:
	if _controller == null:
		return
	var result: Dictionary = _controller.call(
		"spawn_targets",
		_selected_metadata(_enemy_option),
		_selected_metadata(_spawn_type_option),
		int(_count_spin.value)
	) as Dictionary
	_feedback_label.text = tr(
		"ui_debug_test_arena_spawn_result"
	) % int(result.get("spawned", 0))


func _on_clear_targets_pressed() -> void:
	_show_count_result(
		"ui_debug_test_arena_clear_result",
		_controller.call("clear_targets", "stationary") as Dictionary
	)


func _on_clear_ai_pressed() -> void:
	_show_count_result(
		"ui_debug_test_arena_clear_result",
		_controller.call("clear_targets", "ai") as Dictionary
	)


func _on_clear_all_pressed() -> void:
	_show_count_result(
		"ui_debug_test_arena_clear_result",
		_controller.call("clear_targets", "") as Dictionary
	)


func _on_kill_ai_pressed() -> void:
	_show_count_result(
		"ui_debug_test_arena_kill_result",
		_controller.call("kill_ai") as Dictionary
	)


func _on_reset_targets_pressed() -> void:
	_show_count_result(
		"ui_debug_test_arena_reset_target_result",
		_controller.call("reset_stationary_targets") as Dictionary
	)


func _on_heal_pressed() -> void:
	_controller.call("heal_player")
	_feedback_label.text = tr("ui_debug_test_arena_healed")


func _on_god_mode_toggled(enabled: bool) -> void:
	if _controller != null:
		_controller.call("set_god_mode", enabled)


func _on_free_skill_toggled(enabled: bool) -> void:
	if _controller != null:
		_controller.call("set_free_skills", enabled)


func _on_refresh_pressed() -> void:
	_controller.call("refresh_skills")
	_feedback_label.text = tr("ui_debug_test_arena_refreshed")


func _on_teleport_pressed() -> void:
	_controller.call("teleport_to_spawn")
	_feedback_label.text = tr("ui_debug_test_arena_teleported")


func _on_reset_arena_pressed() -> void:
	_controller.call("reset_arena")
	_god_mode_check.set_pressed_no_signal(false)
	_free_skill_check.set_pressed_no_signal(false)
	_feedback_label.text = tr("ui_debug_test_arena_reset_done")


func _on_reset_stats_pressed() -> void:
	_controller.call("reset_damage_stats")
	_feedback_label.text = tr("ui_debug_test_arena_stats_reset")


func _on_setup_pressed() -> void:
	_controller.call("request_return_to_setup")


func _on_title_pressed() -> void:
	_controller.call("request_return_to_title")


func _show_count_result(key: String, result: Dictionary) -> void:
	_feedback_label.text = tr(key) % int(result.get("count", 0))


func _set_label_text(node_name: String, key: String) -> void:
	var label: Label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/%s" % node_name
	) as Label
	if label != null:
		label.text = tr(key)


func _set_grid_label_text(
	grid_name: String,
	node_name: String,
	key: String
) -> void:
	var label: Label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/%s/%s"
		% [grid_name, node_name]
	) as Label
	if label != null:
		label.text = tr(key)


func _set_button_text(node_name: String, key: String) -> void:
	var button: Button = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/ActionGrid/%s" % node_name
	) as Button
	if button != null:
		button.text = tr(key)


func _set_bottom_button_text(node_name: String, key: String) -> void:
	var button: Button = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/BottomButtons/%s" % node_name
	) as Button
	if button != null:
		button.text = tr(key)


func _on_locale_changed(_locale: String) -> void:
	refresh_texts()
