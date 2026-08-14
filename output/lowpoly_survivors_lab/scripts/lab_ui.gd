class_name LowpolyLabUI
extends CanvasLayer

signal start_requested
signal pause_requested
signal upgrade_selected(upgrade_id: String)
signal restart_requested
signal menu_requested
signal create_room_requested(display_name: String)
signal join_room_requested(display_name: String, room_code: String)
signal ready_requested(ready: bool)
signal lobby_start_requested
signal leave_room_requested
signal touch_input_changed(value: Vector2)

enum RunState {
	MENU,
	RUNNING,
	LEVEL_UP,
	PAUSED,
	VICTORY,
	DEFEAT,
}

const COLOR_INK := Color(0.035, 0.055, 0.085, 0.96)
const COLOR_PANEL := Color(0.075, 0.115, 0.16, 0.96)
const COLOR_EDGE := Color(0.26, 0.86, 0.78, 0.82)
const COLOR_ACCENT := Color(0.42, 1.0, 0.76, 1.0)
const COLOR_WARNING := Color(1.0, 0.56, 0.26, 1.0)
const COLOR_TEXT := Color(0.92, 0.97, 1.0, 1.0)
const COLOR_MUTED := Color(0.63, 0.72, 0.82, 1.0)

var _menu_layer: Control
var _hud_layer: Control
var _pause_layer: Control
var _upgrade_layer: Control
var _result_layer: Control
var _lobby_layer: Control
var _health_label: Label
var _health_bar: ProgressBar
var _experience_label: Label
var _experience_bar: ProgressBar
var _timer_label: Label
var _kill_label: Label
var _weapon_label: Label
var _boss_panel: PanelContainer
var _boss_label: Label
var _boss_bar: ProgressBar
var _upgrade_cards: HBoxContainer
var _result_title: Label
var _result_summary: Label
var _status_label: Label
var _controls_label: Label
var _start_button: Button
var _resume_button: Button
var _restart_button: Button
var _display_name_edit: LineEdit
var _room_code_edit: LineEdit
var _create_room_button: Button
var _join_room_button: Button
var _lobby_code_label: Label
var _lobby_players_label: Label
var _lobby_status_label: Label
var _ready_button: Button
var _lobby_start_button: Button
var _teammates_label: Label
var _network_label: Label
var _connection_diagnostic_label: Label
var _pause_title: Label
var _pause_hint: Label
var _touch_controls: Control
var _hud_top_margin: MarginContainer
var _boss_margin: MarginContainer
var _touch_joystick: LowpolyTouchJoystick
var _touch_menu_button: Button
var _local_menu_open: bool = false
var _online_mode: bool = false
var _local_ready: bool = false
var _current_state: int = RunState.MENU
var _touch_controls_override: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_menu()
	_build_hud()
	_build_pause()
	_build_upgrade()
	_build_result()
	_build_lobby()
	get_viewport().size_changed.connect(_apply_mobile_safe_area)
	_apply_mobile_safe_area.call_deferred()
	show_state(RunState.MENU)


func show_state(state: int) -> void:
	_current_state = state
	_menu_layer.visible = state == RunState.MENU and not _lobby_layer.visible
	_hud_layer.visible = state != RunState.MENU
	_pause_layer.visible = state == RunState.PAUSED or _local_menu_open
	_upgrade_layer.visible = state == RunState.LEVEL_UP
	_result_layer.visible = state == RunState.VICTORY or state == RunState.DEFEAT
	_update_touch_controls_visibility()
	if state == RunState.MENU:
		_boss_panel.visible = false
		_start_button.grab_focus.call_deferred()
	elif state == RunState.PAUSED:
		_resume_button.grab_focus.call_deferred()
	elif state == RunState.VICTORY or state == RunState.DEFEAT:
		_restart_button.grab_focus.call_deferred()


