# Doc: docs/代码/debug_test_arena.md
# Authority: docs/决策记录.md ADR #159 / #160
class_name DebugTestArenaControlPanel
extends CanvasLayer


const SKILL_SLOTS := preload("res://scripts/contracts/skill_slots.gd")

var pauses_game: bool = true

var _controller: Node = null
var _count_spin: SpinBox = null
var _damage_spin: SpinBox = null
var _element_option: OptionButton = null
var _enemy_option: OptionButton = null
var _feedback_label: Label = null
var _free_skill_check: CheckButton = null
var _god_mode_check: CheckButton = null
var _observation_label: Label = null
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
	_element_option = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/SpawnGrid/ElementOption"
	) as OptionButton
	_damage_spin = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/SpawnGrid/DamageSpin"
	) as SpinBox
	_observation_label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/ObservationLabel"
	) as Label
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
		or _element_option == null
		or _damage_spin == null
		or _observation_label == null
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


func _process(_delta: float) -> void:
	_refresh_observation()


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
	_element_option.clear()
	var element_payload: Dictionary = DataLoader.load_json(
		DataLoader.ELEMENTS_PATH
	)
	for raw_element: Variant in element_payload.get("elements", []):
		if not raw_element is Dictionary:
			continue
		var element: Dictionary = raw_element as Dictionary
		var element_id: String = String(element.get("id", ""))
		_element_option.add_item(
			tr(String(element.get("name_key", element_id)))
		)
		_element_option.set_item_metadata(
			_element_option.item_count - 1,
			element_id
		)
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
	_set_grid_label_text("SpawnGrid", "ElementLabel", "ui_debug_test_arena_element")
	_set_grid_label_text("SpawnGrid", "DamageLabel", "ui_debug_test_arena_damage_amount")
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
	_set_button_text("CastSkill1Button", "ui_debug_test_arena_cast_skill_1")
	_set_button_text("CastSkill2Button", "ui_debug_test_arena_cast_skill_2")
	_set_button_text("CastSkill3Button", "ui_debug_test_arena_cast_skill_3")
	_set_button_text("CastSkill4Button", "ui_debug_test_arena_cast_skill_4")
	_set_button_text("ShieldButton", "ui_debug_test_arena_restore_shield")
	_set_button_text("OvershieldButton", "ui_debug_test_arena_add_overshield")
	_set_button_text("EnergyButton", "ui_debug_test_arena_restore_energy")
	_set_button_text("ElementDamageButton", "ui_debug_test_arena_inject_damage")
	_set_bottom_button_text("SetupButton", "ui_debug_test_arena_return_setup")
	_set_bottom_button_text("ExitButton", "ui_debug_test_arena_exit")
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
	_connect_button("CastSkill1Button", _on_cast_skill_1_pressed)
	_connect_button("CastSkill2Button", _on_cast_skill_2_pressed)
	_connect_button("CastSkill3Button", _on_cast_skill_3_pressed)
	_connect_button("CastSkill4Button", _on_cast_skill_4_pressed)
	_connect_button("ShieldButton", _on_restore_shield_pressed)
	_connect_button("OvershieldButton", _on_add_overshield_pressed)
	_connect_button("EnergyButton", _on_restore_energy_pressed)
	_connect_button("ElementDamageButton", _on_inject_damage_pressed)
	_connect_bottom_button("SetupButton", _on_setup_pressed)
	_connect_bottom_button("ExitButton", _on_exit_pressed)
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


func _on_cast_skill_1_pressed() -> void:
	_cast_skill_slot(SKILL_SLOTS.SKILL_1)


func _on_cast_skill_2_pressed() -> void:
	_cast_skill_slot(SKILL_SLOTS.SKILL_2)


func _on_cast_skill_3_pressed() -> void:
	_cast_skill_slot(SKILL_SLOTS.SKILL_3)


func _on_cast_skill_4_pressed() -> void:
	_cast_skill_slot(SKILL_SLOTS.SKILL_4)


func _cast_skill_slot(slot_id: String) -> void:
	var result: Dictionary = _controller.call(
		"cast_skill_slot",
		slot_id
	) as Dictionary
	_feedback_label.text = "%s: %s" % [
		slot_id,
		String(result.get("reason", "")),
	]


func _on_restore_shield_pressed() -> void:
	_controller.call("restore_player_shield")
	_feedback_label.text = tr("ui_debug_test_arena_restore_shield")


func _on_add_overshield_pressed() -> void:
	_controller.call("add_player_overshield", 100.0)
	_feedback_label.text = tr("ui_debug_test_arena_add_overshield")


func _on_restore_energy_pressed() -> void:
	_controller.call("restore_player_energy")
	_feedback_label.text = tr("ui_debug_test_arena_restore_energy")


func _on_inject_damage_pressed() -> void:
	var result: Dictionary = _controller.call(
		"inject_player_element_damage",
		_selected_metadata(_element_option),
		float(_damage_spin.value)
	) as Dictionary
	_feedback_label.text = "%s: %s" % [
		_selected_metadata(_element_option),
		String(result.get("reason", "")),
	]


func _refresh_observation() -> void:
	if (
		_controller == null
		or _observation_label == null
		or not _controller.has_method("combat_observation")
	):
		return
	var observation: Dictionary = _controller.call(
		"combat_observation"
	) as Dictionary
	_observation_label.text = (
		"%s %.0f  ·  %s %.0f  ·  %s %.0f\n%s: %s  ·  %s: %s"
		% [
			tr("ui_stats_shield"),
			float(observation.get("shield", 0.0)),
			tr("ui_stats_overshield"),
			float(observation.get("overshield", 0.0)),
			tr("ui_stats_energy"),
			float(observation.get("energy", 0.0)),
			tr("ui_debug_test_arena_player_status"),
			_status_summary_text(
				observation.get("player_statuses", [])
			),
			tr("ui_debug_test_arena_enemy_status"),
			_status_summary_text(
				observation.get("enemy_statuses", [])
			),
		]
	)


func _status_summary_text(raw_statuses: Variant) -> String:
	if not raw_statuses is Array or (raw_statuses as Array).is_empty():
		return "—"
	var parts: PackedStringArray = []
	for raw_status: Variant in raw_statuses as Array:
		if not raw_status is Dictionary:
			continue
		var status: Dictionary = raw_status as Dictionary
		parts.append("%s×%d" % [
			String(status.get("id", "")),
			int(status.get("stacks", 1)),
		])
	return ", ".join(parts)


func _on_setup_pressed() -> void:
	_controller.call("request_return_to_setup")


func _on_exit_pressed() -> void:
	_controller.call("request_exit")


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
