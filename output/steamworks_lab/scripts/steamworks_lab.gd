extends Node2D

const SESSION_SCRIPT := preload("res://scripts/network_session.gd")
const PLAYER_SCRIPT := preload("res://scripts/slime_player.gd")
const EXPRESSION_WHEEL_SCRIPT := preload("res://scripts/expression_wheel.gd")
const BULLET_SCRIPT := preload("res://scripts/slime_bullet.gd")
const BATTLE_DIRECTOR_SCRIPT := preload("res://scripts/battle_director.gd")
const BATTLE_HUD_SCRIPT := preload("res://scripts/battle_hud.gd")
const BUFF_PANEL_SCRIPT := preload("res://scripts/buff_panel.gd")
const UI_STYLE_SCRIPT := preload("res://scripts/ui_style.gd")

const VIEWPORT_SIZE := Vector2(540.0, 960.0)
const WORLD_RECT := Rect2(Vector2(20.0, 70.0), Vector2(500.0, 870.0))
const WORLD_SCROLL_SPEED: float = 120.0
const DEFAULT_PORT: int = 24567
const SCREEN_START: String = "start"
const SCREEN_MULTIPLAYER: String = "multiplayer"
const SCREEN_GAME: String = "game"

const ACTION_MOVE_UP := "move_up"
const ACTION_MOVE_DOWN := "move_down"
const ACTION_MOVE_LEFT := "move_left"
const ACTION_MOVE_RIGHT := "move_right"
const ACTION_EXPRESSION_WHEEL := "expression_wheel"
const ACTION_FIRE := "fire"
const ACTION_ACTIVE_ITEM := "active_item"
const EXPRESSION_DURATION: float = 2.2
const FIRE_COOLDOWN: float = 0.18
const FIRE_SPREAD_DEGREES: float = 2.5
const ACTIVE_EXPRESSIONS: Array[Dictionary] = [
	{"id": "happy_01", "text": "(^_^)", "label": "开心"},
	{"id": "wave_01", "text": "ヾ(^▽^*)", "label": "招呼"},
	{"id": "surprised_01", "text": "(⊙_⊙)", "label": "惊讶"},
	{"id": "love_01", "text": "(♡ω♡)", "label": "喜欢"},
	{"id": "angry_01", "text": "(｀へ´)", "label": "生气"},
	{"id": "panic_01", "text": "(°ロ°)", "label": "慌张"},
	{"id": "ready_01", "text": "(๑•̀ㅂ•́)و", "label": "准备"},
	{"id": "sleepy_01", "text": "(-_-) zzz", "label": "困了"},
]

var _session: Node
var _players: Dictionary = {}
var _peer_inputs: Dictionary = {}
var _bullets: Array[Node] = []
var _log_lines: Array[String] = []
var _screen: String = SCREEN_START
var _suppress_session_end_navigation: bool = false
var _fire_held: bool = false
var _fire_cooldown_remaining: float = 0.0
var _fire_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _world_scroll_offset: float = 0.0
var _ui_anim_time: float = 0.0
var _backdrop_stars: Array[Dictionary] = []
var _director: Node2D
var _battle_hud: Control
var _buff_panel: Control
var _ui_transition_tween: Tween
var _ui_motion_tweens: Dictionary = {}
var _local_buff_options: PackedInt32Array = PackedInt32Array()

var _ui_root: Control
var _start_page: Control
var _multiplayer_page: Control
var _game_page: Control
var _multiplayer_status_label: Label
var _log_label: Label
var _address_input: LineEdit
var _port_input: SpinBox
var _lobby_input: LineEdit
var _steam_status_label: Label
var _host_steam_button: Button
var _join_steam_button: Button
var _ready_room_label: Label
var _start_battle_button: Button
var _expression_wheel: Control


func _ready() -> void:
	_fire_rng.randomize()
	_generate_backdrop_stars()
	_ensure_input_actions()
	_create_session()
	_create_ui()
	_show_start_page()


func _physics_process(delta: float) -> void:
	_ui_anim_time += delta
	if _screen == SCREEN_GAME:
		_update_gameplay(delta)
		if _battle_active():
			_world_scroll_offset += WORLD_SCROLL_SPEED * delta
	_update_status()
	queue_redraw()


func player_nodes() -> Dictionary:
	return _players


func _battle_active() -> bool:
	if _director == null:
		return false
	return int(_director.get("phase")) == BATTLE_DIRECTOR_SCRIPT.Phase.BATTLE


func _start_battle() -> void:
	if _director == null:
		_director = BATTLE_DIRECTOR_SCRIPT.new() as Node2D
		_director.name = "BattleDirector"
		add_child(_director)
		_director.call("setup", self, _session, WORLD_RECT)
		_director.connect("phase_changed", Callable(self, "_on_director_phase_changed"))
		_director.connect("buff_options_ready", Callable(self, "_on_director_buff_options"))
		_director.connect("active_item_used", Callable(self, "_on_director_active_item_used"))
	_reset_battle()


func _end_battle() -> void:
	if _director != null:
		_director.call("reset_battle")


func _reset_battle() -> void:
	if _director != null:
		_director.call("reset_battle")
	_clear_bullets()
	_fire_cooldown_remaining = 0.0
	if _buff_panel != null:
		_buff_panel.call("close")
	var slot := 0
	for peer_id in _players.keys():
		var player := _players[peer_id] as Node
		if player == null or not is_instance_valid(player):
			continue
		player.call("revive_full")
		player.call("set_move_speed", BATTLE_DIRECTOR_SCRIPT.PLAYER_BASE_MOVE_SPEED)
		player.call("warp_to", _spawn_position_for_slot(slot))
		slot += 1


func set_player_bullets_frozen(frozen: bool) -> void:
	for bullet in _bullets:
		if is_instance_valid(bullet):
			bullet.call("set_battle_frozen", frozen)


func _on_director_phase_changed(new_phase: int, payload: Dictionary) -> void:
	if _buff_panel != null:
		if new_phase == BATTLE_DIRECTOR_SCRIPT.Phase.BATTLE:
			_buff_panel.call("close")
		elif new_phase == BATTLE_DIRECTOR_SCRIPT.Phase.CHOOSING_BUFF and not _buff_panel.visible:
			_buff_panel.call("show_waiting", "等待其他玩家选择…")
	if _session != null and bool(_session.call("is_host")):
		_session.call("broadcast_phase", new_phase, payload)


func _on_director_buff_options(peer_id: int, options: PackedInt32Array) -> void:
	var local_id := int(_session.call("local_peer_id"))
	if peer_id == local_id:
		_local_buff_options = options
		_open_buff_panel(options)
		return
	if bool(_session.call("is_host")):
		_session.call("send_buff_options", peer_id, options)