func set_health(current: float, maximum: float) -> void:
	_health_bar.max_value = maxf(maximum, 1.0)
	_health_bar.value = clampf(current, 0.0, _health_bar.max_value)
	_health_label.text = "生命  %d / %d" % [ceili(current), ceili(maximum)]


func set_experience(current: float, required: float, level: int) -> void:
	_experience_bar.max_value = maxf(required, 1.0)
	_experience_bar.value = clampf(current, 0.0, _experience_bar.max_value)
	_experience_label.text = "等级 %d   经验 %d / %d" % [level, floori(current), ceili(required)]


func set_time(_elapsed: float, remaining: float) -> void:
	_timer_label.text = _format_time(maxf(remaining, 0.0))


func set_kills(count: int) -> void:
	_kill_label.text = "击杀  %d" % count


func set_weapon_levels(snapshot: Dictionary) -> void:
	var labels: Array[String] = []
	var names := {
		"pulse_rifle": "脉冲步枪",
		"orbital_drone": "轨道无人机",
		"ion_pulse": "离子脉冲",
	}
	for weapon_id in ["pulse_rifle", "orbital_drone", "ion_pulse"]:
		var level := int(snapshot.get(weapon_id, 0))
		if level > 0:
			labels.append("%s Lv.%d" % [names[weapon_id], level])
	_weapon_label.text = "武器  " + ("   ·   ".join(labels) if not labels.is_empty() else "尚未装备")


func show_boss(_boss: Variant = null) -> void:
	_boss_panel.visible = true
	_boss_label.text = "最终目标 · 蚂蚁机甲"


func set_boss_health(current: float, maximum: float) -> void:
	_boss_panel.visible = maximum > 0.0 and current > 0.0
	_boss_bar.max_value = maxf(maximum, 1.0)
	_boss_bar.value = clampf(current, 0.0, _boss_bar.max_value)


func show_upgrade(options: Array) -> void:
	_clear_children(_upgrade_cards)
	var first_button: Button
	for raw_option in options:
		if not raw_option is Dictionary:
			continue
		var option: Dictionary = raw_option
		var card := Button.new()
		card.custom_minimum_size = Vector2(248.0, 210.0)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.add_theme_font_size_override("font_size", 19)
		card.add_theme_color_override("font_color", COLOR_TEXT)
		card.add_theme_color_override("font_hover_color", Color.WHITE)
		card.add_theme_stylebox_override("normal", _panel_style(COLOR_PANEL, COLOR_EDGE, 14))
		card.add_theme_stylebox_override("hover", _panel_style(Color(0.11, 0.22, 0.25, 0.98), COLOR_ACCENT, 14))
		card.add_theme_stylebox_override("focus", _panel_style(Color(0.10, 0.19, 0.23, 0.98), COLOR_WARNING, 14))
		var upgrade_id := String(option.get("id", ""))
		var title := String(option.get("name", option.get("title", upgrade_id)))
		var description := String(option.get("description", option.get("desc", "")))
		var next_level := int(option.get("next_level", option.get("level", 1)))
		card.text = "%s\n\n%s\n\n升至 Lv.%d" % [title, description, next_level]
		card.pressed.connect(_on_upgrade_button_pressed.bind(upgrade_id))
		_upgrade_cards.add_child(card)
		if first_button == null:
			first_button = card
	if first_button != null:
		first_button.grab_focus.call_deferred()


func show_result(victory: bool, summary: Dictionary) -> void:
	_result_title.text = "任务完成" if victory else "任务失败"
	_result_title.add_theme_color_override("font_color", COLOR_ACCENT if victory else COLOR_WARNING)
	var elapsed := float(summary.get("elapsed", summary.get("survival_time", 0.0)))
	var kills := int(summary.get("kills", summary.get("kill_count", 0)))
	var level := int(summary.get("level", 1))
	_result_summary.text = "存活时间  %s\n击杀数量  %d\n最终等级  %d" % [
		_format_time(elapsed),
		kills,
		level,
	]
	show_state(RunState.VICTORY if victory else RunState.DEFEAT)


func set_status_message(message: String, is_error: bool = false) -> void:
	_status_label.text = message
	_status_label.add_theme_color_override("font_color", COLOR_WARNING if is_error else COLOR_MUTED)


func show_lobby(snapshot: Dictionary, local_user_id: String) -> void:
	_online_mode = true
	_lobby_layer.visible = true
	_menu_layer.visible = false
	_hud_layer.visible = false
	_update_touch_controls_visibility()
	_lobby_code_label.text = "房间码  %s" % String(snapshot.get("room_code", "------"))
	var host_id := String(snapshot.get("host_user_id", ""))
	var rows: Array[String] = []
	var all_ready := true
	_local_ready = false
	for value: Variant in snapshot.get("members", []):
		if not value is Dictionary:
			continue
		var member: Dictionary = value
		var user_id := String(member.get("user_id", ""))
		var ready := bool(member.get("ready", false))
		var connected := bool(member.get("connected", true))
		all_ready = all_ready and ready and connected
		if user_id == local_user_id:
			_local_ready = ready
		rows.append("%s%s  ·  %s  ·  %s" % [
			"★ " if user_id == host_id else "",
			String(member.get("display_name", "幸存者")),
			String(member.get("platform", "unknown")),
			"已准备" if ready else "未准备",
		])
	_lobby_players_label.text = "\n".join(rows)
	_ready_button.text = "取消准备" if _local_ready else "准备"
	var local_is_host := host_id == local_user_id
	_lobby_start_button.visible = local_is_host
	_lobby_start_button.disabled = not all_ready or rows.is_empty()
	_lobby_status_label.text = "全员准备后由房主开始；开局后房间锁定。"


func hide_lobby() -> void:
	_lobby_layer.visible = false
	_update_touch_controls_visibility()


func set_online_status(message: String, is_error: bool = false) -> void:
	set_status_message(message, is_error)
	if _lobby_status_label != null:
		_lobby_status_label.text = message
		_lobby_status_label.add_theme_color_override("font_color", COLOR_WARNING if is_error else COLOR_MUTED)


func set_connection_diagnostic(message: String) -> void:
	if _connection_diagnostic_label != null:
		_connection_diagnostic_label.text = message


func show_local_menu(visible: bool, online: bool = false) -> void:
	_local_menu_open = visible
	_online_mode = online
	_pause_layer.visible = visible
	_update_touch_controls_visibility()
	if visible:
		_resume_button.grab_focus.call_deferred()
		if _pause_title != null:
			_pause_title.text = "本地菜单" if online else "实验已暂停"
		if _pause_hint != null:
			_pause_hint.text = (
				"联机战斗仍在继续，你的角色不会自动获得保护。"
				if online
				else "计时、敌人、弹丸与武器冷却均已冻结。"
			)


func is_local_menu_open() -> bool:
	return _local_menu_open


func set_teammates(roster: Array[Dictionary], local_slot: int) -> void:
	var rows: Array[String] = []
	for member: Dictionary in roster:
		var slot := int(member.get("slot", -1))
		if slot == local_slot:
			continue
		var status := "已移除" if bool(member.get("removed", false)) else "掉线" if not bool(member.get("connected", true)) else "阵亡" if float(member.get("health", 0.0)) <= 0.0 else "%d/%d" % [ceili(float(member.get("health", 0.0))), ceili(float(member.get("max_health", 1.0)))]
		rows.append("P%d  %s" % [slot + 1, status])
	_teammates_label.text = "队友  " + ("   ·   ".join(rows) if not rows.is_empty() else "单独行动")


func set_latency(milliseconds: int) -> void:
	_network_label.text = "延迟 %d ms" % milliseconds


func show_migration(active: bool, message: String) -> void:
	_network_label.text = message
	_network_label.add_theme_color_override("font_color", COLOR_WARNING if active else COLOR_ACCENT)