func _on_director_active_item_used(peer_id: int, item_id: int, origin: Vector2) -> void:
	if _session != null and bool(_session.call("is_host")):
		_session.call("broadcast_active_item_used", peer_id, item_id, origin)


func _on_phase_received(new_phase: int, payload: Dictionary) -> void:
	if _director == null or bool(_director.call("is_authority")):
		return
	_director.call("apply_phase", new_phase, payload)


func _on_buff_options_received(options: PackedInt32Array) -> void:
	if _director == null or bool(_director.call("is_authority")):
		return
	_local_buff_options = options
	_open_buff_panel(options)


func _on_buff_choice_received(peer_id: int, option_index: int) -> void:
	if _director == null or not bool(_session.call("is_host")):
		return
	_director.call("submit_buff_choice", peer_id, option_index)


func _on_enemy_volley_received(origin: Vector2, directions: PackedVector2Array, speed: float) -> void:
	if _director == null or bool(_director.call("is_authority")):
		return
	_director.call("spawn_volley_visual", origin, directions, speed)


func _on_battle_reset_received() -> void:
	if _director == null or bool(_director.call("is_authority")):
		return
	_reset_battle()


func _on_battle_launch_received() -> void:
	if _screen == SCREEN_GAME:
		return
	_start_battle()
	_show_game_page()
	_append_log("Host started the battle.")


func _open_buff_panel(options: PackedInt32Array) -> void:
	if _buff_panel == null or _director == null:
		return
	var defs: Array[Dictionary] = []
	for buff_id in options:
		defs.append(_director.call("buff_def", buff_id))
	var timeout := 0.0
	if String(_session.call("active_transport")) != "offline":
		timeout = BATTLE_DIRECTOR_SCRIPT.BUFF_CHOICE_TIMEOUT
	_buff_panel.call("open_with_options", defs, timeout)


func _on_buff_option_chosen(option_index: int) -> void:
	if _director == null:
		return
	var local_id := int(_session.call("local_peer_id"))
	if bool(_director.call("is_authority")):
		_director.call("submit_buff_choice", local_id, option_index)
		if not _battle_active() and _buff_panel != null:
			_buff_panel.call("show_waiting", "等待其他玩家选择…")
		return
	if option_index >= 0 and option_index < _local_buff_options.size():
		_director.call("apply_buff", local_id, _local_buff_options[option_index])
	_session.call("send_buff_choice_to_host", option_index)
	if _buff_panel != null:
		_buff_panel.call("show_waiting", "等待其他玩家选择…")


func _unhandled_input(event: InputEvent) -> void:
	if _screen != SCREEN_GAME:
		return
	var key_event := event as InputEventKey
	if event.is_action_pressed(ACTION_EXPRESSION_WHEEL) and (key_event == null or not key_event.echo):
		_open_expression_wheel()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_released(ACTION_EXPRESSION_WHEEL):
		_release_expression_wheel()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(ACTION_ACTIVE_ITEM) and (key_event == null or not key_event.echo):
		_try_active_item()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(ACTION_FIRE):
		_fire_held = true
		_try_fire()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_released(ACTION_FIRE):
		_fire_held = false
		get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEWPORT_SIZE), UI_STYLE_SCRIPT.BG_COLOR, true)
	if _screen == SCREEN_GAME:
		_draw_game_world()
	else:
		_draw_menu_background()


func _create_session() -> void:
	_session = SESSION_SCRIPT.new() as Node
	_session.name = "NetworkSession"
	add_child(_session)
	_session.connect("status_changed", Callable(self, "_append_log"))
	_session.connect("session_started", Callable(self, "_on_session_started"))
	_session.connect("session_ended", Callable(self, "_on_session_ended"))
	_session.connect("peer_joined", Callable(self, "_on_peer_joined"))
	_session.connect("peer_left", Callable(self, "_on_peer_left"))
	_session.connect("input_received", Callable(self, "_on_input_received"))
	_session.connect("snapshot_received", Callable(self, "_on_snapshot_received"))
	_session.connect("expression_received", Callable(self, "_on_expression_received"))
	_session.connect("shot_requested", Callable(self, "_on_shot_requested"))
	_session.connect("shot_received", Callable(self, "_on_shot_received"))
	_session.connect("phase_received", Callable(self, "_on_phase_received"))
	_session.connect("buff_options_received", Callable(self, "_on_buff_options_received"))
	_session.connect("buff_choice_received", Callable(self, "_on_buff_choice_received"))
	_session.connect("enemy_volley_received", Callable(self, "_on_enemy_volley_received"))
	_session.connect("battle_reset_received", Callable(self, "_on_battle_reset_received"))
	_session.connect("battle_launch_received", Callable(self, "_on_battle_launch_received"))
	_session.connect("active_item_requested", Callable(self, "_on_active_item_requested"))
	_session.connect("active_item_used_received", Callable(self, "_on_active_item_used_received"))


func _create_ui() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.name = "UiLayer"
	add_child(ui_layer)
	_ui_root = Control.new()
	_ui_root.name = "UiRoot"
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.theme = UI_STYLE_SCRIPT.build_theme()
	ui_layer.add_child(_ui_root)
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_create_start_page()
	_create_multiplayer_page()
	_create_game_page()


func _create_start_page() -> void:
	_start_page = _make_page("StartPage")
	var rows := _make_centered_panel(_start_page, "StartPanel", Vector2(456.0, 440.0), "hero")
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", 14)

	var kicker := _make_kicker_label("STEAM / LOCAL CO-OP LAB")
	rows.add_child(kicker)

	var title := _make_title_label("Steamworks Slime Lab")
	title.add_theme_font_size_override("font_size", 32)
	rows.add_child(title)

	var subtitle := _make_body_label("软体史莱姆 · 竖版弹幕 · Host 权威联机验证")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(subtitle)

	var button_stack := VBoxContainer.new()
	button_stack.add_theme_constant_override("separation", 10)
	button_stack.custom_minimum_size = Vector2(320.0, 0.0)
	rows.add_child(button_stack)

	var single_player_button := _make_button("开始单人游戏", Vector2(320.0, 52.0), true)
	single_player_button.pressed.connect(_on_start_single_player_pressed)
	button_stack.add_child(single_player_button)

	var multiplayer_button := _make_button("开始联机游戏", Vector2(320.0, 48.0))
	multiplayer_button.pressed.connect(_on_start_multiplayer_pressed)
	button_stack.add_child(multiplayer_button)

	var hint := _make_hint_label("WASD / 方向键移动    鼠标射击    Q 主动道具    T 表情轮")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(hint)