func _build_menu() -> void:
	_menu_layer = _new_full_control("MenuLayer")
	add_child(_menu_layer)
	_add_dimmer(_menu_layer, Color(0.01, 0.025, 0.05, 0.68))
	var center := _new_full_center(_menu_layer)
	var panel := _new_panel(Vector2(700.0, 760.0))
	center.add_child(panel)
	var box := _panel_vbox(panel, 16)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var kicker := _new_label("QUATERNIUS × POLY PIZZA · CC0 实验", 15, COLOR_ACCENT)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(kicker)
	var title := _new_label("LOWPOLY\n幸存者实验室", 48, COLOR_TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var subtitle := _new_label("在外星基地撑过十分钟，击毁最终蚂蚁机甲。", 20, COLOR_MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	box.add_child(_spacer(10.0))
	_controls_label = _new_label(
		"",
		18,
		COLOR_TEXT
	)
	_controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_controls_label.add_theme_constant_override("line_spacing", 7)
	box.add_child(_controls_label)
	_refresh_controls_hint()
	box.add_child(_spacer(8.0))
	_display_name_edit = LineEdit.new()
	_display_name_edit.placeholder_text = "昵称（最多 16 字）"
	_display_name_edit.text = "幸存者%03d" % randi_range(1, 999)
	_display_name_edit.max_length = 16
	_display_name_edit.custom_minimum_size = Vector2(360.0, 48.0)
	_display_name_edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_display_name_edit.add_theme_font_size_override("font_size", 18)
	box.add_child(_display_name_edit)
	_start_button = _new_button("单人游戏", Vector2(360.0, 56.0))
	_start_button.pressed.connect(_on_start_pressed)
	_start_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_start_button)
	_create_room_button = _new_button("创建房间", Vector2(360.0, 52.0))
	_create_room_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_create_room_button.pressed.connect(_on_create_room_pressed)
	box.add_child(_create_room_button)
	var join_row := HBoxContainer.new()
	join_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	join_row.add_theme_constant_override("separation", 10)
	_room_code_edit = LineEdit.new()
	_room_code_edit.placeholder_text = "六位房间码"
	_room_code_edit.max_length = 6
	_room_code_edit.custom_minimum_size = Vector2(210.0, 48.0)
	_room_code_edit.add_theme_font_size_override("font_size", 18)
	join_row.add_child(_room_code_edit)
	_join_room_button = _new_button("加入房间", Vector2(140.0, 48.0))
	_join_room_button.pressed.connect(_on_join_room_pressed)
	join_row.add_child(_join_room_button)
	box.add_child(join_row)
	_status_label = _new_label("离线单人可直接开始；联机需要本地 EOS 配置。", 15, COLOR_MUTED)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status_label)
	var credit := _new_label(
		"3D 模型：Quaternius · CC0\n经 Poly Pizza 获取；完整来源见 THIRD_PARTY_NOTICES.md",
		13,
		Color(0.50, 0.61, 0.72, 1.0)
	)
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(credit)


func _build_hud() -> void:
	_hud_layer = _new_full_control("HudLayer")
	_hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud_layer)
	_hud_top_margin = MarginContainer.new()
	_hud_top_margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hud_top_margin.offset_left = 18.0
	_hud_top_margin.offset_top = 16.0
	_hud_top_margin.offset_right = -18.0
	_hud_top_margin.offset_bottom = 128.0
	_hud_layer.add_child(_hud_top_margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	_hud_top_margin.add_child(rows)
	var top_panel := _new_panel(Vector2(0.0, 66.0))
	rows.add_child(top_panel)
	var top_row := _panel_hbox(top_panel, 18)
	_health_label = _new_label("生命  100 / 100", 17, COLOR_TEXT)
	top_row.add_child(_health_label)
	_health_bar = _new_bar(240.0, Color(0.95, 0.30, 0.30, 1.0))
	top_row.add_child(_health_bar)
	_experience_label = _new_label("等级 1   经验 0 / 10", 17, COLOR_TEXT)
	top_row.add_child(_experience_label)
	_experience_bar = _new_bar(240.0, Color(0.34, 0.84, 1.0, 1.0))
	top_row.add_child(_experience_bar)
	var flexible := Control.new()
	flexible.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(flexible)
	_kill_label = _new_label("击杀  0", 18, COLOR_TEXT)
	top_row.add_child(_kill_label)
	_timer_label = _new_label("10:00", 28, COLOR_ACCENT)
	timer_label_setup(_timer_label)
	top_row.add_child(_timer_label)
	var weapon_panel := _new_panel(Vector2(0.0, 42.0))
	rows.add_child(weapon_panel)
	_weapon_label = _new_label("武器  脉冲步枪 Lv.1", 16, COLOR_MUTED)
	var weapon_margin := MarginContainer.new()
	weapon_margin.add_theme_constant_override("margin_left", 16)
	weapon_margin.add_theme_constant_override("margin_right", 16)
	weapon_margin.add_theme_constant_override("margin_top", 8)
	weapon_margin.add_theme_constant_override("margin_bottom", 8)
	weapon_panel.add_child(weapon_margin)
	weapon_margin.add_child(_weapon_label)
	_teammates_label = _new_label("队友  单独行动", 15, COLOR_MUTED)
	_teammates_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_teammates_label.position = Vector2(28.0, 142.0)
	_hud_layer.add_child(_teammates_label)
	_network_label = _new_label("", 15, COLOR_ACCENT)
	_network_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_network_label.position = Vector2(-260.0, 142.0)
	_network_label.custom_minimum_size.x = 230.0
	_network_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud_layer.add_child(_network_label)
	_connection_diagnostic_label = _new_label("", 14, COLOR_MUTED)
	_connection_diagnostic_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_connection_diagnostic_label.position = Vector2(-610.0, 210.0)
	_connection_diagnostic_label.custom_minimum_size.x = 580.0
	_connection_diagnostic_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud_layer.add_child(_connection_diagnostic_label)

	_boss_margin = MarginContainer.new()
	_boss_margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_boss_margin.offset_left = 300.0
	_boss_margin.offset_top = 140.0
	_boss_margin.offset_right = -300.0
	_boss_margin.offset_bottom = 206.0
	_hud_layer.add_child(_boss_margin)
	_boss_panel = _new_panel(Vector2(0.0, 62.0))
	_boss_margin.add_child(_boss_panel)
	var boss_box := _panel_vbox(_boss_panel, 4)
	_boss_label = _new_label("最终目标 · 蚂蚁机甲", 16, COLOR_WARNING)
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_box.add_child(_boss_label)
	_boss_bar = _new_bar(0.0, COLOR_WARNING)
	_boss_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boss_box.add_child(_boss_bar)
	_boss_panel.visible = false
	_build_touch_controls()


func _build_pause() -> void:
	_pause_layer = _new_full_control("PauseLayer")
	add_child(_pause_layer)
	_add_dimmer(_pause_layer, Color(0.01, 0.02, 0.04, 0.72))
	var center := _new_full_center(_pause_layer)
	var panel := _new_panel(Vector2(440.0, 330.0))
	center.add_child(panel)
	var box := _panel_vbox(panel, 18)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_pause_title = _new_label("实验已暂停", 36, COLOR_TEXT)
	_pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_pause_title)
	_pause_hint = _new_label("计时、敌人、弹丸与武器冷却均已冻结。", 16, COLOR_MUTED)
	_pause_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_pause_hint)
	_resume_button = _new_button("继续实验", Vector2(260.0, 52.0))
	_resume_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_resume_button.pressed.connect(_on_resume_pressed)
	box.add_child(_resume_button)
	var menu := _new_button("返回标题", Vector2(260.0, 48.0))
	menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	menu.pressed.connect(_on_menu_pressed)
	box.add_child(menu)