func _create_multiplayer_page() -> void:
	_multiplayer_page = _make_page("MultiplayerPage")
	var rows := _make_centered_panel(_multiplayer_page, "MultiplayerPanel", Vector2(500.0, 888.0), "hero")
	rows.add_theme_constant_override("separation", 10)

	var kicker := _make_kicker_label("READY ROOM")
	rows.add_child(kicker)

	var title := _make_title_label("Multiplayer")
	title.add_theme_font_size_override("font_size", 30)
	rows.add_child(title)

	var session_section := _make_section_box(rows, "Session")
	_multiplayer_status_label = Label.new()
	_multiplayer_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_multiplayer_status_label.add_theme_color_override("font_color", UI_STYLE_SCRIPT.TEXT_COLOR)
	session_section.add_child(_multiplayer_status_label)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(body)

	var local_section := _make_section_box(body, "Local")

	var host_local_button := _make_button("Host Local", Vector2(0.0, 42.0), true)
	host_local_button.pressed.connect(_on_host_local_pressed)
	local_section.add_child(host_local_button)

	var local_row := HBoxContainer.new()
	local_row.add_theme_constant_override("separation", 8)
	local_section.add_child(local_row)

	_address_input = LineEdit.new()
	_address_input.text = "127.0.0.1"
	_address_input.placeholder_text = "Address"
	_address_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI_STYLE_SCRIPT.apply_input(_address_input)
	local_row.add_child(_address_input)

	_port_input = SpinBox.new()
	_port_input.min_value = 1
	_port_input.max_value = 65535
	_port_input.value = DEFAULT_PORT
	_port_input.step = 1
	_port_input.custom_minimum_size = Vector2(112.0, 0.0)
	local_row.add_child(_port_input)

	var join_local_button := _make_button("Join Local")
	join_local_button.pressed.connect(_on_join_local_pressed)
	local_section.add_child(join_local_button)

	var steam_section := _make_section_box(body, "Steam")

	_steam_status_label = Label.new()
	_steam_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_steam_status_label.add_theme_color_override("font_color", UI_STYLE_SCRIPT.MUTED_TEXT_COLOR)
	steam_section.add_child(_steam_status_label)

	_host_steam_button = _make_button("Host Steam")
	_host_steam_button.pressed.connect(_on_host_steam_pressed)
	steam_section.add_child(_host_steam_button)

	_lobby_input = LineEdit.new()
	_lobby_input.placeholder_text = "Steam lobby id"
	UI_STYLE_SCRIPT.apply_input(_lobby_input)
	steam_section.add_child(_lobby_input)

	_join_steam_button = _make_button("Join Steam by ID")
	_join_steam_button.pressed.connect(_on_join_steam_pressed)
	steam_section.add_child(_join_steam_button)

	var ready_section := _make_section_box(body, "Ready Room")

	_ready_room_label = Label.new()
	_ready_room_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ready_room_label.add_theme_color_override("font_color", UI_STYLE_SCRIPT.TEXT_COLOR)
	ready_section.add_child(_ready_room_label)

	_start_battle_button = _make_button("Start Battle", Vector2(0.0, 46.0), true)
	_start_battle_button.pressed.connect(_on_ready_start_battle_pressed)
	ready_section.add_child(_start_battle_button)

	var session_buttons := HBoxContainer.new()
	session_buttons.add_theme_constant_override("separation", 8)
	ready_section.add_child(session_buttons)

	var leave_button := _make_button("Leave Session")
	leave_button.pressed.connect(_on_multiplayer_leave_pressed)
	session_buttons.add_child(leave_button)

	var back_button := _make_button("Back")
	back_button.pressed.connect(_on_multiplayer_back_pressed)
	session_buttons.add_child(back_button)

	var log_column := _make_section_box(body, "Status Log")
	log_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_column.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_log_label = Label.new()
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_label.add_theme_color_override("font_color", UI_STYLE_SCRIPT.MUTED_TEXT_COLOR)
	log_column.add_child(_log_label)


func _create_game_page() -> void:
	_game_page = _make_page("GamePage")

	_battle_hud = BATTLE_HUD_SCRIPT.new() as Control
	_battle_hud.name = "BattleHud"
	_battle_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_battle_hud.connect("restart_requested", Callable(self, "_on_restart_requested"))
	_battle_hud.connect("leave_requested", Callable(self, "_on_leave_game_pressed"))
	_game_page.add_child(_battle_hud)

	_buff_panel = BUFF_PANEL_SCRIPT.new() as Control
	_buff_panel.name = "BuffPanel"
	_buff_panel.connect("option_chosen", Callable(self, "_on_buff_option_chosen"))
	_game_page.add_child(_buff_panel)

	_create_expression_wheel()


func _make_page(page_name: String) -> Control:
	var page := Control.new()
	page.name = page_name
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.visible = false
	_ui_root.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return page


func _make_centered_panel(
	parent: Control,
	panel_name: String,
	minimum_size: Vector2,
	variant: String = "panel"
) -> VBoxContainer:
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.custom_minimum_size = minimum_size
	UI_STYLE_SCRIPT.apply_panel(panel, variant)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	margin.add_child(rows)
	return rows


func _make_section_box(parent: Control, title_text: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = "%sSection" % title_text.replace(" ", "")
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI_STYLE_SCRIPT.apply_panel(panel, "section")
	parent.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	margin.add_child(rows)

	var title := _make_kicker_label(title_text)
	title.add_theme_font_size_override("font_size", 12)
	rows.add_child(title)
	return rows


func _make_title_label(label_text: String) -> Label:
	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(0.93, 1.0, 0.78, 1.0))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.56))
	return label


func _make_kicker_label(label_text: String) -> Label:
	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", UI_STYLE_SCRIPT.AMBER_COLOR)
	return label


func _make_body_label(label_text: String) -> Label:
	var label := Label.new()
	label.text = label_text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", UI_STYLE_SCRIPT.TEXT_COLOR)
	return label


func _make_hint_label(label_text: String) -> Label:
	var label := _make_body_label(label_text)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UI_STYLE_SCRIPT.MUTED_TEXT_COLOR)
	return label


func _make_button(label: String, minimum_size: Vector2 = Vector2(0.0, 38.0), primary: bool = false) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = minimum_size
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UI_STYLE_SCRIPT.apply_button(button, primary)
	_wire_button_motion(button, primary)
	return button


func _wire_button_motion(button: Button, primary: bool) -> void:
	button.resized.connect(_refresh_button_pivot.bind(button))
	button.mouse_entered.connect(_on_ui_button_hovered.bind(button, primary))
	button.mouse_exited.connect(_on_ui_button_unhovered.bind(button))
	button.button_down.connect(_on_ui_button_pressed.bind(button))
	button.button_up.connect(_on_ui_button_released.bind(button, primary))