func _build_upgrade() -> void:
	_upgrade_layer = _new_full_control("UpgradeLayer")
	add_child(_upgrade_layer)
	_add_dimmer(_upgrade_layer, Color(0.01, 0.025, 0.045, 0.76))
	var center := _new_full_center(_upgrade_layer)
	var panel := _new_panel(Vector2(940.0, 390.0))
	center.add_child(panel)
	var box := _panel_vbox(panel, 16)
	var title := _new_label("升级协议 · 选择一项", 32, COLOR_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var hint := _new_label("战斗已冻结。选择后立即恢复。", 15, COLOR_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	_upgrade_cards = HBoxContainer.new()
	_upgrade_cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_upgrade_cards.add_theme_constant_override("separation", 18)
	box.add_child(_upgrade_cards)


func _build_result() -> void:
	_result_layer = _new_full_control("ResultLayer")
	add_child(_result_layer)
	_add_dimmer(_result_layer, Color(0.01, 0.02, 0.04, 0.80))
	var center := _new_full_center(_result_layer)
	var panel := _new_panel(Vector2(500.0, 440.0))
	center.add_child(panel)
	var box := _panel_vbox(panel, 18)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_result_title = _new_label("任务完成", 42, COLOR_ACCENT)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_title)
	_result_summary = _new_label("存活时间  10:00\n击杀数量  0\n最终等级  1", 22, COLOR_TEXT)
	_result_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_summary.add_theme_constant_override("line_spacing", 10)
	box.add_child(_result_summary)
	_restart_button = _new_button("重新开始", Vector2(280.0, 54.0))
	_restart_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_restart_button.pressed.connect(_on_restart_pressed)
	box.add_child(_restart_button)
	var menu := _new_button("返回标题", Vector2(280.0, 48.0))
	menu.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	menu.pressed.connect(_on_menu_pressed)
	box.add_child(menu)


func _build_lobby() -> void:
	_lobby_layer = _new_full_control("LobbyLayer")
	add_child(_lobby_layer)
	_add_dimmer(_lobby_layer, Color(0.01, 0.025, 0.05, 0.78))
	var center := _new_full_center(_lobby_layer)
	var panel := _new_panel(Vector2(760.0, 650.0))
	center.add_child(panel)
	var box := _panel_vbox(panel, 18)
	var title := _new_label("合作大厅", 40, COLOR_TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_lobby_code_label = _new_label("房间码  ------", 34, COLOR_ACCENT)
	_lobby_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_lobby_code_label)
	var players_panel := _new_panel(Vector2(0.0, 250.0))
	players_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(players_panel)
	var players_margin := MarginContainer.new()
	players_margin.add_theme_constant_override("margin_left", 18)
	players_margin.add_theme_constant_override("margin_right", 18)
	players_margin.add_theme_constant_override("margin_top", 18)
	players_margin.add_theme_constant_override("margin_bottom", 18)
	players_panel.add_child(players_margin)
	_lobby_players_label = _new_label("等待玩家……", 22, COLOR_TEXT)
	_lobby_players_label.add_theme_constant_override("line_spacing", 14)
	players_margin.add_child(_lobby_players_label)
	_lobby_status_label = _new_label("正在连接 EOS……", 16, COLOR_MUTED)
	_lobby_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_lobby_status_label)
	var action_row := HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	action_row.add_theme_constant_override("separation", 14)
	box.add_child(action_row)
	_ready_button = _new_button("准备", Vector2(190.0, 54.0))
	_ready_button.pressed.connect(_on_ready_pressed)
	action_row.add_child(_ready_button)
	_lobby_start_button = _new_button("开始游戏", Vector2(190.0, 54.0))
	_lobby_start_button.pressed.connect(_on_lobby_start_pressed)
	action_row.add_child(_lobby_start_button)
	var leave_button := _new_button("离开房间", Vector2(190.0, 54.0))
	leave_button.pressed.connect(_on_leave_room_pressed)
	action_row.add_child(leave_button)
	_lobby_layer.visible = false


func _build_touch_controls() -> void:
	_touch_controls = Control.new()
	_touch_controls.name = "TouchControls"
	_touch_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(_touch_controls)
	_touch_controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_touch_joystick = LowpolyTouchJoystick.new()
	_touch_joystick.name = "MovementJoystick"
	_touch_controls.add_child(_touch_joystick)
	_touch_joystick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_touch_joystick.vector_changed.connect(func(value: Vector2) -> void: touch_input_changed.emit(value))
	_touch_menu_button = _new_button("菜单", Vector2(132.0, 58.0))
	_touch_menu_button.name = "LocalMenuButton"
	_touch_controls.add_child(_touch_menu_button)
	_touch_menu_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_touch_menu_button.pressed.connect(_on_resume_pressed)
	_layout_touch_controls(16.0, 12.0, 16.0, 12.0)
	_update_touch_controls_visibility()


func set_touch_controls_enabled_for_test(enabled: bool) -> void:
	_touch_controls_override = 1 if enabled else 0
	_refresh_controls_hint()
	_update_touch_controls_visibility()


func are_touch_controls_visible() -> bool:
	return _touch_controls != null and _touch_controls.is_visible_in_tree()


func _is_touch_device() -> bool:
	if _touch_controls_override >= 0:
		return _touch_controls_override == 1
	return (
		OS.get_name() == "Android"
		or OS.has_feature("mobile")
		or DisplayServer.is_touchscreen_available()
	)


func _refresh_controls_hint() -> void:
	if _controls_label == null:
		return
	_controls_label.text = (
		"左下虚拟摇杆：移动\n武器会自动锁定敌人并开火\n右上“菜单”：打开本地菜单"
		if _is_touch_device()
		else "WASD / 方向键 / 左摇杆：移动\n武器会自动锁定敌人并开火\nEsc / 手柄 Start：暂停"
	)


func _update_touch_controls_visibility() -> void:
	if _touch_controls == null:
		return
	var should_show := (
		_is_touch_device()
		and _current_state == RunState.RUNNING
		and not _local_menu_open
		and (_lobby_layer == null or not _lobby_layer.visible)
	)
	_touch_controls.visible = should_show
	if not should_show and _touch_joystick != null:
		_touch_joystick.reset_input()


func _layout_touch_controls(left: float, top: float, right: float, bottom: float) -> void:
	if _touch_joystick != null:
		var joystick_size := _touch_joystick.custom_minimum_size
		_touch_joystick.offset_left = 42.0 + left
		_touch_joystick.offset_top = -220.0 - bottom
		_touch_joystick.offset_right = _touch_joystick.offset_left + joystick_size.x
		_touch_joystick.offset_bottom = _touch_joystick.offset_top + joystick_size.y
	if _touch_menu_button != null:
		var menu_size := _touch_menu_button.custom_minimum_size
		_touch_menu_button.offset_left = -160.0 - right
		_touch_menu_button.offset_top = 210.0 + top
		_touch_menu_button.offset_right = _touch_menu_button.offset_left + menu_size.x
		_touch_menu_button.offset_bottom = _touch_menu_button.offset_top + menu_size.y