func _refresh_button_pivot(button: Button) -> void:
	if button == null or not is_instance_valid(button):
		return
	button.pivot_offset = button.size * 0.5


func _on_ui_button_hovered(button: Button, primary: bool) -> void:
	if button.disabled:
		return
	var target_color := Color(1.04, 1.08, 1.0, 1.0) if primary else Color.WHITE
	_tween_ui_control(button, Vector2(1.025, 1.025), target_color, 0.12, Tween.TRANS_QUAD, Tween.EASE_OUT)


func _on_ui_button_unhovered(button: Button) -> void:
	_tween_ui_control(button, Vector2.ONE, Color.WHITE, 0.16, Tween.TRANS_QUAD, Tween.EASE_OUT)


func _on_ui_button_pressed(button: Button) -> void:
	if button.disabled:
		return
	_tween_ui_control(button, Vector2(0.98, 0.98), Color(0.92, 1.0, 0.88, 1.0), 0.06, Tween.TRANS_QUAD, Tween.EASE_OUT)


func _on_ui_button_released(button: Button, primary: bool) -> void:
	if button.disabled:
		return
	var target_scale := Vector2(1.025, 1.025) if button.get_global_rect().has_point(get_global_mouse_position()) else Vector2.ONE
	var target_color := Color(1.04, 1.08, 1.0, 1.0) if primary and target_scale != Vector2.ONE else Color.WHITE
	_tween_ui_control(button, target_scale, target_color, 0.18, Tween.TRANS_BACK, Tween.EASE_OUT)


func _tween_ui_control(
	control: Control,
	target_scale: Vector2,
	target_modulate: Color,
	duration: float,
	trans_type: Tween.TransitionType,
	ease_type: Tween.EaseType
) -> void:
	if control == null or not is_instance_valid(control):
		return
	var key := control.get_instance_id()
	var previous_tween := _ui_motion_tweens.get(key) as Tween
	if previous_tween != null and previous_tween.is_valid():
		previous_tween.kill()
	var tween := create_tween()
	_ui_motion_tweens[key] = tween
	tween.set_parallel(true)
	tween.tween_property(control, "scale", target_scale, duration).set_trans(trans_type).set_ease(ease_type)
	tween.tween_property(control, "self_modulate", target_modulate, duration).set_trans(trans_type).set_ease(ease_type)


func _create_expression_wheel() -> void:
	_expression_wheel = EXPRESSION_WHEEL_SCRIPT.new() as Control
	_expression_wheel.name = "ExpressionWheel"
	_expression_wheel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_expression_wheel.call("set_options", ACTIVE_EXPRESSIONS)
	_game_page.add_child(_expression_wheel)


func _show_start_page() -> void:
	_set_screen(SCREEN_START)


func _show_multiplayer_page() -> void:
	_set_screen(SCREEN_MULTIPLAYER)


func _show_game_page() -> void:
	_set_screen(SCREEN_GAME)


func _set_screen(screen_name: String) -> void:
	var previous_page := _page_for_screen(_screen)
	var next_page := _page_for_screen(screen_name)
	_screen = screen_name
	_transition_to_page(previous_page, next_page)
	if screen_name != SCREEN_GAME and _expression_wheel != null:
		_expression_wheel.call("close")
	if screen_name != SCREEN_GAME:
		_fire_held = false
		_fire_cooldown_remaining = 0.0
	queue_redraw()


func _page_for_screen(screen_name: String) -> Control:
	match screen_name:
		SCREEN_START:
			return _start_page
		SCREEN_MULTIPLAYER:
			return _multiplayer_page
		SCREEN_GAME:
			return _game_page
		_:
			return null