func _apply_mobile_safe_area() -> void:
	if not _is_touch_device():
		return
	var screen_size := Vector2(DisplayServer.screen_get_size())
	var safe := DisplayServer.get_display_safe_area()
	var viewport_size := get_viewport().get_visible_rect().size
	if screen_size.x <= 0.0 or screen_size.y <= 0.0 or safe.size.x <= 0 or safe.size.y <= 0:
		return
	var scale := Vector2(viewport_size.x / screen_size.x, viewport_size.y / screen_size.y)
	var left := maxf(16.0, float(safe.position.x) * scale.x)
	var top := maxf(12.0, float(safe.position.y) * scale.y)
	var right := maxf(16.0, (screen_size.x - float(safe.end.x)) * scale.x)
	var bottom := maxf(12.0, (screen_size.y - float(safe.end.y)) * scale.y)
	if _hud_top_margin != null:
		_hud_top_margin.offset_left = 18.0 + left
		_hud_top_margin.offset_top = 16.0 + top
		_hud_top_margin.offset_right = -18.0 - right
		_hud_top_margin.offset_bottom = 128.0 + top
	if _boss_margin != null:
		_boss_margin.offset_left = 300.0 + left
		_boss_margin.offset_top = 140.0 + top
		_boss_margin.offset_right = -300.0 - right
		_boss_margin.offset_bottom = 206.0 + top
	if _teammates_label != null:
		_teammates_label.position = Vector2(28.0 + left, 142.0 + top)
	if _network_label != null:
		_network_label.position = Vector2(-260.0 - right, 142.0 + top)
	if _connection_diagnostic_label != null:
		_connection_diagnostic_label.position = Vector2(-610.0 - right, 210.0 + top)
	_layout_touch_controls(left, top, right, bottom)


func _new_full_control(node_name: String) -> Control:
	var control := Control.new()
	control.name = node_name
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return control


func _new_full_center(parent: Control) -> CenterContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)
	return center


func _add_dimmer(parent: Control, color: Color) -> void:
	var dimmer := ColorRect.new()
	dimmer.color = color
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(dimmer)


func _new_panel(minimum_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = minimum_size
	panel.add_theme_stylebox_override("panel", _panel_style(COLOR_INK, COLOR_EDGE, 18))
	return panel


func _panel_vbox(panel: PanelContainer, separation: int) -> VBoxContainer:
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 24)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	margin.add_child(box)
	return box


func _panel_hbox(panel: PanelContainer, separation: int) -> HBoxContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	margin.add_child(box)
	return box


func _new_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _new_button(text: String, minimum_size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = minimum_size
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _panel_style(COLOR_PANEL, COLOR_EDGE, 11))
	button.add_theme_stylebox_override("hover", _panel_style(Color(0.11, 0.22, 0.25, 1.0), COLOR_ACCENT, 11))
	button.add_theme_stylebox_override("focus", _panel_style(Color(0.10, 0.19, 0.23, 1.0), COLOR_WARNING, 11))
	return button


func _new_bar(width: float, fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, 18.0)
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _panel_style(Color(0.025, 0.04, 0.06, 0.95), Color(0.2, 0.29, 0.36, 1.0), 6))
	bar.add_theme_stylebox_override("fill", _panel_style(fill_color, fill_color, 6))
	bar.max_value = 100.0
	bar.value = 100.0
	return bar


func _panel_style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.38)
	style.shadow_size = 8
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = height
	return spacer


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _format_time(seconds: float) -> String:
	var total := maxi(0, floori(seconds))
	return "%02d:%02d" % [total / 60, total % 60]


func timer_label_setup(label: Label) -> void:
	label.custom_minimum_size.x = 90.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _on_start_pressed() -> void:
	start_requested.emit()


func _on_create_room_pressed() -> void:
	create_room_requested.emit(_display_name_edit.text.strip_edges())


func _on_join_room_pressed() -> void:
	join_room_requested.emit(
		_display_name_edit.text.strip_edges(),
		_room_code_edit.text.strip_edges()
	)


func _on_ready_pressed() -> void:
	ready_requested.emit(not _local_ready)


func _on_lobby_start_pressed() -> void:
	lobby_start_requested.emit()


func _on_leave_room_pressed() -> void:
	leave_room_requested.emit()


func _on_resume_pressed() -> void:
	pause_requested.emit()


func _on_upgrade_button_pressed(upgrade_id: String) -> void:
	if upgrade_id != "":
		upgrade_selected.emit(upgrade_id)


func _on_restart_pressed() -> void:
	restart_requested.emit()


func _on_menu_pressed() -> void:
	menu_requested.emit()