func _transition_to_page(previous_page: Control, next_page: Control) -> void:
	if next_page == null:
		return
	if _ui_transition_tween != null and _ui_transition_tween.is_valid():
		_ui_transition_tween.kill()

	if previous_page == null or previous_page == next_page or not previous_page.visible:
		_show_page_immediate(next_page)
		return

	next_page.visible = true
	next_page.modulate.a = 0.0
	next_page.position = Vector2(0.0, 18.0)
	next_page.scale = Vector2(0.985, 0.985)

	_ui_transition_tween = create_tween()
	_ui_transition_tween.set_parallel(true)
	_ui_transition_tween.tween_property(previous_page, "modulate:a", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_ui_transition_tween.tween_property(previous_page, "position:y", -14.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_ui_transition_tween.tween_property(next_page, "modulate:a", 1.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_ui_transition_tween.tween_property(next_page, "position:y", 0.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_ui_transition_tween.tween_property(next_page, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_ui_transition_tween.chain().tween_callback(_finish_page_transition.bind(previous_page, next_page))


func _show_page_immediate(next_page: Control) -> void:
	for page in [_start_page, _multiplayer_page, _game_page]:
		var control := page as Control
		if control == null:
			continue
		control.visible = control == next_page
		control.modulate.a = 1.0 if control == next_page else 0.0
		control.position = Vector2.ZERO
		control.scale = Vector2.ONE


func _finish_page_transition(previous_page: Control, next_page: Control) -> void:
	if previous_page != null and previous_page != next_page:
		previous_page.visible = false
		previous_page.modulate.a = 0.0
		previous_page.position = Vector2.ZERO
		previous_page.scale = Vector2.ONE
	if next_page != null:
		next_page.visible = true
		next_page.modulate.a = 1.0
		next_page.position = Vector2.ZERO
		next_page.scale = Vector2.ONE


func _on_start_single_player_pressed() -> void:
	_begin_single_player()


func _on_start_multiplayer_pressed() -> void:
	_leave_session_without_navigation()
	_clear_players()
	_clear_bullets()
	_peer_inputs.clear()
	_show_multiplayer_page()
	_append_log("Multiplayer setup.")


func _begin_single_player() -> void:
	_leave_session_without_navigation()
	_clear_players()
	_clear_bullets()
	_peer_inputs.clear()
	var player: Node = _ensure_player(1, "Slime")
	player.call("warp_to", _spawn_position_for_slot(0))
	player.call("set_local_or_host_simulated", true)
	_start_battle()
	_show_game_page()
	_append_log("Single player started.")


func _on_host_local_pressed() -> void:
	_clear_players()
	_clear_bullets()
	_peer_inputs.clear()
	_session.call("host_local", int(_port_input.value))


func _on_join_local_pressed() -> void:
	_clear_players()
	_clear_bullets()
	_peer_inputs.clear()
	_session.call("join_local", _address_input.text, int(_port_input.value))


func _on_host_steam_pressed() -> void:
	_clear_players()
	_clear_bullets()
	_peer_inputs.clear()
	_session.call("host_steam")


func _on_join_steam_pressed() -> void:
	_clear_players()
	_clear_bullets()
	_peer_inputs.clear()
	_session.call("join_steam_lobby", _lobby_input.text)


func _on_ready_start_battle_pressed() -> void:
	if _session == null or not bool(_session.call("is_host")):
		return
	if _players.size() < 2:
		_append_log("Need at least 2 players in the ready room.")
		return
	_start_battle()
	_show_game_page()
	_session.call("broadcast_battle_launch")
	_append_log("Battle launched from ready room.")


func _on_multiplayer_leave_pressed() -> void:
	_session.call("leave_session")
	_end_battle()
	_clear_players()
	_clear_bullets()
	_peer_inputs.clear()
	_show_multiplayer_page()
	_append_log("Multiplayer session left.")


func _on_multiplayer_back_pressed() -> void:
	_leave_session_without_navigation()
	_clear_players()
	_clear_bullets()
	_peer_inputs.clear()
	_show_start_page()


func _on_leave_game_pressed() -> void:
	_leave_session_without_navigation()
	_end_battle()
	_clear_players()
	_clear_bullets()
	_peer_inputs.clear()
	_show_start_page()
	_append_log("Returned to start page.")


func _on_restart_requested() -> void:
	if _director == null or not bool(_director.call("is_authority")):
		return
	_reset_battle()
	if bool(_session.call("is_host")):
		_session.call("broadcast_battle_reset")
	_append_log("Battle restarted.")


func _leave_session_without_navigation() -> void:
	if _session == null:
		return
	_suppress_session_end_navigation = true
	_session.call("leave_session")
	_suppress_session_end_navigation = false


func _on_session_started(host: bool, transport: String, lobby_id: String) -> void:
	if host:
		var host_player: Node = _ensure_player(1, "Host")
		host_player.call("warp_to", _spawn_position_for_slot(0))
		host_player.call("set_local_or_host_simulated", true)
		_append_log("Ready room created. Wait for players, then start.")
	else:
		_append_log("Joined ready room. Waiting for host start.")
	if lobby_id != "" and _lobby_input != null:
		_lobby_input.text = lobby_id
	_show_multiplayer_page()
	_append_log("Session ready: %s %s" % [transport, "host" if host else "client"])


func _on_session_ended() -> void:
	if not _suppress_session_end_navigation and _screen == SCREEN_GAME:
		_end_battle()
		_clear_players()
		_clear_bullets()
		_peer_inputs.clear()
		_show_multiplayer_page()
	_update_status()


func _on_peer_joined(peer_id: int) -> void:
	if not bool(_session.call("is_host")):
		return
	var player: Node = _ensure_player(peer_id, "Peer %d" % peer_id)
	player.call("set_local_or_host_simulated", true)
	_peer_inputs[peer_id] = Vector2.ZERO
	if _screen == SCREEN_GAME:
		_session.call("send_battle_launch", peer_id)


func _on_peer_left(peer_id: int) -> void:
	_remove_player(peer_id)
	_peer_inputs.erase(peer_id)
	if _director != null:
		_director.call("notify_peer_left", peer_id)


func _on_input_received(peer_id: int, input_vector: Vector2) -> void:
	if not bool(_session.call("is_host")):
		return
	_peer_inputs[peer_id] = input_vector


func _on_snapshot_received(snapshot: Dictionary) -> void:
	if bool(_session.call("is_host")):
		return
	var players: Variant = snapshot.get("players", [])
	if not players is Array:
		return
	var seen: Dictionary = {}
	for raw_player in players:
		if not raw_player is Dictionary:
			continue
		var player_data: Dictionary = raw_player
		var peer_id := int(player_data.get("peer_id", 0))
		if peer_id <= 0:
			continue
		seen[peer_id] = true
		var player: Node = _ensure_player(peer_id, String(player_data.get("name", "Peer %d" % peer_id)))
		player.call("set_local_or_host_simulated", false)
		player.call("set_authoritative_state", _dict_to_vector(player_data.get("position", {})), _dict_to_vector(player_data.get("velocity", {})))
		player.call(
			"apply_snapshot_extras",
			int(player_data.get("hp", 3)),
			bool(player_data.get("alive", true)),
			float(player_data.get("inv", 0.0))
		)

	for peer_id in _players.keys():
		if not seen.has(peer_id):
			_remove_player(peer_id)

	if _director != null:
		_director.call("apply_snapshot_battle", snapshot)


func _on_expression_received(peer_id: int, expression_id: String) -> void:
	_show_player_expression(peer_id, expression_id)


func _on_shot_requested(peer_id: int, direction: Vector2) -> void:
	if not bool(_session.call("is_host")):
		return
	_fire_player_shots(peer_id, direction, true)


func _on_shot_received(peer_id: int, origin: Vector2, direction: Vector2, speed: float) -> void:
	_play_fire_surface_feedback(peer_id, direction)
	_spawn_bullet(peer_id, origin, direction, speed)


func _on_active_item_requested(peer_id: int) -> void:
	if not bool(_session.call("is_host")):
		return
	_use_active_item_authority(peer_id)


func _on_active_item_used_received(peer_id: int, item_id: int, origin: Vector2) -> void:
	if _director == null or bool(_director.call("is_authority")):
		return
	_director.call("play_active_item_feedback", peer_id, item_id, origin)


func _fire_player_shots(peer_id: int, aim_direction: Vector2, broadcast: bool) -> void:
	if not _players.has(peer_id) or not _battle_active():
		return
	var player := _players[peer_id] as Node
	if player == null or not bool(player.get("alive")):
		return
	var bullet_count := 1
	var bullet_speed: float = BULLET_SCRIPT.DEFAULT_SPEED
	if _director != null:
		bullet_count = int(_director.call("player_bullet_count", peer_id))
		bullet_speed *= float(_director.call("player_bullet_speed_scale", peer_id))
	var half := float(bullet_count - 1) * 0.5
	for index in range(bullet_count):
		var fan_offset := deg_to_rad(8.0) * (float(index) - half)
		var shot_direction := _jitter_fire_direction(aim_direction.rotated(fan_offset))
		var origin := _player_fire_surface(peer_id, shot_direction)
		_spawn_bullet(peer_id, origin, shot_direction, bullet_speed)
		if broadcast:
			_session.call("broadcast_shot", peer_id, origin, shot_direction, bullet_speed)


func _update_gameplay(delta: float) -> void:
	_fire_cooldown_remaining = maxf(0.0, _fire_cooldown_remaining - delta)
	_prune_bullets()
	var input_vector := _local_input_vector()
	if bool(_session.call("is_host")):
		_peer_inputs[1] = input_vector
		if _battle_active():
			_apply_host_inputs()
		else:
			_freeze_player_inputs()
		if _director != null:
			_director.call("host_tick", delta)
		_session.call("broadcast_snapshot", _build_snapshot())
	elif String(_session.call("active_transport")) != "offline":
		_session.call("send_input_to_host", input_vector)
		if _director != null:
			_director.call("client_tick", delta)
	else:
		var offline_player: Node = _ensure_player(1, "Slime")
		offline_player.call("set_input_vector", input_vector if _battle_active() else Vector2.ZERO)
		if _director != null:
			_director.call("host_tick", delta)
	if _fire_held:
		_try_fire()
	_refresh_battle_hud()


func _freeze_player_inputs() -> void:
	for peer_id in _players.keys():
		var player := _players[peer_id] as Node
		if player != null and is_instance_valid(player):
			player.call("set_input_vector", Vector2.ZERO)


func _refresh_battle_hud() -> void:
	if _battle_hud == null or _director == null:
		return
	var state: Dictionary = _director.call("battle_state")
	var local_id := int(_session.call("local_peer_id"))
	var player := _players.get(local_id) as Node
	if player != null and is_instance_valid(player):
		state["hp"] = int(player.get("hp"))
		state["alive"] = bool(player.get("alive"))
	else:
		state["hp"] = 0
		state["alive"] = true
	state["max_hp"] = PLAYER_SCRIPT.MAX_HP
	state["authority"] = bool(_director.call("is_authority"))
	state["game_over"] = int(state.get("phase", 0)) == BATTLE_DIRECTOR_SCRIPT.Phase.GAME_OVER
	state["active_item"] = _director.call("active_item_for_peer", local_id)
	if not state.has("boss"):
		state["boss"] = {}
	_battle_hud.call("refresh", state)
	if _buff_panel != null and bool(_buff_panel.call("is_waiting")):
		var pending := int(_director.call("pending_choice_count"))
		if pending > 0:
			_buff_panel.call("update_waiting", "等待其他玩家选择… (%d)" % pending)


func _apply_host_inputs() -> void:
	for peer_id in _players.keys():
		var player := _players[peer_id] as Node
		if player == null:
			continue
		var input_vector: Vector2 = _peer_inputs.get(peer_id, Vector2.ZERO)
		player.call("set_input_vector", input_vector)


func _build_snapshot() -> Dictionary:
	var player_states: Array[Dictionary] = []
	for peer_id in _players.keys():
		var player := _players[peer_id] as Node
		if player == null:
			continue
		player_states.append(player.call("snapshot_state"))
	var snapshot := {
		"players": player_states,
		"transport": String(_session.call("active_transport")),
		"lobby_id": String(_session.call("lobby_id")),
	}
	if _director != null:
		snapshot.merge(_director.call("battle_snapshot"))
	return snapshot


func _ensure_player(peer_id: int, display_name: String) -> Node:
	if _players.has(peer_id):
		return _players[peer_id]
	var player := PLAYER_SCRIPT.new() as Node
	player.name = "SlimePlayer%d" % peer_id
	player.call("set_player_info", peer_id, display_name, peer_id)
	add_child(player)
	player.call("warp_to", _spawn_position_for_slot(_players.size()))
	player.call("set_movement_bounds", WORLD_RECT)
	_players[peer_id] = player
	return player


func _try_fire() -> void:
	if _fire_cooldown_remaining > 0.0 or _screen != SCREEN_GAME:
		return
	if _expression_wheel != null and bool(_expression_wheel.call("is_open")):
		return
	if not _battle_active():
		return
	var local_id := int(_session.call("local_peer_id"))
	if not _players.has(local_id):
		return
	var local_player := _players[local_id] as Node
	if local_player == null or not bool(local_player.get("alive")):
		return
	var direction := _local_aim_direction(local_id)
	_fire_cooldown_remaining = _local_fire_cooldown(local_id)
	if _session == null or String(_session.call("active_transport")) == "offline":
		_fire_player_shots(local_id, direction, false)
		return
	_session.call("send_shot_to_host", direction)


func _try_active_item() -> void:
	if _screen != SCREEN_GAME:
		return
	if _expression_wheel != null and bool(_expression_wheel.call("is_open")):
		return
	if not _battle_active():
		return
	var local_id := int(_session.call("local_peer_id"))
	if not _players.has(local_id):
		return
	var local_player := _players[local_id] as Node
	if local_player == null or not bool(local_player.get("alive")):
		return
	if _session == null or String(_session.call("active_transport")) == "offline":
		_use_active_item_authority(local_id)
		return
	_session.call("send_active_item_to_host")


func _use_active_item_authority(peer_id: int) -> void:
	if _director == null or not bool(_director.call("is_authority")):
		return
	var result: Dictionary = _director.call("use_active_item", peer_id)
	if result.is_empty():
		return
	var item_id := int(result.get("item_id", -1))
	var item_info: Dictionary = _director.call("active_item_def", item_id)
	var item_name := String(item_info.get("name", "主动道具"))
	_append_log("Peer %d used %s." % [peer_id, item_name])


func _local_fire_cooldown(peer_id: int) -> float:
	if _director == null:
		return FIRE_COOLDOWN
	return float(_director.call("player_fire_cooldown", peer_id))


func _local_aim_direction(peer_id: int) -> Vector2:
	var center := _player_body_center(peer_id)
	var direction := get_global_mouse_position() - center
	if direction.length_squared() <= 0.0001:
		return Vector2.UP
	return direction.normalized()


func _jitter_fire_direction(direction: Vector2) -> Vector2:
	var normalized := direction.normalized()
	if normalized.length_squared() <= 0.0001:
		normalized = Vector2.RIGHT
	var spread_radians := deg_to_rad(FIRE_SPREAD_DEGREES)
	return normalized.rotated(_fire_rng.randf_range(-spread_radians, spread_radians)).normalized()


func _player_body_center(peer_id: int) -> Vector2:
	if not _players.has(peer_id):
		return WORLD_RECT.get_center()
	var player := _players[peer_id] as Node
	if player == null:
		return WORLD_RECT.get_center()
	var body_center: Vector2 = player.call("body_center")
	return body_center


func _player_fire_surface(peer_id: int, direction: Vector2) -> Vector2:
	if not _players.has(peer_id):
		return WORLD_RECT.get_center()
	var player := _players[peer_id] as Node
	if player == null:
		return WORLD_RECT.get_center()
	var surface_point: Vector2 = player.call("emit_fire_surface", direction)
	return surface_point


func _play_fire_surface_feedback(peer_id: int, direction: Vector2) -> void:
	if not _players.has(peer_id):
		return
	var player := _players[peer_id] as Node
	if player != null:
		player.call("play_fire_surface_feedback", direction)


func _spawn_bullet(peer_id: int, origin: Vector2, direction: Vector2, speed: float = 560.0) -> void:
	var bullet := BULLET_SCRIPT.new() as Node2D
	bullet.name = "SlimeBullet%d" % (_bullets.size() + 1)
	var palette := _bullet_palette_for_peer(peer_id)
	bullet.call("configure", origin, direction, palette["fill"], palette["edge"], speed)
	bullet.set("owner_peer_id", peer_id)
	add_child(bullet)
	_bullets.append(bullet)
	if _director != null:
		if bool(_director.call("is_authority")):
			bullet.set("damage", int(_director.call("player_bullet_damage", peer_id)))
			bullet.set("pierce_remaining", int(_director.call("player_pierce_count", peer_id)))
		_director.call("register_player_bullet", bullet)


func _bullet_palette_for_peer(peer_id: int) -> Dictionary:
	if not _players.has(peer_id):
		return {
			"fill": Color(0.82, 1.0, 0.70, 0.96),
			"edge": Color(0.98, 1.0, 0.84, 0.98),
		}
	var player := _players[peer_id] as Node
	if player == null:
		return {
			"fill": Color(0.82, 1.0, 0.70, 0.96),
			"edge": Color(0.98, 1.0, 0.84, 0.98),
		}
	var palette: Dictionary = player.call("bullet_palette")
	return palette


func _open_expression_wheel() -> void:
	if _expression_wheel == null:
		return
	_expression_wheel.call("open_at", VIEWPORT_SIZE * 0.5)


func _release_expression_wheel() -> void:
	if _expression_wheel == null or not bool(_expression_wheel.call("is_open")):
		return
	var expression_id := String(_expression_wheel.call("selected_expression_id"))
	_expression_wheel.call("close")
	if expression_id != "":
		_send_expression(expression_id)


func _send_expression(expression_id: String) -> void:
	if not _is_expression_id_allowed(expression_id):
		return
	if _session == null or String(_session.call("active_transport")) == "offline":
		_show_player_expression(1, expression_id)
		return
	_session.call("send_expression_to_host", expression_id)


func _show_player_expression(peer_id: int, expression_id: String) -> void:
	var expression_text := _expression_text(expression_id)
	if expression_text == "" or not _players.has(peer_id):
		return
	var player := _players[peer_id] as Node
	if player != null:
		player.call("show_expression", expression_text, EXPRESSION_DURATION)


func _expression_text(expression_id: String) -> String:
	for expression in ACTIVE_EXPRESSIONS:
		if String(expression.get("id", "")) == expression_id:
			return String(expression.get("text", ""))
	return ""


func _is_expression_id_allowed(expression_id: String) -> bool:
	return _expression_text(expression_id) != ""


func _remove_player(peer_id: int) -> void:
	if not _players.has(peer_id):
		return
	var player := _players[peer_id] as Node
	_players.erase(peer_id)
	if is_instance_valid(player):
		player.queue_free()


func _clear_players() -> void:
	for peer_id in _players.keys():
		var player := _players[peer_id] as Node
		if is_instance_valid(player):
			player.queue_free()
	_players.clear()


func _clear_bullets() -> void:
	for bullet in _bullets:
		if is_instance_valid(bullet):
			bullet.queue_free()
	_bullets.clear()


func _prune_bullets() -> void:
	var live_bullets: Array[Node] = []
	for bullet in _bullets:
		if is_instance_valid(bullet) and not bullet.is_queued_for_deletion():
			live_bullets.append(bullet)
	_bullets = live_bullets


func _local_input_vector() -> Vector2:
	var input_vector := Input.get_vector(ACTION_MOVE_LEFT, ACTION_MOVE_RIGHT, ACTION_MOVE_UP, ACTION_MOVE_DOWN)
	return input_vector.limit_length(1.0)


func _spawn_position_for_slot(slot_index: int) -> Vector2:
	var index: int = maxi(0, slot_index)
	var steps := ceilf(float(index) * 0.5)
	var side := -1.0 if index % 2 == 1 else 1.0
	var x: float = clampf(
		WORLD_RECT.get_center().x + steps * 62.0 * side,
		WORLD_RECT.position.x + 44.0,
		WORLD_RECT.end.x - 44.0
	)
	return Vector2(x, WORLD_RECT.end.y - 90.0)


func _dict_to_vector(data: Variant) -> Vector2:
	if not data is Dictionary:
		return Vector2.ZERO
	var dictionary: Dictionary = data
	return Vector2(float(dictionary.get("x", 0.0)), float(dictionary.get("y", 0.0)))


func _draw_menu_background() -> void:
	for band_index in range(9):
		var y := float(band_index) * VIEWPORT_SIZE.y / 9.0
		var alpha := 0.05 + float(band_index % 2) * 0.025
		draw_rect(Rect2(Vector2(0.0, y), Vector2(VIEWPORT_SIZE.x, VIEWPORT_SIZE.y / 9.0)), Color(0.06, 0.11, 0.09, alpha), true)

	var scan_y := fposmod(_ui_anim_time * 52.0, VIEWPORT_SIZE.y + 120.0) - 60.0
	draw_rect(Rect2(Vector2(0.0, scan_y), Vector2(VIEWPORT_SIZE.x, 2.0)), Color(0.42, 1.0, 0.66, 0.22), true)
	draw_rect(Rect2(Vector2(0.0, scan_y + 7.0), Vector2(VIEWPORT_SIZE.x, 1.0)), Color(1.0, 0.72, 0.24, 0.12), true)

	var grid_color := Color(0.33, 0.75, 0.55, 0.10)
	var step := 48.0
	for x_index in range(int(VIEWPORT_SIZE.x / step) + 1):
		var x := float(x_index) * step
		draw_line(Vector2(x, 0.0), Vector2(x, VIEWPORT_SIZE.y), grid_color, 1.0)
	for y_index in range(int(VIEWPORT_SIZE.y / step) + 1):
		var y := float(y_index) * step
		draw_line(Vector2(0.0, y), Vector2(VIEWPORT_SIZE.x, y), grid_color, 1.0)

	var rail_offset := fposmod(_ui_anim_time * 34.0, 160.0)
	for index in range(-2, 8):
		var x0 := float(index) * 124.0 - rail_offset
		draw_line(Vector2(x0, VIEWPORT_SIZE.y), Vector2(x0 + 230.0, 0.0), Color(0.28, 0.85, 0.90, 0.11), 2.0)
		draw_line(Vector2(VIEWPORT_SIZE.x - x0, VIEWPORT_SIZE.y), Vector2(VIEWPORT_SIZE.x - x0 - 230.0, 0.0), Color(1.0, 0.45, 0.32, 0.08), 2.0)


func _draw_game_world() -> void:
	draw_rect(WORLD_RECT.grow(18.0), Color(0.0, 0.0, 0.0, 0.28), true)
	draw_rect(WORLD_RECT.grow(10.0), Color(0.09, 0.16, 0.13, 0.35), true)
	draw_rect(WORLD_RECT, Color(0.044, 0.066, 0.064, 1.0), true)
	_draw_world_grid()
	_draw_backdrop_stars()
	var scan_y := WORLD_RECT.position.y + fposmod(_ui_anim_time * 80.0, WORLD_RECT.size.y)
	draw_line(Vector2(WORLD_RECT.position.x, scan_y), Vector2(WORLD_RECT.end.x, scan_y), Color(0.42, 1.0, 0.66, 0.13), 1.0)
	draw_rect(WORLD_RECT.grow(2.0), Color(1.0, 0.72, 0.24, 0.18), false, 1.0)
	draw_rect(WORLD_RECT, Color(0.40, 0.82, 0.58, 0.62), false, 2.0)


func _draw_world_grid() -> void:
	var grid_color := Color(0.33, 0.55, 0.49, 0.12)
	var step := 40.0
	for x_index in range(int(WORLD_RECT.size.x / step) + 1):
		var x := WORLD_RECT.position.x + float(x_index) * step
		draw_line(Vector2(x, WORLD_RECT.position.y), Vector2(x, WORLD_RECT.position.y + WORLD_RECT.size.y), grid_color, 1.0)
	var scrolled := fmod(_world_scroll_offset, step)
	for y_index in range(int(WORLD_RECT.size.y / step) + 2):
		var y := WORLD_RECT.position.y + fposmod(float(y_index) * step + scrolled, WORLD_RECT.size.y + step) - step
		if y < WORLD_RECT.position.y or y > WORLD_RECT.end.y:
			continue
		draw_line(Vector2(WORLD_RECT.position.x, y), Vector2(WORLD_RECT.position.x + WORLD_RECT.size.x, y), grid_color, 1.0)


func _draw_backdrop_stars() -> void:
	for star in _backdrop_stars:
		var star_data: Dictionary = star
		var parallax := float(star_data.get("parallax", 0.5))
		var base := Vector2(float(star_data.get("x", 0.0)), float(star_data.get("y", 0.0)))
		var y := WORLD_RECT.position.y + fposmod(base.y + _world_scroll_offset * parallax, WORLD_RECT.size.y)
		var alpha := 0.10 + parallax * 0.22
		var star_radius := 1.0 + parallax * 1.6
		draw_circle(Vector2(base.x, y), star_radius, Color(0.72, 0.92, 0.84, alpha))


func _generate_backdrop_stars() -> void:
	_backdrop_stars.clear()
	var star_rng := RandomNumberGenerator.new()
	star_rng.seed = 20260702
	for index in range(56):
		_backdrop_stars.append({
			"x": star_rng.randf_range(WORLD_RECT.position.x + 6.0, WORLD_RECT.end.x - 6.0),
			"y": star_rng.randf_range(0.0, WORLD_RECT.size.y),
			"parallax": 0.35 if index % 3 == 0 else star_rng.randf_range(0.55, 1.0),
		})


func _update_status() -> void:
	var lobby_text := String(_session.call("lobby_id"))
	var status_text := "Mode: %s\nPeer: %d\nLobby: %s\nPlayers: %d" % [
		String(_session.call("active_transport")),
		int(_session.call("local_peer_id")),
		lobby_text if lobby_text != "" else "-",
		_players.size(),
	]
	if _multiplayer_status_label != null:
		_multiplayer_status_label.text = status_text
	if _steam_status_label != null:
		var steam_available := bool(_session.call("steam_available"))
		_steam_status_label.text = String(_session.call("steam_status_text"))
		if _host_steam_button != null:
			_host_steam_button.disabled = not steam_available
		if _join_steam_button != null:
			_join_steam_button.disabled = not steam_available
	if _ready_room_label != null:
		var active_transport := String(_session.call("active_transport"))
		var host_active := bool(_session.call("is_host"))
		if active_transport == "offline":
			_ready_room_label.text = "Ready room: no active session."
		elif host_active:
			_ready_room_label.text = "Ready room\nPlayers connected: %d\nStart when everyone has joined." % _players.size()
		else:
			_ready_room_label.text = "Ready room\nConnected as peer %d\nWaiting for host to start." % int(_session.call("local_peer_id"))
	if _start_battle_button != null:
		_start_battle_button.disabled = (
			not bool(_session.call("is_host"))
			or String(_session.call("active_transport")) == "offline"
			or _players.size() < 2
		)


func _append_log(message: String) -> void:
	_log_lines.append(message)
	while _log_lines.size() > 14:
		_log_lines.pop_front()
	if _log_label != null:
		_log_label.text = "\n".join(_log_lines)
	print("[SteamworksLab] %s" % message)


func _ensure_input_actions() -> void:
	_register_key_action(ACTION_MOVE_UP, KEY_W)
	_register_key_action(ACTION_MOVE_UP, KEY_UP)
	_register_key_action(ACTION_MOVE_DOWN, KEY_S)
	_register_key_action(ACTION_MOVE_DOWN, KEY_DOWN)
	_register_key_action(ACTION_MOVE_LEFT, KEY_A)
	_register_key_action(ACTION_MOVE_LEFT, KEY_LEFT)
	_register_key_action(ACTION_MOVE_RIGHT, KEY_D)
	_register_key_action(ACTION_MOVE_RIGHT, KEY_RIGHT)
	_register_key_action(ACTION_EXPRESSION_WHEEL, KEY_T)
	_register_key_action(ACTION_ACTIVE_ITEM, KEY_Q)
	_register_mouse_action(ACTION_FIRE, MOUSE_BUTTON_LEFT)


func _register_key_action(action_name: String, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for event in InputMap.action_get_events(action_name):
		var key_event := event as InputEventKey
		if key_event != null and key_event.keycode == keycode:
			return
	var event := InputEventKey.new()
	event.keycode = keycode
	InputMap.action_add_event(action_name, event)


func _register_mouse_action(action_name: String, button_index: MouseButton) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for event in InputMap.action_get_events(action_name):
		var mouse_event := event as InputEventMouseButton
		if mouse_event != null and mouse_event.button_index == button_index:
			return
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	InputMap.action_add_event(action_name, event)
