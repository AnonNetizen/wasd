extends Node2D

const SESSION_SCRIPT := preload("res://scripts/network_session.gd")
const LOCAL_INPUT_ROUTER_SCRIPT := preload("res://scripts/local_input_router.gd")
const PLAYER_SCRIPT := preload("res://scripts/slime_player.gd")
const AI_TEAMMATE_SCRIPT := preload("res://scripts/ai_teammate.gd")
const SLIME_BODY_SCRIPT := preload("res://scripts/slime_body.gd")
const EXPRESSION_WHEEL_SCRIPT := preload("res://scripts/expression_wheel.gd")
const BULLET_SCRIPT := preload("res://scripts/slime_bullet.gd")
const MERGED_SLIME_SCRIPT := preload("res://scripts/merged_slime.gd")
const BATTLE_DIRECTOR_SCRIPT := preload("res://scripts/battle_director.gd")
const BATTLE_HUD_SCRIPT := preload("res://scripts/battle_hud.gd")
const BUFF_PANEL_SCRIPT := preload("res://scripts/buff_panel.gd")
const PAUSE_PANEL_SCRIPT := preload("res://scripts/pause_panel.gd")
const RECORDS_PANEL_SCRIPT := preload("res://scripts/records_panel.gd")
const UI_STYLE_SCRIPT := preload("res://scripts/ui_style.gd")
const LAB_SETTINGS_SCRIPT := preload("res://scripts/lab_settings.gd")
const LAB_LOCALE_SCRIPT := preload("res://scripts/lab_locale.gd")
const LAB_SAVE_SCRIPT := preload("res://scripts/lab_save.gd")

const DESIGN_VIEWPORT_SIZE := Vector2(540.0, 960.0)
const DESIGN_WORLD_RECT := Rect2(Vector2(20.0, 70.0), Vector2(500.0, 870.0))
const WORLD_SCROLL_SPEED: float = 120.0
const DEFAULT_PORT: int = 24567
const SCREEN_START: String = "start"
const SCREEN_MULTIPLAYER: String = "multiplayer"
const SCREEN_SETTINGS: String = "settings"
const SCREEN_CUSTOMIZE: String = "customize"
const SCREEN_GAME: String = "game"

enum PlayMode {
	MENU,
	SINGLE,
	COUCH,
	STEAM_HOST,
	STEAM_CLIENT,
}

const ACTION_MOVE_UP := "move_up"
const ACTION_MOVE_DOWN := "move_down"
const ACTION_MOVE_LEFT := "move_left"
const ACTION_MOVE_RIGHT := "move_right"
const ACTION_EXPRESSION_WHEEL := "expression_wheel"
const ACTION_FIRE := "fire"
const ACTION_ACTIVE_ITEM := "active_item"
const ACTION_PAUSE_MENU := "pause_menu"
const ACTION_MERGE := "merge"
const EXPRESSION_DURATION: float = 2.2
const FIRE_COOLDOWN: float = 0.18
const FIRE_SPREAD_DEGREES: float = 2.5
const CUSTOMIZE_PREVIEW_FIRE_INTERVAL: float = 0.58
const CUSTOMIZE_PREVIEW_BULLET_SPEED: float = 320.0
const MERGE_DISTANCE: float = 92.0
const MERGE_HOLD_DURATION: float = 0.8
const MERGE_DURATION: float = 10.0
const MERGE_COOLDOWN: float = 20.0
const MERGE_SHIELD: int = 3
const MERGE_MOVE_SPEED_SCALE: float = 0.85
const MERGE_SPLIT_OFFSET: float = 24.0
const MERGE_SPLIT_INVULNERABILITY: float = 0.8
const MERGE_HIT_INVULNERABILITY: float = 0.45
const SINGLE_AI_PEER_ID: int = 1001
const SINGLE_ULTIMATE_MAX_CHARGE: int = 100
const SINGLE_ULTIMATE_HIT_CHARGE: int = 1
const SINGLE_ULTIMATE_ENEMY_KILL_CHARGE: int = 5
const SINGLE_ULTIMATE_BOSS_KILL_CHARGE: int = 20
const SINGLE_AI_DURATION: float = 10.0
const SINGLE_AI_MOVE_SPEED_SCALE: float = 1.18
const SCREEN_SHAKE_MAX_STRENGTH: float = 18.0
const SCREEN_SHAKE_MIN_DURATION: float = 0.04
const SCREEN_FLASH_MAX_ALPHA: float = 0.42
const ACTIVE_EXPRESSIONS: Array[Dictionary] = [
	{"id": "happy_01", "text": "(^_^)", "label_key": "emote_happy"},
	{"id": "wave_01", "text": "ヾ(^▽^*)", "label_key": "emote_wave"},
	{"id": "surprised_01", "text": "(⊙_⊙)", "label_key": "emote_surprised"},
	{"id": "love_01", "text": "(♡ω♡)", "label_key": "emote_love"},
	{"id": "angry_01", "text": "(｀へ´)", "label_key": "emote_angry"},
	{"id": "panic_01", "text": "(°ロ°)", "label_key": "emote_panic"},
	{"id": "ready_01", "text": "(๑•̀ㅂ•́)و", "label_key": "emote_ready"},
	{"id": "sleepy_01", "text": "(-_-) zzz", "label_key": "emote_sleepy"},
]

var _session: Node
var _local_input_router: Node
var _players: Dictionary = {}
var _peer_inputs: Dictionary = {}
var _bullets: Array[Node] = []
var _log_lines: Array[String] = []
var _screen: String = SCREEN_START
var _suppress_session_end_navigation: bool = false
var _play_mode: PlayMode = PlayMode.MENU
var _fire_held_by_player: Dictionary = {}
var _merge_held_by_player: Dictionary = {}
var _fire_cooldown_by_player: Dictionary = {}
var _aim_direction_by_player: Dictionary = {}
var _expression_held_by_player: Dictionary = {}
var _expression_owner_id: int = 0
var _fire_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _screen_shake_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _world_scroll_offset: float = 0.0
var _ui_anim_time: float = 0.0
var _backdrop_stars: Array[Dictionary] = []
var _director: Node2D
var _battle_hud: Control
var _buff_panel: Control
var _pause_panel: Control
var _settings: RefCounted
var _save: RefCounted
var _settings_config_path: String = LAB_SETTINGS_SCRIPT.CONFIG_PATH
var _save_config_path: String = LAB_SAVE_SCRIPT.CONFIG_PATH
var _ui_transition_tween: Tween
var _ui_motion_tweens: Dictionary = {}
var _local_buff_options: PackedInt32Array = PackedInt32Array()
var _couch_buff_options: Dictionary = {}
var _couch_buff_queue: Array[int] = []
var _couch_buff_player_id: int = 0
var _couch_buff_nav_y: float = 0.0
var _couch_buff_confirm_held: bool = false
var _localized_text_controls: Array[Control] = []
var _localized_placeholder_controls: Array[Control] = []
var _settings_return_screen: String = SCREEN_START
var _peer_appearances: Dictionary = {}
var _peer_merge_intents: Dictionary = {}
var _merge_intent_order: Dictionary = {}
var _merge_hold_progress: Dictionary = {}
var _active_merges: Dictionary = {}
var _merge_cooldowns: Dictionary = {}
var _next_merge_id: int = 1
var _merge_press_sequence: int = 1
var _single_ultimate_charge: int = 0
var _single_ai_teammate: Node
var _single_ai_requires_merge_release: bool = false
var _slime_swatch_buttons: Array[Button] = []
var _bullet_swatch_buttons: Array[Button] = []
var _customize_refreshing: bool = false
var _customize_preview_fire_timer: float = 0.0
var _customize_preview_bullets: Array[Node] = []
var _pause_menu_open: bool = false
var _pause_freezes_game: bool = false
var _controller_reconnect_blocked: bool = false
var _base_canvas_transform: Transform2D = Transform2D.IDENTITY
var _screen_shake_strength: float = 0.0
var _screen_shake_duration: float = 0.0
var _screen_shake_remaining: float = 0.0
var _screen_shake_offset: Vector2 = Vector2.ZERO
var _screen_flash_color: Color = Color(1.0, 0.35, 0.22, 1.0)
var _screen_flash_alpha: float = 0.0
var _screen_flash_duration: float = 0.0
var _screen_flash_remaining: float = 0.0

var _ui_root: Control
var _start_page: Control
var _multiplayer_page: Control
var _settings_page: Control
var _customize_page: Control
var _game_page: Control
var _records_panel: Control
var _lobby_input: LineEdit
var _steam_status_label: Label
var _host_steam_button: Button
var _invite_steam_button: Button
var _join_steam_button: Button
var _ready_room_label: Label
var _start_battle_button: Button
var _expression_wheel: Control
var _screen_flash_rect: ColorRect
var _language_option: OptionButton
var _resolution_option: OptionButton
var _fullscreen_check: CheckButton
var _customize_name_input: LineEdit
var _customize_preview_area: Control
var _customize_preview_body: Node2D
var _customize_preview_name_label: Label
var _steam_invite_confirm_panel: Control
var _steam_invite_confirm_card: PanelContainer
var _steam_invite_confirm_title_label: Label
var _steam_invite_confirm_body_label: Label
var _steam_invite_confirm_accept_button: Button
var _steam_invite_confirm_cancel_button: Button
var _steam_invite_confirm_tween: Tween
var _pending_steam_invite_lobby_id: String = ""


func _ready() -> void:
	_fire_rng.randomize()
	_screen_shake_rng.randomize()
	_base_canvas_transform = get_viewport().canvas_transform
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_generate_backdrop_stars()
	_ensure_input_actions()
	_create_session()
	_create_local_input_router()
	_load_lab_settings()
	_load_lab_save()
	_create_ui()
	_sync_world_rect()
	_show_start_page()


func _physics_process(delta: float) -> void:
	_ui_anim_time += delta
	_update_screen_effects(delta)
	_update_customize_preview(delta)
	if _screen == SCREEN_GAME:
		if _play_mode == PlayMode.COUCH:
			_poll_couch_pause_input()
		if _pause_blocks_gameplay_tick():
			_refresh_battle_hud()
		else:
			_update_gameplay(delta)
		if _battle_active() and not _pause_blocks_gameplay_tick():
			_world_scroll_offset += WORLD_SCROLL_SPEED * delta
	elif _session != null and bool(_session.call("is_host")) and String(_session.call("active_transport")) != "offline":
		_session.call("broadcast_snapshot", _build_snapshot())
	_update_status()
	queue_redraw()


func _exit_tree() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.canvas_transform = _base_canvas_transform


func player_nodes() -> Dictionary:
	return _players


func design_viewport_size() -> Vector2:
	return DESIGN_VIEWPORT_SIZE


func current_viewport_size() -> Vector2:
	var viewport_size := get_viewport_rect().size
	return Vector2(
		maxf(viewport_size.x, DESIGN_VIEWPORT_SIZE.x),
		maxf(viewport_size.y, DESIGN_VIEWPORT_SIZE.y)
	)


func current_world_rect() -> Rect2:
	return _world_rect()


func _on_viewport_size_changed() -> void:
	_sync_world_rect()


func _sync_world_rect() -> void:
	var world_rect := _world_rect()
	if _director != null:
		_director.call("set_world_rect", world_rect)
	for peer_id in _players.keys():
		var player := _players[peer_id] as Node
		if player != null and is_instance_valid(player):
			player.call("set_movement_bounds", world_rect)
	if _single_ai_active():
		_single_ai_teammate.call("set_movement_bounds", world_rect)
	queue_redraw()


func _world_rect() -> Rect2:
	return Rect2(_design_origin() + DESIGN_WORLD_RECT.position, DESIGN_WORLD_RECT.size)


func _design_origin() -> Vector2:
	var viewport_size := current_viewport_size()
	return Vector2(
		maxf(0.0, (viewport_size.x - DESIGN_VIEWPORT_SIZE.x) * 0.5),
		maxf(0.0, (viewport_size.y - DESIGN_VIEWPORT_SIZE.y) * 0.5)
	)


func _battle_active() -> bool:
	if _director == null:
		return false
	return int(_director.get("phase")) == BATTLE_DIRECTOR_SCRIPT.Phase.BATTLE


func _start_battle() -> void:
	if _director == null:
		_director = BATTLE_DIRECTOR_SCRIPT.new() as Node2D
		_director.name = "BattleDirector"
		add_child(_director)
		_director.call("setup", self, _session, _world_rect())
		_director.connect("phase_changed", Callable(self, "_on_director_phase_changed"))
		_director.connect("buff_options_ready", Callable(self, "_on_director_buff_options"))
		_director.connect("active_item_used", Callable(self, "_on_director_active_item_used"))
		_director.connect("player_enemy_hit", Callable(self, "_on_player_enemy_hit"))
	_reset_battle()


func _end_battle() -> void:
	_close_pause_menu()
	if _director != null:
		_director.call("reset_battle")


func _reset_battle() -> void:
	_close_pause_menu()
	_clear_screen_fx()
	_reset_single_ultimate()
	if _director != null:
		_director.call("reset_battle")
	_clear_bullets()
	_clear_merges()
	_clear_local_input_state()
	if _buff_panel != null:
		_buff_panel.call("close")
	var slot := 0
	for peer_id in _players.keys():
		var player := _players[peer_id] as Node
		if player == null or not is_instance_valid(player):
			continue
		player.call("revive_full")
		player.call("set_battle_timers_paused", false)
		player.call("set_move_speed", BATTLE_DIRECTOR_SCRIPT.PLAYER_BASE_MOVE_SPEED)
		player.call("warp_to", _spawn_position_for_slot(slot))
		slot += 1


func set_player_bullets_frozen(frozen: bool) -> void:
	for bullet in _bullets:
		if is_instance_valid(bullet):
			bullet.call("set_battle_frozen", frozen)


func request_screen_shake(strength: float, duration: float) -> void:
	if strength <= 0.0 or duration <= 0.0:
		return
	_screen_shake_strength = maxf(
		_screen_shake_strength,
		clampf(strength, 0.0, SCREEN_SHAKE_MAX_STRENGTH)
	)
	_screen_shake_duration = maxf(_screen_shake_duration, maxf(duration, SCREEN_SHAKE_MIN_DURATION))
	_screen_shake_remaining = maxf(_screen_shake_remaining, maxf(duration, SCREEN_SHAKE_MIN_DURATION))
	_sample_screen_shake_offset()
	_apply_canvas_shake()


func request_screen_flash(color: Color, alpha: float, duration: float) -> void:
	if alpha <= 0.0 or duration <= 0.0:
		return
	_screen_flash_color = color
	_screen_flash_alpha = maxf(_screen_flash_alpha, clampf(alpha, 0.0, SCREEN_FLASH_MAX_ALPHA))
	_screen_flash_duration = maxf(_screen_flash_duration, duration)
	_screen_flash_remaining = maxf(_screen_flash_remaining, duration)
	_apply_screen_flash()


func screen_fx_state() -> Dictionary:
	return {
		"shake_remaining": _screen_shake_remaining,
		"shake_strength": _screen_shake_strength,
		"shake_offset": _screen_shake_offset,
		"flash_alpha": _screen_flash_alpha,
		"flash_remaining": _screen_flash_remaining,
		"flash_visible": _screen_flash_rect != null and _screen_flash_rect.visible,
	}


func _update_screen_effects(delta: float) -> void:
	if _screen_shake_remaining > 0.0:
		_screen_shake_remaining = maxf(0.0, _screen_shake_remaining - delta)
		_sample_screen_shake_offset()
	else:
		_screen_shake_strength = 0.0
		_screen_shake_duration = 0.0
		_screen_shake_offset = Vector2.ZERO
	_apply_canvas_shake()

	if _screen_flash_remaining > 0.0:
		_screen_flash_remaining = maxf(0.0, _screen_flash_remaining - delta)
	else:
		_screen_flash_alpha = 0.0
		_screen_flash_duration = 0.0
	_apply_screen_flash()


func _sample_screen_shake_offset() -> void:
	if _screen_shake_remaining <= 0.0 or _screen_shake_duration <= 0.0:
		_screen_shake_offset = Vector2.ZERO
		return
	var life_ratio := clampf(_screen_shake_remaining / _screen_shake_duration, 0.0, 1.0)
	var amplitude := _screen_shake_strength * pow(life_ratio, 1.35)
	if amplitude <= 0.05:
		_screen_shake_offset = Vector2.ZERO
		return
	var direction := Vector2(
		_screen_shake_rng.randf_range(-1.0, 1.0),
		_screen_shake_rng.randf_range(-1.0, 1.0)
	)
	if direction.length_squared() <= 0.0001:
		direction = Vector2.RIGHT
	_screen_shake_offset = direction.normalized() * amplitude


func _apply_canvas_shake() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var transform := _base_canvas_transform
	transform.origin += _screen_shake_offset
	viewport.canvas_transform = transform


func _apply_screen_flash() -> void:
	if _screen_flash_rect == null:
		return
	if _screen_flash_remaining <= 0.0 or _screen_flash_duration <= 0.0:
		_screen_flash_rect.visible = false
		_screen_flash_rect.color = Color(_screen_flash_color, 0.0)
		return
	var life_ratio := clampf(_screen_flash_remaining / _screen_flash_duration, 0.0, 1.0)
	_screen_flash_rect.visible = true
	_screen_flash_rect.color = Color(_screen_flash_color, _screen_flash_alpha * life_ratio)


func _clear_screen_fx() -> void:
	_screen_shake_strength = 0.0
	_screen_shake_duration = 0.0
	_screen_shake_remaining = 0.0
	_screen_shake_offset = Vector2.ZERO
	_screen_flash_alpha = 0.0
	_screen_flash_duration = 0.0
	_screen_flash_remaining = 0.0
	_apply_canvas_shake()
	_apply_screen_flash()


func _on_director_phase_changed(new_phase: int, payload: Dictionary) -> void:
	_sync_player_battle_timers(new_phase == BATTLE_DIRECTOR_SCRIPT.Phase.BATTLE)
	if new_phase == BATTLE_DIRECTOR_SCRIPT.Phase.GAME_OVER:
		_reset_single_ultimate()
		_record_game_over_survival_time(payload)
	if _buff_panel != null:
		if new_phase == BATTLE_DIRECTOR_SCRIPT.Phase.BATTLE:
			_buff_panel.call("close")
			_couch_buff_options.clear()
			_couch_buff_queue.clear()
			_couch_buff_player_id = 0
		elif new_phase == BATTLE_DIRECTOR_SCRIPT.Phase.CHOOSING_BUFF and not _buff_panel.visible:
			if _play_mode == PlayMode.COUCH:
				_couch_buff_options.clear()
				_couch_buff_queue.clear()
				_couch_buff_player_id = 0
			else:
				_buff_panel.call("show_waiting", _waiting_text())
	if _session != null and bool(_session.call("is_host")):
		_session.call("broadcast_phase", new_phase, payload)


func _on_director_buff_options(peer_id: int, options: PackedInt32Array) -> void:
	if _play_mode == PlayMode.COUCH:
		_couch_buff_options[peer_id] = options
		if not _couch_buff_queue.has(peer_id):
			_couch_buff_queue.append(peer_id)
			_couch_buff_queue.sort()
		if _couch_buff_player_id <= 0:
			_open_next_couch_buff()
		return
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


func _on_player_enemy_hit(peer_id: int, defeated: bool, is_boss: bool) -> void:
	if _play_mode != PlayMode.SINGLE or peer_id != 1 or _single_ai_active():
		return
	var gained_charge := SINGLE_ULTIMATE_HIT_CHARGE
	if defeated:
		gained_charge += (
			SINGLE_ULTIMATE_BOSS_KILL_CHARGE
			if is_boss
			else SINGLE_ULTIMATE_ENEMY_KILL_CHARGE
		)
	_single_ultimate_charge = mini(
		SINGLE_ULTIMATE_MAX_CHARGE,
		_single_ultimate_charge + gained_charge
	)


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
	_append_log(_t("log_host_started_battle"))


func _open_buff_panel(options: PackedInt32Array, player_label: String = "") -> void:
	if _buff_panel == null or _director == null:
		return
	var defs: Array[Dictionary] = []
	for buff_id in options:
		defs.append(_localized_buff_def(_director.call("buff_def", buff_id)))
	var timeout := 0.0
	if String(_session.call("active_transport")) != "offline":
		timeout = BATTLE_DIRECTOR_SCRIPT.BUFF_CHOICE_TIMEOUT
	_buff_panel.call("set_routed_controller_input", _play_mode == PlayMode.COUCH)
	_buff_panel.call(
		"set_mouse_selection_enabled",
		_play_mode != PlayMode.COUCH or _couch_buff_player_id == 1
	)
	_buff_panel.call("open_with_options", defs, timeout, player_label)


func _on_buff_option_chosen(option_index: int) -> void:
	if _director == null:
		return
	if _play_mode == PlayMode.COUCH:
		if _couch_buff_player_id <= 0:
			return
		var player_id := _couch_buff_player_id
		_couch_buff_player_id = 0
		_director.call("submit_buff_choice", player_id, option_index)
		if int(_director.get("phase")) == BATTLE_DIRECTOR_SCRIPT.Phase.CHOOSING_BUFF:
			_open_next_couch_buff()
		return
	var local_id := int(_session.call("local_peer_id"))
	if bool(_director.call("is_authority")):
		_director.call("submit_buff_choice", local_id, option_index)
		if not _battle_active() and _buff_panel != null:
			_buff_panel.call("show_waiting", _waiting_text())
		return
	if option_index >= 0 and option_index < _local_buff_options.size():
		_director.call("apply_buff", local_id, _local_buff_options[option_index])
	_session.call("send_buff_choice_to_host", option_index)
	if _buff_panel != null:
		_buff_panel.call("show_waiting", _waiting_text())


func _open_next_couch_buff() -> void:
	while not _couch_buff_queue.is_empty():
		var player_id: int = int(_couch_buff_queue.pop_front())
		if not _couch_buff_options.has(player_id):
			continue
		var player := _players.get(player_id) as Node
		if player == null or not bool(player.get("alive")):
			continue
		_couch_buff_player_id = player_id
		_couch_buff_nav_y = 0.0
		_couch_buff_confirm_held = false
		var player_label := _display_name_for_peer(player_id)
		if player_label.strip_edges() == "":
			player_label = "P%d" % player_id
		_open_buff_panel(_couch_buff_options[player_id], player_label)
		return
	_couch_buff_player_id = 0


func _unhandled_input(event: InputEvent) -> void:
	if _screen != SCREEN_GAME:
		return
	var player_id := _keyboard_player_id()
	var key_event := event as InputEventKey
	if event.is_action_pressed(ACTION_PAUSE_MENU) and (key_event == null or not key_event.echo):
		if _pause_menu_open:
			if not _controller_reconnect_blocked:
				_close_pause_menu()
		elif _can_open_pause_menu():
			_open_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if _pause_menu_open:
		get_viewport().set_input_as_handled()
		return
	if _play_mode == PlayMode.COUCH:
		# Couch gameplay consumes P1 through the same per-slot frame route as controllers.
		# Esc remains event-driven above so pause cannot be missed between process frames.
		return
	if event.is_action_pressed(ACTION_EXPRESSION_WHEEL) and (key_event == null or not key_event.echo):
		_open_expression_wheel(player_id, false)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_released(ACTION_EXPRESSION_WHEEL):
		_release_expression_wheel(player_id)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(ACTION_ACTIVE_ITEM) and (key_event == null or not key_event.echo):
		_try_active_item(player_id)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(ACTION_MERGE) and (key_event == null or not key_event.echo):
		if _try_summon_single_ai():
			get_viewport().set_input_as_handled()
			return
		_set_local_merge_intent(true, player_id)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_released(ACTION_MERGE):
		_set_local_merge_intent(false, player_id)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(ACTION_FIRE):
		_fire_held_by_player[player_id] = true
		_try_fire(player_id)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_released(ACTION_FIRE):
		_fire_held_by_player[player_id] = false
		get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, current_viewport_size()), UI_STYLE_SCRIPT.BG_COLOR, true)
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
	_session.connect("appearance_received", Callable(self, "_on_appearance_received"))
	_session.connect("merge_intent_received", Callable(self, "_on_merge_intent_received"))
	_session.connect("steam_invite_join_requested", Callable(self, "_on_steam_invite_join_requested"))


func _create_local_input_router() -> void:
	_local_input_router = LOCAL_INPUT_ROUTER_SCRIPT.new() as Node
	_local_input_router.name = "LocalInputRouter"
	add_child(_local_input_router)
	_local_input_router.connect("roster_changed", Callable(self, "_on_couch_roster_changed"))
	_local_input_router.connect("controller_missing", Callable(self, "_on_couch_controller_missing"))
	_local_input_router.connect("controllers_restored", Callable(self, "_on_couch_controllers_restored"))
	_local_input_router.connect("controller_overflow", Callable(self, "_on_couch_controller_overflow"))


func local_input_router() -> Node:
	return _local_input_router


func couch_player_count() -> int:
	return _players.size() if _play_mode == PlayMode.COUCH else 0


func _on_couch_roster_changed(slots: Array[Dictionary]) -> void:
	if _play_mode != PlayMode.COUCH:
		return
	_sync_couch_roster(slots)


func _sync_couch_roster(slots: Array[Dictionary]) -> void:
	var expected: Dictionary = {}
	for row in slots:
		var slot_id := int(row.get("slot_id", row.get("slot", 0)))
		if slot_id < 1 or slot_id > 4:
			continue
		expected[slot_id] = true
		var fallback_name := "" if slot_id == 1 else "P%d" % slot_id
		var player: Node = _ensure_player(slot_id, fallback_name)
		player.call("set_local_or_host_simulated", true)
		_peer_inputs[slot_id] = Vector2.ZERO
		_peer_merge_intents[slot_id] = false
		if slot_id == 1:
			_apply_local_appearance(false)
		else:
			_apply_appearance_to_player(slot_id, {
				"name": fallback_name,
				"slime_palette_id": slot_id - 1,
				"bullet_palette_id": slot_id - 1,
			}, fallback_name)
	if not bool(_local_input_router.call("is_locked")):
		for existing_id in _players.keys():
			var player_id := int(existing_id)
			if not expected.has(player_id):
				_remove_player(player_id)
	_update_status()


func _on_couch_controller_missing(_slot_id: int) -> void:
	if _play_mode != PlayMode.COUCH or _screen != SCREEN_GAME:
		return
	_controller_reconnect_blocked = true
	_open_pause_menu()
	if _pause_panel != null:
		_pause_panel.call("open_controller_reconnect", _missing_controller_labels())


func _on_couch_controllers_restored() -> void:
	if not _controller_reconnect_blocked:
		return
	_controller_reconnect_blocked = false
	if _pause_panel != null:
		_pause_panel.call("mark_controllers_restored")


func _missing_controller_labels() -> Array[String]:
	var labels: Array[String] = []
	if _local_input_router == null:
		return labels
	var missing: Array = _local_input_router.call("missing_slot_ids")
	for raw_slot_id in missing:
		labels.append("P%d" % int(raw_slot_id))
	return labels


func _on_couch_controller_overflow(ignored_count: int) -> void:
	if _play_mode != PlayMode.COUCH:
		return
	if ignored_count > 0:
		var message := _t("log_couch_controller_overflow", {"count": ignored_count})
		_append_log(message)
		if _screen == SCREEN_GAME and _battle_hud != null:
			_battle_hud.call("show_notice", message)
	_update_status()


func _disable_couch_mode() -> void:
	if _local_input_router != null:
		_local_input_router.call("disable")
	_controller_reconnect_blocked = false
	_couch_buff_options.clear()
	_couch_buff_queue.clear()
	_couch_buff_player_id = 0
	_clear_local_input_state()
	if _play_mode == PlayMode.COUCH:
		_play_mode = PlayMode.MENU


func _load_lab_settings() -> void:
	_settings = LAB_SETTINGS_SCRIPT.new(_settings_config_path)
	var steam_language := ""
	if _session != null and _session.has_method("steam_game_language"):
		steam_language = String(_session.call("steam_game_language"))
	_settings.call("load_settings", steam_language)
	_settings.call("apply_fullscreen")


func _load_lab_save() -> void:
	_save = LAB_SAVE_SCRIPT.new(_save_config_path)
	_save.call("load_save")


func _record_game_over_survival_time(payload: Dictionary) -> void:
	if _save == null:
		return
	var category := _record_category_for_play_mode(_play_mode)
	if category < 0:
		return
	var seconds := float(payload.get("time", -1.0))
	if seconds < 0.0 and _director != null:
		var state: Dictionary = _director.call("battle_state")
		seconds = float(state.get("time", 0.0))
	if seconds <= 0.0:
		return
	if bool(_save.call("record_survival_time", category, seconds)):
		_refresh_records_panel()


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
	_create_settings_page()
	_create_customize_page()
	_create_game_page()
	_create_records_panel()
	_create_steam_invite_confirm_panel()


func _create_start_page() -> void:
	_start_page = _make_page("StartPage")
	var rows := _make_centered_panel(_start_page, "StartPanel", Vector2(520.0, 650.0), "hero")
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", 14)

	var kicker := _make_kicker_label(_t("main_kicker"))
	_register_localized_text(kicker, "main_kicker")
	rows.add_child(kicker)

	var title := _make_title_label(_t("app_title"))
	_register_localized_text(title, "app_title")
	title.add_theme_font_size_override("font_size", 32)
	rows.add_child(title)

	var subtitle := _make_body_label(_t("main_subtitle"))
	_register_localized_text(subtitle, "main_subtitle")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(subtitle)

	var button_stack := VBoxContainer.new()
	button_stack.add_theme_constant_override("separation", 10)
	button_stack.custom_minimum_size = Vector2(320.0, 0.0)
	rows.add_child(button_stack)

	var single_player_button := _make_button(_t("main_single"), Vector2(320.0, 52.0), true)
	_register_localized_text(single_player_button, "main_single")
	single_player_button.pressed.connect(_on_start_single_player_pressed)
	button_stack.add_child(single_player_button)

	var multiplayer_button := _make_button(_t("main_multiplayer"), Vector2(320.0, 48.0))
	_register_localized_text(multiplayer_button, "main_multiplayer")
	multiplayer_button.pressed.connect(_on_start_multiplayer_pressed)
	button_stack.add_child(multiplayer_button)

	var records_button := _make_button(_t("main_records"), Vector2(320.0, 42.0))
	_register_localized_text(records_button, "main_records")
	records_button.pressed.connect(_on_records_pressed)
	button_stack.add_child(records_button)

	var customize_button := _make_button(_t("main_customize"), Vector2(320.0, 42.0))
	_register_localized_text(customize_button, "main_customize")
	customize_button.pressed.connect(_on_customize_pressed)
	button_stack.add_child(customize_button)

	var settings_button := _make_button(_t("main_settings"), Vector2(320.0, 42.0))
	_register_localized_text(settings_button, "main_settings")
	settings_button.pressed.connect(_on_settings_pressed)
	button_stack.add_child(settings_button)

	var exit_button := _make_button(_t("main_exit"), Vector2(320.0, 42.0))
	_register_localized_text(exit_button, "main_exit")
	exit_button.pressed.connect(_on_exit_pressed)
	button_stack.add_child(exit_button)

	var hint := _make_hint_label(_t("main_hint"))
	_register_localized_text(hint, "main_hint")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(hint)


func _create_multiplayer_page() -> void:
	_multiplayer_page = _make_page("MultiplayerPage")
	var rows := _make_centered_panel(_multiplayer_page, "MultiplayerPanel", Vector2(500.0, 760.0), "hero")
	rows.add_theme_constant_override("separation", 10)

	var kicker := _make_kicker_label(_t("ready_room_kicker"))
	_register_localized_text(kicker, "ready_room_kicker")
	rows.add_child(kicker)

	var title := _make_title_label(_t("multiplayer_title"))
	_register_localized_text(title, "multiplayer_title")
	title.add_theme_font_size_override("font_size", 30)
	rows.add_child(title)

	var body := VBoxContainer.new()
	body.name = "MultiplayerBody"
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(body)

	var local_section := _make_section_box(body, "section_local", "Local")

	var host_local_button := _make_button(_t("host_local"), Vector2(0.0, 42.0), true)
	_register_localized_text(host_local_button, "host_local")
	host_local_button.pressed.connect(_on_start_couch_pressed)
	local_section.add_child(host_local_button)

	var local_hint := _make_hint_label(_t("local_couch_hint"))
	_register_localized_text(local_hint, "local_couch_hint")
	local_section.add_child(local_hint)

	var steam_section := _make_section_box(body, "section_steam", "Steam")

	_steam_status_label = Label.new()
	_steam_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_steam_status_label.add_theme_color_override("font_color", UI_STYLE_SCRIPT.MUTED_TEXT_COLOR)
	steam_section.add_child(_steam_status_label)

	_host_steam_button = _make_button(_t("host_steam"))
	_register_localized_text(_host_steam_button, "host_steam")
	_host_steam_button.pressed.connect(_on_host_steam_pressed)
	steam_section.add_child(_host_steam_button)

	_invite_steam_button = _make_button(_t("invite_steam_friend"))
	_register_localized_text(_invite_steam_button, "invite_steam_friend")
	_invite_steam_button.pressed.connect(_on_invite_steam_pressed)
	steam_section.add_child(_invite_steam_button)

	_lobby_input = LineEdit.new()
	_lobby_input.placeholder_text = _t("steam_lobby_id_placeholder")
	_register_localized_placeholder(_lobby_input, "steam_lobby_id_placeholder")
	UI_STYLE_SCRIPT.apply_input(_lobby_input)
	steam_section.add_child(_lobby_input)

	_join_steam_button = _make_button(_t("join_steam"))
	_register_localized_text(_join_steam_button, "join_steam")
	_join_steam_button.pressed.connect(_on_join_steam_pressed)
	steam_section.add_child(_join_steam_button)

	var ready_section := _make_section_box(body, "section_ready_room", "ReadyRoom")

	_ready_room_label = Label.new()
	_ready_room_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ready_room_label.add_theme_color_override("font_color", UI_STYLE_SCRIPT.TEXT_COLOR)
	ready_section.add_child(_ready_room_label)

	_start_battle_button = _make_button(_t("start_battle"), Vector2(0.0, 46.0), true)
	_register_localized_text(_start_battle_button, "start_battle")
	_start_battle_button.pressed.connect(_on_ready_start_battle_pressed)
	ready_section.add_child(_start_battle_button)

	var session_buttons := HBoxContainer.new()
	session_buttons.add_theme_constant_override("separation", 8)
	ready_section.add_child(session_buttons)

	var leave_button := _make_button(_t("leave_session"))
	_register_localized_text(leave_button, "leave_session")
	leave_button.pressed.connect(_on_multiplayer_leave_pressed)
	session_buttons.add_child(leave_button)

	var back_button := _make_button(_t("back"))
	_register_localized_text(back_button, "back")
	back_button.pressed.connect(_on_multiplayer_back_pressed)
	session_buttons.add_child(back_button)

func _create_settings_page() -> void:
	_settings_page = _make_page("SettingsPage")
	var rows := _make_centered_panel(_settings_page, "SettingsPanel", Vector2(456.0, 520.0), "hero")
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", 14)

	var kicker := _make_kicker_label(_t("settings_kicker"))
	_register_localized_text(kicker, "settings_kicker")
	rows.add_child(kicker)

	var title := _make_title_label(_t("settings_title"))
	_register_localized_text(title, "settings_title")
	title.add_theme_font_size_override("font_size", 30)
	rows.add_child(title)

	var language_label := _make_kicker_label(_t("settings_language"))
	_register_localized_text(language_label, "settings_language")
	language_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rows.add_child(language_label)

	_language_option = OptionButton.new()
	_language_option.name = "LanguageOption"
	_language_option.custom_minimum_size = Vector2(320.0, 42.0)
	_language_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_language_option.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UI_STYLE_SCRIPT.apply_option_button(_language_option)
	rows.add_child(_language_option)

	var resolution_label := _make_kicker_label(_t("settings_resolution"))
	_register_localized_text(resolution_label, "settings_resolution")
	resolution_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rows.add_child(resolution_label)

	_resolution_option = OptionButton.new()
	_resolution_option.name = "ResolutionOption"
	_resolution_option.custom_minimum_size = Vector2(320.0, 42.0)
	_resolution_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resolution_option.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	UI_STYLE_SCRIPT.apply_option_button(_resolution_option)
	rows.add_child(_resolution_option)

	_fullscreen_check = CheckButton.new()
	_fullscreen_check.name = "FullscreenCheck"
	_fullscreen_check.text = _t("settings_fullscreen")
	_register_localized_text(_fullscreen_check, "settings_fullscreen")
	_fullscreen_check.button_pressed = bool(_settings.get("fullscreen"))
	_fullscreen_check.custom_minimum_size = Vector2(320.0, 40.0)
	_fullscreen_check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fullscreen_check.add_theme_color_override("font_color", UI_STYLE_SCRIPT.TEXT_COLOR)
	_fullscreen_check.add_theme_color_override("font_pressed_color", UI_STYLE_SCRIPT.AMBER_COLOR)
	rows.add_child(_fullscreen_check)

	var back_button := _make_button(_t("settings_back"), Vector2(320.0, 44.0), true)
	_register_localized_text(back_button, "settings_back")
	back_button.pressed.connect(_on_settings_back_pressed)
	rows.add_child(back_button)

	_refresh_language_option()
	_refresh_resolution_option()
	_language_option.item_selected.connect(_on_language_selected)
	_resolution_option.item_selected.connect(_on_resolution_selected)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)


func _create_customize_page() -> void:
	_customize_page = _make_page("CustomizePage")
	var rows := _make_centered_panel(_customize_page, "CustomizePanel", Vector2(520.0, 850.0), "hero")
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", 12)

	var kicker := _make_kicker_label(_t("customize_kicker"))
	_register_localized_text(kicker, "customize_kicker")
	rows.add_child(kicker)

	var title := _make_title_label(_t("customize_title"))
	_register_localized_text(title, "customize_title")
	title.add_theme_font_size_override("font_size", 30)
	rows.add_child(title)

	var preview_section := _make_section_box(rows, "customize_preview", "CustomizePreview")
	_customize_preview_area = Control.new()
	_customize_preview_area.name = "CustomizePreviewArea"
	_customize_preview_area.clip_contents = true
	_customize_preview_area.custom_minimum_size = Vector2(360.0, 170.0)
	_customize_preview_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_section.add_child(_customize_preview_area)
	_customize_preview_area.resized.connect(_refresh_customize_preview)
	_customize_preview_body = SLIME_BODY_SCRIPT.new() as Node2D
	_customize_preview_body.name = "CustomizeSlimePreview"
	_customize_preview_body.scale = Vector2(1.45, 1.45)
	_customize_preview_area.add_child(_customize_preview_body)
	_customize_preview_body.call("set_position_drive_enabled", false)
	_customize_preview_name_label = Label.new()
	_customize_preview_name_label.name = "CustomizePreviewNameLabel"
	_customize_preview_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_customize_preview_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_customize_preview_name_label.z_index = 8
	_customize_preview_name_label.add_theme_font_size_override("font_size", 16)
	_customize_preview_name_label.add_theme_color_override("font_color", Color(0.92, 0.98, 1.0, 1.0))
	_customize_preview_name_label.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.08, 0.92))
	_customize_preview_name_label.add_theme_constant_override("outline_size", 3)
	_customize_preview_area.add_child(_customize_preview_name_label)

	var name_section := _make_section_box(rows, "customize_name", "CustomizeName")
	_customize_name_input = LineEdit.new()
	_customize_name_input.name = "CustomizeNameInput"
	_customize_name_input.text = String(_settings.get("player_name"))
	_customize_name_input.placeholder_text = _t("customize_name_placeholder")
	_register_localized_placeholder(_customize_name_input, "customize_name_placeholder")
	_customize_name_input.max_length = int(LAB_SETTINGS_SCRIPT.MAX_PLAYER_NAME_LENGTH)
	_customize_name_input.custom_minimum_size = Vector2(320.0, 42.0)
	_customize_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI_STYLE_SCRIPT.apply_input(_customize_name_input)
	name_section.add_child(_customize_name_input)
	_customize_name_input.text_changed.connect(_on_customize_name_changed)

	var slime_section := _make_section_box(rows, "customize_slime_color", "CustomizeSlime")
	var slime_grid := _make_palette_grid()
	slime_section.add_child(slime_grid)
	_slime_swatch_buttons = _populate_palette_grid(slime_grid, PLAYER_SCRIPT.slime_palette_options(), true)

	var bullet_section := _make_section_box(rows, "customize_bullet_color", "CustomizeBullet")
	var bullet_grid := _make_palette_grid()
	bullet_section.add_child(bullet_grid)
	_bullet_swatch_buttons = _populate_palette_grid(bullet_grid, PLAYER_SCRIPT.bullet_palette_options(), false)

	var back_button := _make_button(_t("customize_back"), Vector2(320.0, 44.0), true)
	_register_localized_text(back_button, "customize_back")
	back_button.pressed.connect(_on_customize_back_pressed)
	rows.add_child(back_button)

	_refresh_customize_controls()


func _create_game_page() -> void:
	_game_page = _make_page("GamePage")

	_screen_flash_rect = ColorRect.new()
	_screen_flash_rect.name = "ImpactFlash"
	_screen_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen_flash_rect.color = Color(1.0, 1.0, 1.0, 0.0)
	_screen_flash_rect.visible = false
	_screen_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_game_page.add_child(_screen_flash_rect)

	_battle_hud = BATTLE_HUD_SCRIPT.new() as Control
	_battle_hud.name = "BattleHud"
	_battle_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_battle_hud.call("set_locale", _current_locale())
	_battle_hud.connect("restart_requested", Callable(self, "_on_restart_requested"))
	_battle_hud.connect("leave_requested", Callable(self, "_on_leave_game_pressed"))
	_game_page.add_child(_battle_hud)

	_buff_panel = BUFF_PANEL_SCRIPT.new() as Control
	_buff_panel.name = "BuffPanel"
	_buff_panel.call("set_locale", _current_locale())
	_buff_panel.connect("option_chosen", Callable(self, "_on_buff_option_chosen"))
	_game_page.add_child(_buff_panel)

	_create_expression_wheel()

	_pause_panel = PAUSE_PANEL_SCRIPT.new() as Control
	_pause_panel.name = "PausePanel"
	_pause_panel.call("set_locale", _current_locale())
	_pause_panel.connect("resume_requested", Callable(self, "_close_pause_menu"))
	_pause_panel.connect("main_menu_requested", Callable(self, "_on_pause_main_menu_requested"))
	_game_page.add_child(_pause_panel)


func _create_records_panel() -> void:
	_records_panel = RECORDS_PANEL_SCRIPT.new() as Control
	_records_panel.name = "RecordsPanel"
	_records_panel.call("set_locale", _current_locale())
	_refresh_records_panel()
	_ui_root.add_child(_records_panel)


func _create_steam_invite_confirm_panel() -> void:
	_steam_invite_confirm_panel = Control.new()
	_steam_invite_confirm_panel.name = "SteamInviteConfirmPanel"
	_steam_invite_confirm_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_steam_invite_confirm_panel.visible = false
	_ui_root.add_child(_steam_invite_confirm_panel)
	_steam_invite_confirm_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var dimmer := ColorRect.new()
	dimmer.name = "Dimmer"
	dimmer.color = Color(0.01, 0.02, 0.02, 0.58)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_steam_invite_confirm_panel.add_child(dimmer)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.name = "CenterContainer"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_steam_invite_confirm_panel.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_steam_invite_confirm_card = PanelContainer.new()
	_steam_invite_confirm_card.name = "SteamInviteConfirmCard"
	_steam_invite_confirm_card.custom_minimum_size = Vector2(390.0, 260.0)
	UI_STYLE_SCRIPT.apply_panel(_steam_invite_confirm_card, "hero")
	center.add_child(_steam_invite_confirm_card)
	_steam_invite_confirm_card.resized.connect(func() -> void:
		_steam_invite_confirm_card.pivot_offset = _steam_invite_confirm_card.size * 0.5
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 22)
	_steam_invite_confirm_card.add_child(margin)

	var rows := VBoxContainer.new()
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", 14)
	margin.add_child(rows)

	_steam_invite_confirm_title_label = _make_title_label(_t("steam_invite_confirm_title"))
	_steam_invite_confirm_title_label.name = "SteamInviteConfirmTitle"
	_register_localized_text(_steam_invite_confirm_title_label, "steam_invite_confirm_title")
	_steam_invite_confirm_title_label.add_theme_font_size_override("font_size", 26)
	rows.add_child(_steam_invite_confirm_title_label)

	_steam_invite_confirm_body_label = _make_body_label("")
	_steam_invite_confirm_body_label.name = "SteamInviteConfirmBody"
	_steam_invite_confirm_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_steam_invite_confirm_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_steam_invite_confirm_body_label)

	_steam_invite_confirm_accept_button = _make_button(_t("steam_invite_confirm_accept"), Vector2(260.0, 46.0), true)
	_steam_invite_confirm_accept_button.name = "SteamInviteConfirmAccept"
	_register_localized_text(_steam_invite_confirm_accept_button, "steam_invite_confirm_accept")
	_steam_invite_confirm_accept_button.pressed.connect(_on_steam_invite_confirm_accept_pressed)
	rows.add_child(_steam_invite_confirm_accept_button)

	_steam_invite_confirm_cancel_button = _make_button(_t("steam_invite_confirm_cancel"), Vector2(260.0, 42.0))
	_steam_invite_confirm_cancel_button.name = "SteamInviteConfirmCancel"
	_register_localized_text(_steam_invite_confirm_cancel_button, "steam_invite_confirm_cancel")
	_steam_invite_confirm_cancel_button.pressed.connect(_on_steam_invite_confirm_cancel_pressed)
	rows.add_child(_steam_invite_confirm_cancel_button)

	_refresh_steam_invite_confirm_text()


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
	parent.add_child(center, true)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.custom_minimum_size = minimum_size
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	UI_STYLE_SCRIPT.apply_panel(panel, variant)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "MarginContainer"
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin, true)

	var rows := VBoxContainer.new()
	rows.name = "VBoxContainer"
	rows.add_theme_constant_override("separation", 10)
	margin.add_child(rows, true)
	return rows


func _make_section_box(parent: Control, title_key: String, section_name: String = "") -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = "%sSection" % (section_name if section_name != "" else title_key)
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

	var title := _make_kicker_label(_t(title_key))
	_register_localized_text(title, title_key)
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


func _make_palette_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return grid


func _populate_palette_grid(grid: GridContainer, palettes: Array[Dictionary], slime_palette: bool) -> Array[Button]:
	var buttons: Array[Button] = []
	for index in range(palettes.size()):
		var palette := palettes[index]
		var swatch_color: Color = palette["fill"]
		var button := _make_swatch_button(swatch_color, false)
		button.name = "%sSwatch%d" % ["Slime" if slime_palette else "Bullet", index]
		if slime_palette:
			button.pressed.connect(_on_slime_palette_selected.bind(index))
		else:
			button.pressed.connect(_on_bullet_palette_selected.bind(index))
		grid.add_child(button)
		buttons.append(button)
	return buttons


func _make_swatch_button(swatch_color: Color, selected: bool) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(74.0, 42.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.text = ""
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Color(0.02, 0.05, 0.05, 0.96))
	_apply_swatch_style(button, swatch_color, selected)
	_wire_button_motion(button, false)
	return button


func _apply_swatch_style(button: Button, swatch_color: Color, selected: bool) -> void:
	var normal := _swatch_stylebox(swatch_color, selected, 1.0)
	var hover := _swatch_stylebox(swatch_color.lightened(0.12), selected, 1.0)
	var pressed := _swatch_stylebox(swatch_color.darkened(0.10), selected, 1.0)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.text = "✓" if selected else ""


func _swatch_stylebox(swatch_color: Color, selected: bool, alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(swatch_color.r, swatch_color.g, swatch_color.b, alpha)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.border_width_left = 3 if selected else 1
	style.border_width_top = 3 if selected else 1
	style.border_width_right = 3 if selected else 1
	style.border_width_bottom = 3 if selected else 1
	style.border_color = UI_STYLE_SCRIPT.AMBER_COLOR if selected else Color(0.95, 1.0, 0.84, 0.42)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.28)
	style.shadow_size = 5
	return style


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


func _current_locale() -> String:
	if _settings == null:
		return LAB_LOCALE_SCRIPT.LOCALE_EN
	return String(_settings.get("locale"))


func _best_survival_seconds(category: int) -> float:
	if _save == null:
		return 0.0
	return float(_save.call("best_survival_seconds", category))


func _record_category_for_play_mode(play_mode: PlayMode) -> int:
	match play_mode:
		PlayMode.SINGLE:
			return LAB_SAVE_SCRIPT.RecordCategory.SINGLE
		PlayMode.COUCH, PlayMode.STEAM_HOST, PlayMode.STEAM_CLIENT:
			return LAB_SAVE_SCRIPT.RecordCategory.MULTIPLAYER
		_:
			return -1


func _refresh_records_panel() -> void:
	if _records_panel == null:
		return
	_records_panel.call(
		"set_survival_records",
		_best_survival_seconds(LAB_SAVE_SCRIPT.RecordCategory.SINGLE),
		_best_survival_seconds(LAB_SAVE_SCRIPT.RecordCategory.MULTIPLAYER)
	)


func _t(key: String, args: Dictionary = {}) -> String:
	return LAB_LOCALE_SCRIPT.text(_current_locale(), key, args)


func _register_localized_text(control: Control, key: String) -> void:
	if control == null:
		return
	control.set_meta("lab_locale_key", key)
	if not _localized_text_controls.has(control):
		_localized_text_controls.append(control)
	_apply_localized_text(control)


func _register_localized_placeholder(control: Control, key: String) -> void:
	if control == null:
		return
	control.set_meta("lab_placeholder_key", key)
	if not _localized_placeholder_controls.has(control):
		_localized_placeholder_controls.append(control)
	_apply_localized_placeholder(control)


func _apply_localized_text(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	var key := String(control.get_meta("lab_locale_key", ""))
	if key == "":
		return
	var value := _t(key)
	if control is Label:
		var label := control as Label
		label.text = value
	elif control is Button:
		var button := control as Button
		button.text = value


func _apply_localized_placeholder(control: Control) -> void:
	if control == null or not is_instance_valid(control):
		return
	var key := String(control.get_meta("lab_placeholder_key", ""))
	if key == "":
		return
	if control is LineEdit:
		var line_edit := control as LineEdit
		line_edit.placeholder_text = _t(key)


func _apply_locale() -> void:
	for control in _localized_text_controls:
		_apply_localized_text(control)
	for control in _localized_placeholder_controls:
		_apply_localized_placeholder(control)
	_refresh_language_option()
	_refresh_resolution_option()
	_refresh_customize_controls()
	_refresh_steam_invite_confirm_text()
	if _battle_hud != null:
		_battle_hud.call("set_locale", _current_locale())
	if _buff_panel != null:
		_buff_panel.call("set_locale", _current_locale())
	if _pause_panel != null:
		_pause_panel.call("set_locale", _current_locale())
	if _records_panel != null:
		_records_panel.call("set_locale", _current_locale())
		_refresh_records_panel()
	for peer_id in _players.keys():
		var player := _players[peer_id] as Node
		if player != null and is_instance_valid(player):
			player.call("set_locale", _current_locale())
	if _single_ai_active():
		var ai_appearance: Dictionary = _single_ai_teammate.call("appearance_state")
		_single_ai_teammate.call("set_locale", _current_locale())
		_single_ai_teammate.call(
			"apply_appearance",
			_t("ai_ally_name"),
			int(ai_appearance.get("slime_palette_id", 0)),
			int(ai_appearance.get("bullet_palette_id", 0))
		)
	for merge_id in _active_merges.keys():
		var merge: Dictionary = _active_merges[merge_id]
		var node := merge.get("node") as Node
		if node != null and is_instance_valid(node):
			node.call("set_locale", _current_locale())
	if _expression_wheel != null:
		_expression_wheel.call("set_options", _localized_expressions())
	_update_status()
	_refresh_battle_hud()


func _refresh_language_option() -> void:
	if _language_option == null:
		return
	var locales: Array[String] = LAB_LOCALE_SCRIPT.supported_locales()
	var selected_index := 0
	_language_option.clear()
	for index in range(locales.size()):
		var locale := locales[index]
		_language_option.add_item(LAB_LOCALE_SCRIPT.language_label(locale, _current_locale()), index)
		if locale == _current_locale():
			selected_index = index
	_language_option.select(selected_index)
	if _fullscreen_check != null:
		_fullscreen_check.button_pressed = bool(_settings.get("fullscreen"))


func _refresh_resolution_option() -> void:
	if _resolution_option == null or _settings == null:
		return
	var options: Array[Dictionary] = LAB_SETTINGS_SCRIPT.resolution_options()
	var selected_id := int(_settings.get("resolution_preset_id"))
	var selected_index := 0
	_resolution_option.clear()
	for index in range(options.size()):
		var option := options[index]
		var option_id := int(option.get("id", index))
		var label_key := String(option.get("label_key", ""))
		_resolution_option.add_item(_t(label_key), option_id)
		if option_id == selected_id:
			selected_index = index
	_resolution_option.select(selected_index)


func _refresh_customize_controls() -> void:
	if _settings == null:
		return
	_customize_refreshing = true
	if _customize_name_input != null:
		_customize_name_input.text = String(_settings.get("player_name"))
	var slime_palette_id := PLAYER_SCRIPT.normalized_slime_palette_id(int(_settings.get("slime_palette_id")))
	var bullet_palette_id := PLAYER_SCRIPT.normalized_bullet_palette_id(int(_settings.get("bullet_palette_id")))
	_refresh_swatch_buttons(_slime_swatch_buttons, PLAYER_SCRIPT.slime_palette_options(), slime_palette_id)
	_refresh_swatch_buttons(_bullet_swatch_buttons, PLAYER_SCRIPT.bullet_palette_options(), bullet_palette_id)
	_refresh_customize_preview()
	_customize_refreshing = false


func _refresh_customize_preview() -> void:
	if _customize_preview_name_label != null and is_instance_valid(_customize_preview_name_label):
		var preview_name := ""
		if _settings != null:
			preview_name = String(_settings.get("player_name")).strip_edges()
		_customize_preview_name_label.text = preview_name
		_customize_preview_name_label.visible = preview_name != ""
		if _customize_preview_area != null and is_instance_valid(_customize_preview_area):
			_customize_preview_name_label.position = Vector2(0.0, 8.0)
			_customize_preview_name_label.size = Vector2(_customize_preview_area.size.x, 28.0)
	if _customize_preview_area != null and is_instance_valid(_customize_preview_area):
		if _customize_preview_body == null or not is_instance_valid(_customize_preview_body):
			return
		_customize_preview_body.position = Vector2(_customize_preview_area.size.x * 0.5, _customize_preview_area.size.y - 52.0)
		_customize_preview_body.call("warp_to", _customize_preview_body.global_position)
	if _customize_preview_body == null or not is_instance_valid(_customize_preview_body):
		return
	var slime_palette_id := 0
	if _settings != null:
		slime_palette_id = int(_settings.get("slime_palette_id"))
	var palette := PLAYER_SCRIPT.slime_palette(slime_palette_id)
	_customize_preview_body.call("set_palette", palette["fill"], palette["edge"], palette["core"])


func _update_customize_preview(delta: float) -> void:
	if _screen != SCREEN_CUSTOMIZE:
		return
	_prune_customize_preview_bullets()
	_customize_preview_fire_timer -= delta
	if _customize_preview_fire_timer <= 0.0:
		_fire_customize_preview_bullet()


func _fire_customize_preview_bullet() -> void:
	if _customize_preview_area == null or not is_instance_valid(_customize_preview_area):
		return
	if _customize_preview_body == null or not is_instance_valid(_customize_preview_body):
		return
	var bullet_palette_id := 0
	if _settings != null:
		bullet_palette_id = int(_settings.get("bullet_palette_id"))
	var palette := PLAYER_SCRIPT.bullet_palette_option(bullet_palette_id)
	var origin: Vector2 = _customize_preview_body.call("emit_surface_bud", Vector2.UP)
	var bullet := BULLET_SCRIPT.new() as Node2D
	bullet.name = "CustomizePreviewBullet%d" % (_customize_preview_bullets.size() + 1)
	_customize_preview_area.add_child(bullet)
	bullet.call(
		"configure",
		origin,
		Vector2.UP,
		palette["fill"],
		palette["edge"],
		CUSTOMIZE_PREVIEW_BULLET_SPEED
	)
	_customize_preview_bullets.append(bullet)
	_customize_preview_fire_timer = CUSTOMIZE_PREVIEW_FIRE_INTERVAL


func _prune_customize_preview_bullets() -> void:
	var live_bullets: Array[Node] = []
	for bullet in _customize_preview_bullets:
		if bullet == null or not is_instance_valid(bullet) or bullet.is_queued_for_deletion():
			continue
		if _customize_preview_area != null and is_instance_valid(_customize_preview_area):
			var bullet_node := bullet as Node2D
			var local_position: Vector2 = bullet_node.global_position - _customize_preview_area.global_position
			if local_position.y < -32.0:
				bullet.queue_free()
				continue
		live_bullets.append(bullet)
	_customize_preview_bullets = live_bullets


func _clear_customize_preview_bullets() -> void:
	for bullet in _customize_preview_bullets:
		if bullet != null and is_instance_valid(bullet):
			bullet.queue_free()
	_customize_preview_bullets.clear()
	_customize_preview_fire_timer = 0.0


func _refresh_swatch_buttons(buttons: Array[Button], palettes: Array[Dictionary], selected_id: int) -> void:
	for index in range(buttons.size()):
		var button := buttons[index]
		if button == null or not is_instance_valid(button) or index >= palettes.size():
			continue
		var palette := palettes[index]
		var swatch_color: Color = palette["fill"]
		_apply_swatch_style(button, swatch_color, index == selected_id)


func _localized_expressions() -> Array[Dictionary]:
	var localized: Array[Dictionary] = []
	for expression in ACTIVE_EXPRESSIONS:
		var row: Dictionary = expression.duplicate(true)
		row["label"] = _t(String(row.get("label_key", "")))
		localized.append(row)
	return localized


func _localized_buff_def(definition: Dictionary) -> Dictionary:
	var localized := definition.duplicate(true)
	var name_key := String(localized.get("name_key", ""))
	if name_key != "":
		localized["name"] = _t(name_key)
	var desc_key := String(localized.get("desc_key", ""))
	if desc_key != "":
		localized["desc"] = _t(desc_key)
	return localized


func _waiting_text(pending_count: int = -1) -> String:
	if pending_count > 0:
		return _t("buff_waiting_count", {"count": pending_count})
	return _t("buff_waiting")


func _create_expression_wheel() -> void:
	_expression_wheel = EXPRESSION_WHEEL_SCRIPT.new() as Control
	_expression_wheel.name = "ExpressionWheel"
	_expression_wheel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_expression_wheel.call("set_options", _localized_expressions())
	_game_page.add_child(_expression_wheel)


func _show_start_page() -> void:
	_set_screen(SCREEN_START)


func _show_multiplayer_page() -> void:
	_set_screen(SCREEN_MULTIPLAYER)


func _show_settings_page(return_screen: String = SCREEN_START) -> void:
	_settings_return_screen = return_screen
	_set_screen(SCREEN_SETTINGS)


func _show_customize_page() -> void:
	_set_screen(SCREEN_CUSTOMIZE)
	_refresh_customize_controls()
	_clear_customize_preview_bullets()
	_fire_customize_preview_bullet()


func _show_game_page() -> void:
	_set_screen(SCREEN_GAME)


func _set_screen(screen_name: String) -> void:
	if screen_name != SCREEN_GAME:
		_close_pause_menu()
	if screen_name != SCREEN_START and _records_panel != null and bool(_records_panel.call("is_open")):
		_records_panel.call("close")
	var previous_page := _page_for_screen(_screen)
	var next_page := _page_for_screen(screen_name)
	_screen = screen_name
	_transition_to_page(previous_page, next_page)
	if screen_name != SCREEN_GAME and _expression_wheel != null:
		_expression_wheel.call("close")
	if screen_name != SCREEN_GAME:
		_clear_local_input_state()
		_clear_screen_fx()
	if screen_name != SCREEN_CUSTOMIZE:
		_clear_customize_preview_bullets()
	queue_redraw()


func _page_for_screen(screen_name: String) -> Control:
	match screen_name:
		SCREEN_START:
			return _start_page
		SCREEN_MULTIPLAYER:
			return _multiplayer_page
		SCREEN_SETTINGS:
			return _settings_page
		SCREEN_CUSTOMIZE:
			return _customize_page
		SCREEN_GAME:
			return _game_page
		_:
			return null


func _transition_to_page(previous_page: Control, next_page: Control) -> void:
	if next_page == null:
		return
	if _ui_transition_tween != null and _ui_transition_tween.is_valid():
		_ui_transition_tween.kill()
	if DisplayServer.get_name().to_lower() == "headless":
		_show_page_immediate(next_page)
		return

	if previous_page == null or previous_page == next_page or not previous_page.visible:
		_show_page_immediate(next_page)
		return

	for page in _all_pages():
		if page == null or page == previous_page or page == next_page:
			continue
		page.visible = false
		page.modulate.a = 0.0
		page.position = Vector2.ZERO
		page.scale = Vector2.ONE

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
	_ui_transition_tween.finished.connect(_finish_page_transition.bind(previous_page, next_page), CONNECT_ONE_SHOT)


func _show_page_immediate(next_page: Control) -> void:
	for page in _all_pages():
		var control := page
		if control == null:
			continue
		control.visible = control == next_page
		control.modulate.a = 1.0 if control == next_page else 0.0
		control.position = Vector2.ZERO
		control.scale = Vector2.ONE


func _finish_page_transition(previous_page: Control, next_page: Control) -> void:
	for page in _all_pages():
		if page == null or page == next_page:
			continue
		page.visible = false
		page.modulate.a = 0.0
		page.position = Vector2.ZERO
		page.scale = Vector2.ONE
	if next_page != null:
		next_page.visible = true
		next_page.modulate.a = 1.0
		next_page.position = Vector2.ZERO
		next_page.scale = Vector2.ONE


func _open_steam_invite_confirm() -> void:
	if _steam_invite_confirm_panel == null:
		return
	if _steam_invite_confirm_tween != null and _steam_invite_confirm_tween.is_valid():
		_steam_invite_confirm_tween.kill()
	_steam_invite_confirm_panel.visible = true
	_steam_invite_confirm_panel.modulate.a = 1.0
	if _steam_invite_confirm_card != null:
		_steam_invite_confirm_card.modulate.a = 0.0
		_steam_invite_confirm_card.scale = Vector2(0.92, 0.92)
		_steam_invite_confirm_card.pivot_offset = _steam_invite_confirm_card.size * 0.5
	if DisplayServer.get_name().to_lower() == "headless":
		if _steam_invite_confirm_card != null:
			_steam_invite_confirm_card.modulate.a = 1.0
			_steam_invite_confirm_card.scale = Vector2.ONE
		return
	_steam_invite_confirm_tween = create_tween()
	_steam_invite_confirm_tween.set_parallel(true)
	if _steam_invite_confirm_card != null:
		_steam_invite_confirm_tween.tween_property(_steam_invite_confirm_card, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_steam_invite_confirm_tween.tween_property(_steam_invite_confirm_card, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _close_steam_invite_confirm() -> void:
	if _steam_invite_confirm_panel == null or not _steam_invite_confirm_panel.visible:
		return
	if _steam_invite_confirm_tween != null and _steam_invite_confirm_tween.is_valid():
		_steam_invite_confirm_tween.kill()
	if DisplayServer.get_name().to_lower() == "headless":
		_steam_invite_confirm_panel.visible = false
		return
	_steam_invite_confirm_tween = create_tween()
	_steam_invite_confirm_tween.set_parallel(true)
	if _steam_invite_confirm_card != null:
		_steam_invite_confirm_tween.tween_property(_steam_invite_confirm_card, "modulate:a", 0.0, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_steam_invite_confirm_tween.tween_property(_steam_invite_confirm_card, "scale", Vector2(0.96, 0.96), 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_steam_invite_confirm_tween.chain().tween_callback(func() -> void:
		if _steam_invite_confirm_panel != null:
			_steam_invite_confirm_panel.visible = false
	)


func _refresh_steam_invite_confirm_text() -> void:
	if _steam_invite_confirm_body_label == null:
		return
	var lobby_text := _pending_steam_invite_lobby_id if _pending_steam_invite_lobby_id != "" else "-"
	_steam_invite_confirm_body_label.text = _t("steam_invite_confirm_body", {"lobby": lobby_text})


func _all_pages() -> Array[Control]:
	return [_start_page, _multiplayer_page, _settings_page, _customize_page, _game_page]


func _can_open_pause_menu() -> bool:
	if _screen != SCREEN_GAME or _director == null:
		return false
	if not _battle_active():
		return false
	return true


func _open_pause_menu() -> void:
	if _pause_menu_open or not _can_open_pause_menu():
		return
	_pause_menu_open = true
	_pause_freezes_game = not _multiplayer_session_active()
	_release_all_local_actions()
	if _expression_wheel != null and bool(_expression_wheel.call("is_open")):
		_expression_wheel.call("close")
	if _pause_freezes_game:
		_set_battle_pause_frozen(true)
	if _pause_panel != null:
		_pause_panel.call("open")
	_freeze_player_inputs()
	_refresh_battle_hud()


func _close_pause_menu() -> void:
	if _controller_reconnect_blocked:
		return
	if not _pause_menu_open:
		if _pause_panel != null and bool(_pause_panel.call("is_open")):
			_pause_panel.call("close")
		return
	if _pause_freezes_game:
		_set_battle_pause_frozen(false)
	_pause_menu_open = false
	_pause_freezes_game = false
	_release_all_local_actions()
	if _pause_panel != null:
		_pause_panel.call("close")
	_refresh_battle_hud()


func _pause_blocks_gameplay_tick() -> bool:
	return _pause_menu_open and _pause_freezes_game


func _set_battle_pause_frozen(frozen: bool) -> void:
	if _director != null:
		_director.call("set_battle_frozen", frozen)
	set_player_bullets_frozen(frozen)
	_sync_player_battle_timers(not frozen)


func _multiplayer_session_active() -> bool:
	return (
		_play_mode == PlayMode.STEAM_HOST
		or _play_mode == PlayMode.STEAM_CLIENT
	) and _session != null and String(_session.call("active_transport")) != "offline"


func _local_fallback_name() -> String:
	if not _multiplayer_session_active():
		return ""
	if bool(_session.call("is_host")):
		return "Host"
	return "Peer %d" % int(_session.call("local_peer_id"))


func _local_appearance(fallback_name: String = "") -> Dictionary:
	if _settings == null:
		return _sanitize_appearance({}, fallback_name)
	var appearance: Dictionary = _settings.call("appearance_settings")
	return _sanitize_appearance(appearance, fallback_name)


func _appearance_for_peer(peer_id: int, fallback_name: String = "") -> Dictionary:
	if _peer_appearances.has(peer_id):
		return _sanitize_appearance(_peer_appearances[peer_id], fallback_name)
	if peer_id == int(_session.call("local_peer_id")):
		return _local_appearance(fallback_name)
	return _sanitize_appearance({
		"name": fallback_name,
		"slime_palette_id": peer_id,
		"bullet_palette_id": peer_id,
	}, fallback_name)


func _sanitize_appearance(raw_appearance: Variant, fallback_name: String = "") -> Dictionary:
	var data: Dictionary = {}
	if raw_appearance is Dictionary:
		data = raw_appearance
	var display_name := String(data.get("name", "")).strip_edges()
	if display_name == "":
		display_name = fallback_name
	if display_name.length() > int(LAB_SETTINGS_SCRIPT.MAX_PLAYER_NAME_LENGTH):
		display_name = display_name.substr(0, int(LAB_SETTINGS_SCRIPT.MAX_PLAYER_NAME_LENGTH))
	return {
		"name": display_name,
		"slime_palette_id": PLAYER_SCRIPT.normalized_slime_palette_id(int(data.get("slime_palette_id", 0))),
		"bullet_palette_id": PLAYER_SCRIPT.normalized_bullet_palette_id(int(data.get("bullet_palette_id", 0))),
	}


func _apply_appearance_to_player(peer_id: int, appearance: Dictionary, fallback_name: String = "") -> Dictionary:
	var clean_appearance := _sanitize_appearance(appearance, fallback_name)
	_peer_appearances[peer_id] = clean_appearance
	var player := _players.get(peer_id) as Node
	if player != null and is_instance_valid(player):
		player.call(
			"apply_appearance",
			String(clean_appearance.get("name", "")),
			int(clean_appearance.get("slime_palette_id", 0)),
			int(clean_appearance.get("bullet_palette_id", 0))
		)
	return clean_appearance


func _apply_local_appearance(send_to_host: bool) -> void:
	if _session == null:
		return
	var local_id := int(_session.call("local_peer_id"))
	var appearance := _local_appearance(_local_fallback_name())
	_apply_appearance_to_player(local_id, appearance, _local_fallback_name())
	if send_to_host and _multiplayer_session_active():
		_session.call("send_appearance_to_host", appearance)


func _on_pause_main_menu_requested() -> void:
	_close_pause_menu()
	_on_leave_game_pressed()


func _on_start_single_player_pressed() -> void:
	_begin_single_player()


func _on_start_multiplayer_pressed() -> void:
	_disable_couch_mode()
	_play_mode = PlayMode.MENU
	_leave_session_without_navigation()
	_clear_players()
	_clear_bullets()
	_peer_inputs.clear()
	_show_multiplayer_page()
	_append_log(_t("log_multiplayer_setup"))


func _on_settings_pressed() -> void:
	_show_settings_page(_screen)


func _on_customize_pressed() -> void:
	_show_customize_page()


func _on_exit_pressed() -> void:
	get_tree().quit()


func _on_records_pressed() -> void:
	if _records_panel == null:
		return
	_records_panel.call(
		"open",
		_best_survival_seconds(LAB_SAVE_SCRIPT.RecordCategory.SINGLE),
		_best_survival_seconds(LAB_SAVE_SCRIPT.RecordCategory.MULTIPLAYER)
	)


func _on_settings_back_pressed() -> void:
	_set_screen(_settings_return_screen)


func _on_customize_back_pressed() -> void:
	_show_start_page()


func _on_language_selected(index: int) -> void:
	var locales: Array[String] = LAB_LOCALE_SCRIPT.supported_locales()
	if index < 0 or index >= locales.size():
		return
	if _settings.call("set_locale", locales[index]):
		_settings.call("save_settings")
	_apply_locale()


func _on_fullscreen_toggled(enabled: bool) -> void:
	if _settings.call("set_fullscreen", enabled):
		_settings.call("save_settings")
	_settings.call("apply_fullscreen")


func _on_resolution_selected(index: int) -> void:
	if _resolution_option == null or index < 0 or index >= _resolution_option.item_count:
		return
	var preset_id := _resolution_option.get_item_id(index)
	if _settings.call("set_resolution_preset_id", preset_id):
		_settings.call("save_settings")
	_settings.call("apply_fullscreen")
	_sync_world_rect()


func _on_customize_name_changed(new_text: String) -> void:
	if _customize_refreshing:
		return
	_settings.call("set_player_name", new_text)
	_settings.call("save_settings")
	_refresh_customize_preview()
	_apply_local_appearance(true)


func _on_slime_palette_selected(palette_id: int) -> void:
	_settings.call("set_slime_palette_id", palette_id)
	_settings.call("save_settings")
	_refresh_customize_controls()
	_apply_local_appearance(true)


func _on_bullet_palette_selected(palette_id: int) -> void:
	_settings.call("set_bullet_palette_id", palette_id)
	_settings.call("save_settings")
	_refresh_customize_controls()
	_clear_customize_preview_bullets()
	if _screen == SCREEN_CUSTOMIZE:
		_fire_customize_preview_bullet()
	_apply_local_appearance(true)


func _begin_single_player() -> void:
	_leave_session_without_navigation()
	_disable_couch_mode()
	_play_mode = PlayMode.SINGLE
	_clear_players()
	_clear_bullets()
	_peer_inputs.clear()
	var player: Node = _ensure_player(1, "")
	_apply_local_appearance(false)
	player.call("warp_to", _spawn_position_for_slot(0))
	player.call("set_local_or_host_simulated", true)
	_start_battle()
	_show_game_page()
	_append_log(_t("log_single_player_started"))


func _on_start_couch_pressed() -> void:
	_leave_session_without_navigation()
	_clear_players()
	_clear_bullets()
	_peer_inputs.clear()
	_clear_local_input_state()
	_play_mode = PlayMode.COUCH
	_local_input_router.call("enable_lobby")
	_sync_couch_roster(_local_input_router.call("slots"))
	_show_multiplayer_page()
	_append_log(_t("log_couch_ready"))


func _on_host_steam_pressed() -> void:
	_disable_couch_mode()
	_play_mode = PlayMode.MENU
	_clear_players()
	_clear_bullets()
	_peer_inputs.clear()
	_session.call("host_steam")


func _on_invite_steam_pressed() -> void:
	if String(_session.call("active_transport")) != "steam":
		_disable_couch_mode()
		_play_mode = PlayMode.MENU
		_clear_players()
		_clear_bullets()
		_peer_inputs.clear()
	_session.call("invite_steam_friend")


func _on_join_steam_pressed() -> void:
	_disable_couch_mode()
	_play_mode = PlayMode.MENU
	_clear_players()
	_clear_bullets()
	_peer_inputs.clear()
	_session.call("join_steam_lobby", _lobby_input.text)


func _on_ready_start_battle_pressed() -> void:
	if _play_mode == PlayMode.COUCH:
		if _players.size() < 2:
			_append_log(_t("log_need_two_players"))
			return
		_local_input_router.call("lock_roster")
		_start_battle()
		_show_game_page()
		_append_log(_t("log_battle_launch"))
		return
	if _session == null or not bool(_session.call("is_host")):
		return
	if _players.size() < 2:
		_append_log(_t("log_need_two_players"))
		return
	_start_battle()
	_show_game_page()
	_session.call("broadcast_battle_launch")
	_append_log(_t("log_battle_launch"))


func _on_multiplayer_leave_pressed() -> void:
	_disable_couch_mode()
	_play_mode = PlayMode.MENU
	_session.call("leave_session")
	_end_battle()
	_clear_players()
	_clear_bullets()
	_peer_inputs.clear()
	_show_multiplayer_page()
	_append_log(_t("log_session_left"))


func _on_multiplayer_back_pressed() -> void:
	_disable_couch_mode()
	_play_mode = PlayMode.MENU
	_leave_session_without_navigation()
	_clear_players()
	_clear_bullets()
	_peer_inputs.clear()
	_show_start_page()


func _on_leave_game_pressed() -> void:
	_disable_couch_mode()
	_play_mode = PlayMode.MENU
	_leave_session_without_navigation()
	_end_battle()
	_clear_players()
	_clear_bullets()
	_peer_inputs.clear()
	_show_start_page()
	_append_log(_t("log_returned_start"))


func _on_restart_requested() -> void:
	if _director == null or not bool(_director.call("is_authority")):
		return
	_reset_battle()
	if bool(_session.call("is_host")):
		_session.call("broadcast_battle_reset")
	_append_log(_t("log_battle_restarted"))


func _leave_session_without_navigation() -> void:
	if _session == null:
		return
	_suppress_session_end_navigation = true
	_session.call("leave_session")
	_suppress_session_end_navigation = false


func _on_steam_invite_join_requested(lobby_id: String) -> void:
	var clean_lobby_id := lobby_id.strip_edges()
	if not clean_lobby_id.is_valid_int():
		_append_log("Steam invite ignored: invalid lobby id.")
		return
	if _pending_steam_invite_lobby_id != "":
		_append_log("Steam invite ignored: another invite is pending.")
		return
	if _can_join_steam_invite_immediately():
		_join_steam_lobby_from_invite(clean_lobby_id)
		return
	_pending_steam_invite_lobby_id = clean_lobby_id
	_refresh_steam_invite_confirm_text()
	_open_steam_invite_confirm()


func _can_join_steam_invite_immediately() -> bool:
	if _session == null:
		return false
	if String(_session.call("active_transport")) != "offline":
		return false
	return _screen == SCREEN_START or _screen == SCREEN_MULTIPLAYER


func _join_steam_lobby_from_invite(lobby_id: String) -> void:
	if _session == null:
		return
	if not lobby_id.is_valid_int():
		_append_log("Steam invite ignored: invalid lobby id.")
		return
	if not bool(_session.call("steam_available")):
		_append_log(String(_session.call("steam_status_text")))
		return
	_disable_couch_mode()
	_play_mode = PlayMode.MENU
	_close_pause_menu()
	_end_battle()
	_clear_players()
	_clear_bullets()
	_peer_inputs.clear()
	_show_multiplayer_page()
	_session.call("join_steam_lobby", lobby_id)


func _on_steam_invite_confirm_accept_pressed() -> void:
	var lobby_id := _pending_steam_invite_lobby_id
	_pending_steam_invite_lobby_id = ""
	_close_steam_invite_confirm()
	_join_steam_lobby_from_invite(lobby_id)


func _on_steam_invite_confirm_cancel_pressed() -> void:
	_pending_steam_invite_lobby_id = ""
	_close_steam_invite_confirm()


func _on_session_started(host: bool, transport: String, lobby_id: String) -> void:
	_play_mode = PlayMode.STEAM_HOST if host else PlayMode.STEAM_CLIENT
	if host:
		var host_player: Node = _ensure_player(1, "Host")
		_peer_merge_intents[1] = false
		_apply_local_appearance(true)
		host_player.call("warp_to", _spawn_position_for_slot(0))
		host_player.call("set_local_or_host_simulated", true)
		_append_log(_t("log_ready_room_created"))
	else:
		_apply_local_appearance(true)
		_append_log(_t("log_ready_room_joined"))
	if lobby_id != "" and _lobby_input != null:
		_lobby_input.text = lobby_id
	_show_multiplayer_page()
	_append_log(_t("log_session_ready", {
		"transport": transport,
		"role": _t("log_role_host") if host else _t("log_role_client"),
	}))


func _on_session_ended() -> void:
	if _play_mode == PlayMode.STEAM_HOST or _play_mode == PlayMode.STEAM_CLIENT:
		_play_mode = PlayMode.MENU
	if not _suppress_session_end_navigation and _screen == SCREEN_GAME:
		_end_battle()
		_clear_players()
		_clear_bullets()
		_clear_merges()
		_peer_inputs.clear()
		_peer_merge_intents.clear()
		_show_multiplayer_page()
	_update_status()


func _on_peer_joined(peer_id: int) -> void:
	if not bool(_session.call("is_host")):
		return
	var player: Node = _ensure_player(peer_id, "Peer %d" % peer_id)
	player.call("set_local_or_host_simulated", true)
	_peer_inputs[peer_id] = Vector2.ZERO
	_peer_merge_intents[peer_id] = false
	if _screen == SCREEN_GAME:
		_session.call("send_battle_launch", peer_id)


func _on_appearance_received(peer_id: int, appearance: Dictionary) -> void:
	if not bool(_session.call("is_host")):
		return
	var fallback_name := "Host" if peer_id == 1 else "Peer %d" % peer_id
	_apply_appearance_to_player(peer_id, appearance, fallback_name)


func _on_peer_left(peer_id: int) -> void:
	_end_merges_for_peer(peer_id, false)
	_remove_player(peer_id)
	_peer_inputs.erase(peer_id)
	_peer_merge_intents.erase(peer_id)
	_merge_intent_order.erase(peer_id)
	_merge_cooldowns.erase(peer_id)
	if _director != null:
		_director.call("notify_peer_left", peer_id)


func _on_input_received(peer_id: int, input_vector: Vector2) -> void:
	if not bool(_session.call("is_host")):
		return
	_peer_inputs[peer_id] = input_vector


func _on_merge_intent_received(peer_id: int, active: bool) -> void:
	if not bool(_session.call("is_host")):
		return
	_set_merge_intent(peer_id, active)


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
		var fallback_name := String(player_data.get("name", "Peer %d" % peer_id))
		var player: Node = _ensure_player(peer_id, fallback_name)
		_apply_appearance_to_player(
			peer_id,
			player_data.get("appearance", player_data),
			fallback_name
		)
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

	_apply_merge_snapshots(snapshot.get("merges", []))

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
	if is_peer_merged(peer_id):
		_fire_merge_shots(peer_id, aim_direction, broadcast)
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


func _fire_merge_shots(peer_id: int, aim_direction: Vector2, broadcast: bool) -> void:
	var merge := _active_merge_for_peer(peer_id)
	if merge.is_empty():
		return
	var node := merge.get("node") as Node
	if node == null or not is_instance_valid(node):
		return
	var direction := aim_direction.normalized()
	if direction.length_squared() <= 0.0001:
		direction = Vector2.UP
	var bullet_speed: float = BULLET_SCRIPT.DEFAULT_SPEED
	var stat_peer_id := 1 if _is_single_ai_peer(peer_id) else peer_id
	if _director != null:
		bullet_speed *= float(_director.call("player_bullet_speed_scale", stat_peer_id))
	var base_damage := 1
	var base_pierce := 0
	if _director != null:
		base_damage = int(_director.call("player_bullet_damage", stat_peer_id))
		base_pierce = (
			0
			if _is_single_ai_peer(peer_id)
			else int(_director.call("player_pierce_count", peer_id))
		)
	if int(merge.get("driver", 0)) == peer_id:
		var origin: Vector2 = node.call("fire_surface", direction)
		var shot_direction := _jitter_fire_direction(direction)
		_spawn_bullet(peer_id, origin, shot_direction, bullet_speed, base_damage + 1, base_pierce + 1)
		node.call("flash_hit")
		if broadcast:
			_session.call("broadcast_shot", peer_id, origin, shot_direction, bullet_speed)
		return
	for offset in [-7.0, 7.0]:
		var shot_direction := _jitter_fire_direction(direction.rotated(deg_to_rad(offset)))
		var origin: Vector2 = node.call("fire_surface", shot_direction)
		_spawn_bullet(peer_id, origin, shot_direction, bullet_speed, base_damage, base_pierce)
		if broadcast:
			_session.call("broadcast_shot", peer_id, origin, shot_direction, bullet_speed)
	node.call("flash_hit")


func _update_gameplay(delta: float) -> void:
	if _pause_blocks_gameplay_tick():
		_freeze_player_inputs()
		_refresh_battle_hud()
		return
	_update_fire_cooldowns(delta)
	_prune_bullets()
	var input_vector := _local_input_vector()
	if _play_mode == PlayMode.COUCH:
		_update_couch_inputs()
		if _battle_active():
			_update_merges_authority(delta)
			_apply_host_inputs()
		else:
			_freeze_player_inputs()
			_update_merge_cooldowns(delta)
		if _director != null:
			_director.call("host_tick", delta)
	elif bool(_session.call("is_host")):
		_peer_inputs[1] = input_vector
		if _battle_active():
			_update_merges_authority(delta)
			_apply_host_inputs()
		else:
			_freeze_player_inputs()
			_update_merge_cooldowns(delta)
		if _director != null:
			_director.call("host_tick", delta)
		_session.call("broadcast_snapshot", _build_snapshot())
	elif String(_session.call("active_transport")) != "offline":
		_session.call("send_input_to_host", input_vector)
		if _director != null:
			_director.call("client_tick", delta)
	else:
		var offline_player: Node = _ensure_player(1, "")
		_update_merge_cooldowns(delta)
		offline_player.call("set_input_vector", input_vector if _battle_active() else Vector2.ZERO)
		if _director != null:
			_director.call("host_tick", delta)
	if _play_mode == PlayMode.SINGLE and _battle_active():
		_update_single_ai(delta)
	for raw_player_id in _fire_held_by_player.keys():
		var player_id := int(raw_player_id)
		if bool(_fire_held_by_player.get(player_id, false)):
			_try_fire(player_id)
	_refresh_battle_hud()


func _update_fire_cooldowns(delta: float) -> void:
	for raw_player_id in _fire_cooldown_by_player.keys():
		var player_id := int(raw_player_id)
		_fire_cooldown_by_player[player_id] = maxf(
			0.0,
			float(_fire_cooldown_by_player.get(player_id, 0.0)) - delta
		)


func _poll_couch_pause_input() -> void:
	if _local_input_router == null:
		return
	for player_id in _local_input_router.call("active_slot_ids"):
		if int(player_id) == 1:
			continue
		var frame: Dictionary = _local_input_router.call("input_frame", int(player_id))
		if not bool(frame.get("pause_pressed", false)):
			continue
		if _pause_menu_open:
			if not _controller_reconnect_blocked:
				_close_pause_menu()
		elif _can_open_pause_menu():
			_open_pause_menu()
		return


func _update_couch_inputs() -> void:
	if _local_input_router == null:
		return
	_local_input_router.call("set_keyboard_aim_direction", _aim_direction_for_player(1))
	for raw_player_id in _local_input_router.call("active_slot_ids"):
		var player_id := int(raw_player_id)
		var frame: Dictionary = _local_input_router.call("input_frame", player_id)
		_peer_inputs[player_id] = frame.get("move", Vector2.ZERO)
		var aim: Variant = frame.get("aim", Vector2.UP)
		if aim is Vector2:
			_aim_direction_by_player[player_id] = aim
		if _couch_buff_player_id == player_id:
			_fire_held_by_player[player_id] = false
			_set_local_merge_intent(false, player_id)
			_update_couch_expression(player_id, false)
			continue
		_fire_held_by_player[player_id] = bool(frame.get("fire_held", false))
		if bool(frame.get("active_item_pressed", false)):
			_try_active_item(player_id)
		_set_local_merge_intent(bool(frame.get("merge_held", false)), player_id)
		_update_couch_expression(player_id, bool(frame.get("expression_held", false)))
	if _couch_buff_player_id > 1:
		_update_couch_buff_controller()


func _update_couch_expression(player_id: int, held: bool) -> void:
	var was_held := bool(_expression_held_by_player.get(player_id, false))
	_expression_held_by_player[player_id] = held
	if held and not was_held:
		_open_expression_wheel(player_id, player_id > 1)
	elif not held and was_held:
		_release_expression_wheel(player_id)
	if player_id > 1 and held and _expression_owner_id == player_id and _expression_wheel != null:
		var aim: Vector2 = _aim_direction_by_player.get(player_id, Vector2.UP)
		_expression_wheel.call("set_selection_direction", aim)


func _update_couch_buff_controller() -> void:
	if _local_input_router == null or _buff_panel == null:
		return
	var frame: Dictionary = _local_input_router.call("input_frame", _couch_buff_player_id)
	var move: Vector2 = frame.get("move", Vector2.ZERO)
	if absf(move.y) >= 0.55 and absf(_couch_buff_nav_y) < 0.55:
		_buff_panel.call("select_relative", 1 if move.y > 0.0 else -1)
	_couch_buff_nav_y = move.y
	var confirm_held := bool(frame.get("merge_held", false))
	if confirm_held and not _couch_buff_confirm_held:
		_buff_panel.call("confirm_selected")
		return
	_couch_buff_confirm_held = confirm_held


func _freeze_player_inputs() -> void:
	for peer_id in _players.keys():
		var player := _players[peer_id] as Node
		if player != null and is_instance_valid(player):
			player.call("set_input_vector", Vector2.ZERO)
	if _single_ai_active():
		_single_ai_teammate.call("set_input_vector", Vector2.ZERO)


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
	state["merge_status"] = _local_merge_status_text(local_id)
	state["ultimate"] = single_ultimate_state()
	state["couch_mode"] = _play_mode == PlayMode.COUCH
	state["player_cards"] = _couch_player_cards() if _play_mode == PlayMode.COUCH else []
	if not state.has("boss"):
		state["boss"] = {}
	_battle_hud.call("refresh", state)
	if _buff_panel != null and bool(_buff_panel.call("is_waiting")):
		var pending := int(_director.call("pending_choice_count"))
		if pending > 0:
			_buff_panel.call("update_waiting", _waiting_text(pending))


func _couch_player_cards() -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	var player_ids: Array[int] = []
	for raw_player_id in _players.keys():
		player_ids.append(int(raw_player_id))
	player_ids.sort()
	var palettes: Array[Dictionary] = PLAYER_SCRIPT.slime_palette_options()
	for player_id in player_ids:
		var player := _players.get(player_id) as Node
		if player == null or not is_instance_valid(player):
			continue
		var appearance: Dictionary = player.call("appearance_state")
		var palette_id := int(appearance.get("slime_palette_id", 0))
		var color := Color.WHITE
		if palette_id >= 0 and palette_id < palettes.size():
			color = palettes[palette_id].get("edge", Color.WHITE)
		cards.append({
			"slot": player_id,
			"name": _display_name_for_peer(player_id),
			"color": color,
			"hp": int(player.get("hp")),
			"max_hp": PLAYER_SCRIPT.MAX_HP,
			"alive": bool(player.get("alive")),
			"active_item": _director.call("active_item_for_peer", player_id),
			"input_hint": "Q" if player_id == 1 else "X",
			"merge_status": _local_merge_status_text(player_id),
		})
	return cards


func _apply_host_inputs() -> void:
	for peer_id in _players.keys():
		var player := _players[peer_id] as Node
		if player == null:
			continue
		if is_peer_merged(int(peer_id)):
			player.call("set_input_vector", Vector2.ZERO)
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
		"merges": _merge_snapshot_rows(),
		"transport": String(_session.call("active_transport")),
		"lobby_id": String(_session.call("lobby_id")),
	}
	if _director != null:
		snapshot.merge(_director.call("battle_snapshot"))
	return snapshot


func is_peer_merged(peer_id: int) -> bool:
	return not _active_merge_for_peer(peer_id).is_empty()


func single_ultimate_state() -> Dictionary:
	var active := _single_ai_active()
	var remaining := 0.0
	var merge_available := false
	if active:
		remaining = float(_single_ai_teammate.call("remaining_seconds"))
		merge_available = (
			not _single_ai_requires_merge_release
			and bool(_single_ai_teammate.call("can_merge"))
			and not is_peer_merged(SINGLE_AI_PEER_ID)
		)
	return {
		"visible": _play_mode == PlayMode.SINGLE,
		"charge": _single_ultimate_charge,
		"max_charge": SINGLE_ULTIMATE_MAX_CHARGE,
		"ready": not active and _single_ultimate_charge >= SINGLE_ULTIMATE_MAX_CHARGE,
		"active": active,
		"remaining": remaining,
		"merge_available": merge_available,
	}


func single_ai_teammate_node() -> Node:
	return _single_ai_teammate if _single_ai_active() else null


func _try_summon_single_ai() -> bool:
	if (
		_play_mode != PlayMode.SINGLE
		or not _battle_active()
		or _single_ai_active()
		or _single_ultimate_charge < SINGLE_ULTIMATE_MAX_CHARGE
	):
		return false
	var player := _players.get(1) as Node
	if player == null or not is_instance_valid(player) or not bool(player.get("alive")):
		return false

	var player_appearance: Dictionary = player.call("appearance_state")
	var slime_palette_id := PLAYER_SCRIPT.normalized_slime_palette_id(
		int(player_appearance.get("slime_palette_id", 0)) + 3
	)
	var bullet_palette_id := PLAYER_SCRIPT.normalized_bullet_palette_id(
		int(player_appearance.get("bullet_palette_id", 0)) + 3
	)
	var teammate := AI_TEAMMATE_SCRIPT.new() as Node
	teammate.name = "SingleAiTeammate"
	teammate.call("set_locale", _current_locale())
	teammate.call("set_player_info", SINGLE_AI_PEER_ID, _t("ai_ally_name"), slime_palette_id)
	teammate.call("apply_appearance", _t("ai_ally_name"), slime_palette_id, bullet_palette_id)
	add_child(teammate)
	teammate.call("set_local_or_host_simulated", true)
	teammate.call("set_movement_bounds", _world_rect())
	teammate.call(
		"set_move_speed",
		BATTLE_DIRECTOR_SCRIPT.PLAYER_BASE_MOVE_SPEED * SINGLE_AI_MOVE_SPEED_SCALE
	)
	teammate.call("begin", SINGLE_AI_DURATION)
	teammate.call(
		"warp_to",
		_clamp_player_position(player.call("body_center") + AI_TEAMMATE_SCRIPT.FOLLOW_OFFSET)
	)
	_single_ai_teammate = teammate
	_single_ultimate_charge = 0
	_single_ai_requires_merge_release = true
	_set_merge_intent(1, false)
	_set_merge_intent(SINGLE_AI_PEER_ID, false)
	_merge_cooldowns.erase(1)
	_merge_cooldowns.erase(SINGLE_AI_PEER_ID)
	_append_log(_t("log_ai_ally_summoned"))
	if _battle_hud != null:
		_battle_hud.call("show_notice", _t("log_ai_ally_summoned"), 1.6)
	request_screen_flash(Color(0.36, 0.92, 1.0, 1.0), 0.16, 0.18)
	return true


func _update_single_ai(delta: float) -> void:
	if not _single_ai_active() or _director == null:
		return
	var teammate := _single_ai_teammate
	var leader_position := _player_body_center(1)
	var follow_position := _clamp_player_position(leader_position + AI_TEAMMATE_SCRIPT.FOLLOW_OFFSET)
	var teammate_position := _player_body_center(SINGLE_AI_PEER_ID)
	var target_position: Vector2 = _director.call("nearest_hostile_position", teammate_position)
	var merged := is_peer_merged(SINGLE_AI_PEER_ID)
	var result: Dictionary = teammate.call(
		"advance_ai",
		delta,
		leader_position,
		follow_position,
		target_position,
		merged
	)
	if bool(result.get("expired", false)):
		_dismiss_single_ai(true)
		return
	if not bool(result.get("fire_ready", false)):
		return
	var aim_direction: Vector2 = result.get("aim_direction", Vector2.UP)
	if merged:
		_fire_merge_shots(SINGLE_AI_PEER_ID, aim_direction, false)
	else:
		_fire_single_ai_shot(aim_direction)


func _fire_single_ai_shot(aim_direction: Vector2) -> void:
	if not _single_ai_active() or _director == null:
		return
	var teammate := _single_ai_teammate
	var direction := aim_direction.normalized()
	if direction.length_squared() <= 0.0001:
		direction = Vector2.UP
	var origin: Vector2 = teammate.call("emit_fire_surface", direction)
	var bullet_speed := (
		BULLET_SCRIPT.DEFAULT_SPEED
		* float(_director.call("player_bullet_speed_scale", 1))
	)
	var damage := int(_director.call("player_bullet_damage", 1))
	_spawn_bullet(SINGLE_AI_PEER_ID, origin, direction, bullet_speed, damage, 0)


func _dismiss_single_ai(show_feedback: bool) -> void:
	if not _single_ai_active():
		_single_ai_teammate = null
		_single_ai_requires_merge_release = false
		return
	_end_merges_for_peer(SINGLE_AI_PEER_ID, false)
	_set_merge_intent(1, false)
	_set_merge_intent(SINGLE_AI_PEER_ID, false)
	_merge_cooldowns.erase(1)
	_merge_cooldowns.erase(SINGLE_AI_PEER_ID)
	var teammate := _single_ai_teammate
	_single_ai_teammate = null
	_single_ai_requires_merge_release = false
	if teammate != null and is_instance_valid(teammate):
		teammate.queue_free()
	if show_feedback:
		_append_log(_t("log_ai_ally_departed"))
		if _battle_hud != null:
			_battle_hud.call("show_notice", _t("log_ai_ally_departed"), 1.4)


func _reset_single_ultimate() -> void:
	_dismiss_single_ai(false)
	_single_ultimate_charge = 0


func _single_ai_active() -> bool:
	return _single_ai_teammate != null and is_instance_valid(_single_ai_teammate)


func _is_single_ai_peer(peer_id: int) -> bool:
	return peer_id == SINGLE_AI_PEER_ID and _single_ai_active()


func _merge_participant_node(peer_id: int) -> Node:
	if _is_single_ai_peer(peer_id):
		return _single_ai_teammate
	return _players.get(peer_id) as Node


func active_merge_hitboxes() -> Array[Dictionary]:
	var hitboxes: Array[Dictionary] = []
	for merge_id in _active_merges.keys():
		var merge: Dictionary = _active_merges[merge_id]
		hitboxes.append({
			"id": int(merge_id),
			"position": merge.get("position", _world_rect().get_center()),
			"radius": MERGED_SLIME_SCRIPT.HIT_RADIUS,
		})
	return hitboxes


func apply_merge_damage(merge_id: int, amount: int) -> bool:
	if not _active_merges.has(merge_id):
		return false
	var merge: Dictionary = _active_merges[merge_id]
	if float(merge.get("invuln", 0.0)) > 0.0:
		return false
	merge["shield"] = maxi(0, int(merge.get("shield", 0)) - maxi(amount, 0))
	merge["invuln"] = MERGE_HIT_INVULNERABILITY
	var node := merge.get("node") as Node
	if node != null and is_instance_valid(node):
		node.call("flash_hit")
		node.call("apply_state", _merge_snapshot_row(merge))
	_active_merges[merge_id] = merge
	if int(merge.get("shield", 0)) <= 0:
		_end_merge(merge_id, true)
	return true


func _set_local_merge_intent(active: bool, player_id: int = -1) -> void:
	var resolved_player_id := _keyboard_player_id() if player_id <= 0 else player_id
	if (
		_play_mode == PlayMode.SINGLE
		and resolved_player_id == 1
		and _single_ai_active()
		and _single_ai_requires_merge_release
	):
		if not active:
			_single_ai_requires_merge_release = false
		_merge_held_by_player[resolved_player_id] = false
		_set_merge_intent(resolved_player_id, false)
		_set_merge_intent(SINGLE_AI_PEER_ID, false)
		return
	if bool(_merge_held_by_player.get(resolved_player_id, false)) == active:
		return
	_merge_held_by_player[resolved_player_id] = active
	if _play_mode == PlayMode.SINGLE and resolved_player_id == 1 and _single_ai_active():
		var can_ai_merge := bool(_single_ai_teammate.call("can_merge"))
		_set_merge_intent(resolved_player_id, active and can_ai_merge)
		_set_merge_intent(SINGLE_AI_PEER_ID, active and can_ai_merge)
		return
	if _play_mode == PlayMode.COUCH:
		_set_merge_intent(resolved_player_id, active)
		return
	if _session == null:
		return
	if resolved_player_id != int(_session.call("local_peer_id")):
		return
	_session.call("send_merge_intent_to_host", active)


func _set_merge_intent(peer_id: int, active: bool) -> void:
	var was_active := bool(_peer_merge_intents.get(peer_id, false))
	_peer_merge_intents[peer_id] = active
	if active and not was_active:
		_merge_intent_order[peer_id] = _merge_press_sequence
		_merge_press_sequence += 1
	elif not active:
		_merge_intent_order.erase(peer_id)
		_clear_merge_hold_for_peer(peer_id)


func _update_merges_authority(delta: float) -> void:
	_update_merge_cooldowns(delta)
	_update_active_merges(delta)
	_update_merge_hold_progress(delta)
	_sync_merged_player_visibility()


func _update_merge_cooldowns(delta: float) -> void:
	for peer_id in _merge_cooldowns.keys():
		var remaining := maxf(0.0, float(_merge_cooldowns.get(peer_id, 0.0)) - delta)
		if remaining <= 0.0:
			_merge_cooldowns.erase(peer_id)
		else:
			_merge_cooldowns[peer_id] = remaining


func _update_active_merges(delta: float) -> void:
	var ended: Array[int] = []
	for merge_id in _active_merges.keys():
		var merge: Dictionary = _active_merges[merge_id]
		var driver := int(merge.get("driver", 0))
		var input_vector: Vector2 = _peer_inputs.get(driver, Vector2.ZERO)
		var position: Vector2 = merge.get("position", _world_rect().get_center())
		position += input_vector.limit_length(1.0) * BATTLE_DIRECTOR_SCRIPT.PLAYER_BASE_MOVE_SPEED * MERGE_MOVE_SPEED_SCALE * delta
		position = _clamp_merge_position(position)
		merge["position"] = position
		merge["remaining"] = maxf(0.0, float(merge.get("remaining", 0.0)) - delta)
		merge["invuln"] = maxf(0.0, float(merge.get("invuln", 0.0)) - delta)
		var node := merge.get("node") as Node
		if node != null and is_instance_valid(node):
			node.call("apply_state", _merge_snapshot_row(merge))
		_active_merges[merge_id] = merge
		if float(merge.get("remaining", 0.0)) <= 0.0:
			ended.append(int(merge_id))
	for merge_id in ended:
		_end_merge(merge_id, true)


func _update_merge_hold_progress(delta: float) -> void:
	var valid_pairs: Dictionary = {}
	var peer_ids := _players.keys()
	if _single_ai_active() and bool(_single_ai_teammate.call("can_merge")):
		peer_ids.append(SINGLE_AI_PEER_ID)
	peer_ids.sort()
	for left_index in range(peer_ids.size()):
		var left := int(peer_ids[left_index])
		if not bool(_peer_merge_intents.get(left, false)):
			continue
		for right_index in range(left_index + 1, peer_ids.size()):
			var right := int(peer_ids[right_index])
			if not bool(_peer_merge_intents.get(right, false)):
				continue
			if not _can_merge_pair(left, right):
				continue
			var key := _merge_pair_key(left, right)
			valid_pairs[key] = true
			var progress := float(_merge_hold_progress.get(key, 0.0)) + delta
			_merge_hold_progress[key] = progress
			if progress >= MERGE_HOLD_DURATION:
				var driver := _merge_driver_for_pair(left, right)
				var gunner := right if driver == left else left
				_start_merge(driver, gunner)
				_merge_hold_progress.erase(key)
				break
	for key in _merge_hold_progress.keys():
		if not valid_pairs.has(key):
			_merge_hold_progress.erase(key)


func _can_merge_pair(left: int, right: int) -> bool:
	if left == right:
		return false
	if is_peer_merged(left) or is_peer_merged(right):
		return false
	var has_single_ai := _is_single_ai_peer(left) or _is_single_ai_peer(right)
	if (
		not has_single_ai
		and (
			float(_merge_cooldowns.get(left, 0.0)) > 0.0
			or float(_merge_cooldowns.get(right, 0.0)) > 0.0
		)
	):
		return false
	var left_player := _merge_participant_node(left)
	var right_player := _merge_participant_node(right)
	if left_player == null or right_player == null:
		return false
	if not bool(left_player.get("alive")) or not bool(right_player.get("alive")):
		return false
	var left_position: Vector2 = left_player.call("body_center")
	var right_position: Vector2 = right_player.call("body_center")
	return left_position.distance_to(right_position) <= MERGE_DISTANCE


func _start_merge(driver: int, gunner: int) -> void:
	if not _can_merge_pair(driver, gunner):
		return
	var driver_player := _merge_participant_node(driver)
	var gunner_player := _merge_participant_node(gunner)
	if driver_player == null or gunner_player == null:
		return
	var driver_position: Vector2 = driver_player.call("body_center")
	var gunner_position: Vector2 = gunner_player.call("body_center")
	var position := (driver_position + gunner_position) * 0.5
	var colors: Dictionary = _merge_visual_colors(driver, gunner)
	var merge_id: int = _next_merge_id
	_next_merge_id += 1
	var merge_duration := MERGE_DURATION
	if _is_single_ai_peer(driver) or _is_single_ai_peer(gunner):
		merge_duration = minf(
			merge_duration,
			float(_single_ai_teammate.call("remaining_seconds"))
		)
		_single_ai_teammate.call("mark_merge_consumed")
	var merge := {
		"id": merge_id,
		"driver": driver,
		"gunner": gunner,
		"driver_name": _display_name_for_peer(driver),
		"gunner_name": _display_name_for_peer(gunner),
		"position": _clamp_merge_position(position),
		"remaining": merge_duration,
		"shield": MERGE_SHIELD,
		"max_shield": MERGE_SHIELD,
		"invuln": 0.0,
		"fill": colors["fill"],
		"edge": colors["edge"],
		"core": colors["core"],
	}
	var node := _ensure_merge_node(merge_id)
	merge["node"] = node
	node.call("configure", _merge_snapshot_row(merge))
	_active_merges[merge_id] = merge
	_set_merge_intent(driver, false)
	_set_merge_intent(gunner, false)
	_sync_merged_player_visibility()


func _end_merges_for_peer(peer_id: int, apply_cooldown: bool) -> void:
	var ended: Array[int] = []
	for merge_id in _active_merges.keys():
		var merge: Dictionary = _active_merges[merge_id]
		if int(merge.get("driver", 0)) == peer_id or int(merge.get("gunner", 0)) == peer_id:
			ended.append(int(merge_id))
	for merge_id in ended:
		_end_merge(merge_id, apply_cooldown)


func _end_merge(merge_id: int, apply_cooldown: bool) -> void:
	if not _active_merges.has(merge_id):
		return
	var merge: Dictionary = _active_merges[merge_id]
	var position: Vector2 = merge.get("position", _world_rect().get_center())
	var driver := int(merge.get("driver", 0))
	var gunner := int(merge.get("gunner", 0))
	var split_direction := Vector2.RIGHT
	var driver_player := _merge_participant_node(driver)
	var gunner_player := _merge_participant_node(gunner)
	if driver_player != null and gunner_player != null:
		var between: Vector2 = gunner_player.call("body_center") - driver_player.call("body_center")
		if between.length_squared() > 0.0001:
			split_direction = between.normalized()
	_place_split_player(driver, position - split_direction * MERGE_SPLIT_OFFSET)
	_place_split_player(gunner, position + split_direction * MERGE_SPLIT_OFFSET)
	var has_single_ai := _is_single_ai_peer(driver) or _is_single_ai_peer(gunner)
	if apply_cooldown and not has_single_ai:
		_merge_cooldowns[driver] = MERGE_COOLDOWN
		_merge_cooldowns[gunner] = MERGE_COOLDOWN
	var node := merge.get("node") as Node
	if node != null and is_instance_valid(node):
		node.queue_free()
	_active_merges.erase(merge_id)
	_sync_merged_player_visibility()


func _place_split_player(peer_id: int, position: Vector2) -> void:
	var player := _merge_participant_node(peer_id)
	if player == null or not is_instance_valid(player):
		return
	player.visible = true
	player.call("warp_to", _clamp_player_position(position))
	player.set("invuln_remaining", MERGE_SPLIT_INVULNERABILITY)


func _clear_merges() -> void:
	for merge_id in _active_merges.keys():
		var merge: Dictionary = _active_merges[merge_id]
		var node := merge.get("node") as Node
		if node != null and is_instance_valid(node):
			node.queue_free()
	_active_merges.clear()
	_peer_merge_intents.clear()
	_merge_intent_order.clear()
	_merge_hold_progress.clear()
	_merge_cooldowns.clear()
	_merge_held_by_player.clear()
	_sync_merged_player_visibility()


func _apply_merge_snapshots(rows: Variant) -> void:
	var seen: Dictionary = {}
	if rows is Array:
		for raw_row in rows:
			if not raw_row is Dictionary:
				continue
			var row: Dictionary = raw_row
			var merge_id := int(row.get("id", 0))
			if merge_id <= 0:
				continue
			seen[merge_id] = true
			var node := _ensure_merge_node(merge_id)
			var merge := row.duplicate(true)
			merge["position"] = _dict_to_vector(row.get("position", {}))
			merge["node"] = node
			node.call("configure", merge)
			_active_merges[merge_id] = merge
	for merge_id in _active_merges.keys():
		if seen.has(merge_id):
			continue
		var stale_merge: Dictionary = _active_merges[merge_id]
		var stale_node := stale_merge.get("node") as Node
		if stale_node != null and is_instance_valid(stale_node):
			stale_node.queue_free()
		_active_merges.erase(merge_id)
	_sync_merged_player_visibility()


func _merge_snapshot_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for merge_id in _active_merges.keys():
		var merge: Dictionary = _active_merges[merge_id]
		rows.append(_merge_snapshot_row(merge))
	return rows


func _merge_snapshot_row(merge: Dictionary) -> Dictionary:
	var position: Vector2 = merge.get("position", _world_rect().get_center())
	return {
		"id": int(merge.get("id", 0)),
		"driver": int(merge.get("driver", 0)),
		"gunner": int(merge.get("gunner", 0)),
		"driver_name": String(merge.get("driver_name", "")),
		"gunner_name": String(merge.get("gunner_name", "")),
		"position": {"x": position.x, "y": position.y},
		"remaining": float(merge.get("remaining", 0.0)),
		"shield": int(merge.get("shield", 0)),
		"max_shield": int(merge.get("max_shield", MERGE_SHIELD)),
		"fill": _color_to_dict(merge.get("fill", Color.WHITE)),
		"edge": _color_to_dict(merge.get("edge", Color.WHITE)),
		"core": _color_to_dict(merge.get("core", Color.WHITE)),
	}


func _ensure_merge_node(merge_id: int) -> Node2D:
	if _active_merges.has(merge_id):
		var existing: Dictionary = _active_merges[merge_id]
		var existing_node := existing.get("node") as Node2D
		if existing_node != null and is_instance_valid(existing_node):
			return existing_node
	var node := MERGED_SLIME_SCRIPT.new() as Node2D
	node.name = "MergedSlime%d" % merge_id
	node.call("set_locale", _current_locale())
	add_child(node)
	return node


func _active_merge_for_peer(peer_id: int) -> Dictionary:
	for merge_id in _active_merges.keys():
		var merge: Dictionary = _active_merges[merge_id]
		if int(merge.get("driver", 0)) == peer_id or int(merge.get("gunner", 0)) == peer_id:
			return merge
	return {}


func _active_merge_node_for_peer(peer_id: int) -> Node:
	var merge := _active_merge_for_peer(peer_id)
	if merge.is_empty():
		return null
	return merge.get("node") as Node


func _sync_merged_player_visibility() -> void:
	for peer_id in _players.keys():
		var player := _players[peer_id] as Node
		if player != null and is_instance_valid(player):
			player.visible = not is_peer_merged(int(peer_id))
	if _single_ai_active():
		_single_ai_teammate.visible = not is_peer_merged(SINGLE_AI_PEER_ID)


func _clear_merge_hold_for_peer(peer_id: int) -> void:
	for key in _merge_hold_progress.keys():
		if _merge_pair_key_has_peer(String(key), peer_id):
			_merge_hold_progress.erase(key)


func _merge_driver_for_pair(left: int, right: int) -> int:
	var left_order := int(_merge_intent_order.get(left, 999999))
	var right_order := int(_merge_intent_order.get(right, 999999))
	if left_order < right_order:
		return left
	if right_order < left_order:
		return right
	return mini(left, right)


func _merge_pair_key(left: int, right: int) -> String:
	var first := mini(left, right)
	var second := maxi(left, right)
	return "%d:%d" % [first, second]


func _merge_pair_key_has_peer(key: String, peer_id: int) -> bool:
	var parts := key.split(":")
	if parts.size() != 2:
		return false
	return int(parts[0]) == peer_id or int(parts[1]) == peer_id


func _merge_visual_colors(driver: int, gunner: int) -> Dictionary:
	var driver_palette := _slime_palette_for_peer(driver)
	var gunner_palette := _slime_palette_for_peer(gunner)
	var driver_fill: Color = driver_palette["fill"]
	var gunner_fill: Color = gunner_palette["fill"]
	var driver_edge: Color = driver_palette["edge"]
	var gunner_edge: Color = gunner_palette["edge"]
	var driver_core: Color = driver_palette["core"]
	var gunner_core: Color = gunner_palette["core"]
	return {
		"fill": driver_fill.lerp(gunner_fill, 0.5),
		"edge": driver_edge.lerp(gunner_edge, 0.5),
		"core": driver_core.lerp(gunner_core, 0.5),
	}


func _slime_palette_for_peer(peer_id: int) -> Dictionary:
	var player := _merge_participant_node(peer_id)
	if player == null:
		return PLAYER_SCRIPT.slime_palette(peer_id)
	var appearance: Dictionary = player.call("appearance_state")
	return PLAYER_SCRIPT.slime_palette(int(appearance.get("slime_palette_id", peer_id)))


func _display_name_for_peer(peer_id: int) -> String:
	var player := _merge_participant_node(peer_id)
	if player == null:
		return "Peer %d" % peer_id
	var display_name := String(player.get("display_name")).strip_edges()
	if display_name != "":
		return display_name
	if _play_mode == PlayMode.COUCH:
		return "P%d" % peer_id
	return "Host" if peer_id == 1 else "Peer %d" % peer_id


func _clamp_merge_position(position: Vector2) -> Vector2:
	var world_rect := _world_rect()
	return Vector2(
		clampf(position.x, world_rect.position.x + MERGED_SLIME_SCRIPT.HIT_RADIUS, world_rect.end.x - MERGED_SLIME_SCRIPT.HIT_RADIUS),
		clampf(position.y, world_rect.position.y + MERGED_SLIME_SCRIPT.HIT_RADIUS, world_rect.end.y - MERGED_SLIME_SCRIPT.HIT_RADIUS)
	)


func _clamp_player_position(position: Vector2) -> Vector2:
	var world_rect := _world_rect()
	return Vector2(
		clampf(position.x, world_rect.position.x + 21.0, world_rect.end.x - 21.0),
		clampf(position.y, world_rect.position.y + 21.0, world_rect.end.y - 21.0)
	)


func _color_to_dict(value: Variant) -> Dictionary:
	var color := Color.WHITE
	if value is Color:
		color = value
	return {"r": color.r, "g": color.g, "b": color.b, "a": color.a}


func _local_merge_status_text(peer_id: int) -> String:
	if not _battle_active() or peer_id <= 0:
		return ""
	var merge := _active_merge_for_peer(peer_id)
	if not merge.is_empty():
		var seconds := int(ceil(float(merge.get("remaining", 0.0))))
		var shield := int(merge.get("shield", 0))
		if int(merge.get("driver", 0)) == peer_id:
			return _t("merge_hud_driver", {"shield": shield, "time": seconds})
		return _t("merge_hud_gunner", {"shield": shield, "time": seconds})
	if (
		_play_mode == PlayMode.SINGLE
		and peer_id == 1
		and _single_ai_active()
		and _single_ai_requires_merge_release
	):
		return ""
	var cooldown := float(_merge_cooldowns.get(peer_id, 0.0))
	if cooldown > 0.0:
		return _t("merge_hud_cooldown", {"seconds": int(ceil(cooldown))})
	if _nearest_merge_ready_peer(peer_id) <= 0:
		return ""
	if bool(_peer_merge_intents.get(peer_id, false)) or bool(_merge_held_by_player.get(peer_id, false)):
		return _t("merge_hud_waiting")
	if _play_mode == PlayMode.COUCH and peer_id > 1:
		return _t("merge_hud_prompt_controller")
	return _t("merge_hud_prompt")


func _nearest_merge_ready_peer(peer_id: int) -> int:
	var player := _merge_participant_node(peer_id)
	if player == null or not bool(player.get("alive")) or is_peer_merged(peer_id):
		return 0
	var player_position: Vector2 = player.call("body_center")
	var best_peer := 0
	var best_distance := MERGE_DISTANCE
	var participant_ids := _players.keys()
	if _single_ai_active() and bool(_single_ai_teammate.call("can_merge")):
		participant_ids.append(SINGLE_AI_PEER_ID)
	for other_id in participant_ids:
		var other_peer := int(other_id)
		if other_peer == peer_id or is_peer_merged(other_peer):
			continue
		var other := _merge_participant_node(other_peer)
		if other == null or not bool(other.get("alive")):
			continue
		if float(_merge_cooldowns.get(other_peer, 0.0)) > 0.0:
			continue
		var distance: float = player_position.distance_to(other.call("body_center"))
		if distance <= best_distance:
			best_distance = distance
			best_peer = other_peer
	return best_peer


func _ensure_player(peer_id: int, display_name: String) -> Node:
	if _players.has(peer_id):
		return _players[peer_id]
	var player := PLAYER_SCRIPT.new() as Node
	player.name = "SlimePlayer%d" % peer_id
	player.call("set_locale", _current_locale())
	var appearance := _appearance_for_peer(peer_id, display_name)
	player.call("set_player_info", peer_id, display_name, peer_id)
	player.call(
		"apply_appearance",
		String(appearance.get("name", "")),
		int(appearance.get("slime_palette_id", 0)),
		int(appearance.get("bullet_palette_id", 0))
	)
	add_child(player)
	player.call("warp_to", _spawn_position_for_slot(_players.size()))
	player.call("set_movement_bounds", _world_rect())
	player.call("set_battle_timers_paused", not _battle_active())
	_players[peer_id] = player
	return player


func _sync_player_battle_timers(timers_running: bool) -> void:
	for peer_id in _players.keys():
		var player := _players[peer_id] as Node
		if player != null and is_instance_valid(player):
			player.call("set_battle_timers_paused", not timers_running)
	if _single_ai_active():
		_single_ai_teammate.call("set_battle_timers_paused", not timers_running)


func _try_fire(player_id: int = -1) -> void:
	var resolved_player_id := _keyboard_player_id() if player_id <= 0 else player_id
	if float(_fire_cooldown_by_player.get(resolved_player_id, 0.0)) > 0.0 or _screen != SCREEN_GAME:
		return
	if _pause_menu_open:
		return
	if _expression_owner_id == resolved_player_id and _expression_wheel != null and bool(_expression_wheel.call("is_open")):
		return
	if not _battle_active():
		return
	if not _players.has(resolved_player_id):
		return
	var local_player := _players[resolved_player_id] as Node
	if local_player == null or not bool(local_player.get("alive")):
		return
	var direction := _aim_direction_for_player(resolved_player_id)
	_fire_cooldown_by_player[resolved_player_id] = _local_fire_cooldown(resolved_player_id)
	if _play_mode == PlayMode.COUCH or _session == null or String(_session.call("active_transport")) == "offline":
		_fire_player_shots(resolved_player_id, direction, false)
		return
	if resolved_player_id != int(_session.call("local_peer_id")):
		return
	_session.call("send_shot_to_host", direction)


func _try_active_item(player_id: int = -1) -> void:
	var resolved_player_id := _keyboard_player_id() if player_id <= 0 else player_id
	if _screen != SCREEN_GAME:
		return
	if _pause_menu_open:
		return
	if _expression_owner_id == resolved_player_id and _expression_wheel != null and bool(_expression_wheel.call("is_open")):
		return
	if not _battle_active():
		return
	if not _players.has(resolved_player_id):
		return
	var local_player := _players[resolved_player_id] as Node
	if local_player == null or not bool(local_player.get("alive")):
		return
	if _play_mode == PlayMode.COUCH or _session == null or String(_session.call("active_transport")) == "offline":
		_use_active_item_authority(resolved_player_id)
		return
	if resolved_player_id != int(_session.call("local_peer_id")):
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
	var item_name_key := String(item_info.get("name_key", "active_item_fallback"))
	var item_name := _t(item_name_key)
	_append_log(_t("log_active_item_used", {"peer": peer_id, "item": item_name}))


func _local_fire_cooldown(peer_id: int) -> float:
	if _director == null:
		return FIRE_COOLDOWN
	return float(_director.call("player_fire_cooldown", peer_id))


func _aim_direction_for_player(player_id: int) -> Vector2:
	if _play_mode == PlayMode.COUCH and player_id > 1:
		var controller_aim: Vector2 = _aim_direction_by_player.get(player_id, Vector2.UP)
		return controller_aim.normalized() if controller_aim.length_squared() > 0.0001 else Vector2.UP
	var center := _player_body_center(player_id)
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
	var world_rect := _world_rect()
	var merge := _active_merge_for_peer(peer_id)
	if not merge.is_empty():
		return merge.get("position", world_rect.get_center())
	var player := _merge_participant_node(peer_id)
	if player == null:
		return world_rect.get_center()
	var body_center: Vector2 = player.call("body_center")
	return body_center


func _player_fire_surface(peer_id: int, direction: Vector2) -> Vector2:
	var world_rect := _world_rect()
	var player := _merge_participant_node(peer_id)
	if player == null:
		return world_rect.get_center()
	var surface_point: Vector2 = player.call("emit_fire_surface", direction)
	return surface_point


func _play_fire_surface_feedback(peer_id: int, direction: Vector2) -> void:
	var merge_node := _active_merge_node_for_peer(peer_id)
	if merge_node != null and is_instance_valid(merge_node):
		merge_node.call("flash_hit")
		return
	if not _players.has(peer_id):
		return
	var player := _players[peer_id] as Node
	if player != null:
		player.call("play_fire_surface_feedback", direction)


func _spawn_bullet(
	peer_id: int,
	origin: Vector2,
	direction: Vector2,
	speed: float = 560.0,
	damage_override: int = -1,
	pierce_override: int = -1
) -> void:
	var bullet := BULLET_SCRIPT.new() as Node2D
	bullet.name = "SlimeBullet%d" % (_bullets.size() + 1)
	var palette := _bullet_palette_for_peer(peer_id)
	bullet.call("configure", origin, direction, palette["fill"], palette["edge"], speed)
	bullet.set("owner_peer_id", peer_id)
	add_child(bullet)
	_bullets.append(bullet)
	if _director != null:
		if bool(_director.call("is_authority")):
			var damage := damage_override if damage_override >= 0 else int(_director.call("player_bullet_damage", peer_id))
			var pierce := pierce_override if pierce_override >= 0 else int(_director.call("player_pierce_count", peer_id))
			bullet.set("damage", damage)
			bullet.set("pierce_remaining", pierce)
		_director.call("register_player_bullet", bullet)


func _bullet_palette_for_peer(peer_id: int) -> Dictionary:
	var player := _merge_participant_node(peer_id)
	if player == null:
		return {
			"fill": Color(0.82, 1.0, 0.70, 0.96),
			"edge": Color(0.98, 1.0, 0.84, 0.98),
		}
	var palette: Dictionary = player.call("bullet_palette")
	return palette


func _open_expression_wheel(player_id: int = -1, controller_mode: bool = false) -> void:
	if _expression_wheel == null:
		return
	var resolved_player_id := _keyboard_player_id() if player_id <= 0 else player_id
	if _expression_owner_id > 0 and _expression_owner_id != resolved_player_id:
		return
	_expression_owner_id = resolved_player_id
	_expression_wheel.call("set_controller_mode", controller_mode)
	var player_label := _display_name_for_peer(resolved_player_id)
	if player_label.strip_edges() == "":
		player_label = "P%d" % resolved_player_id
	var device_label := _t("local_device_keyboard_mouse")
	if controller_mode and _local_input_router != null:
		device_label = String(_local_input_router.call("device_name_for_slot", resolved_player_id))
		if device_label.strip_edges() == "":
			device_label = _t("local_slot_gamepad")
	_expression_wheel.call("set_controller_context", _t("expression_controller_context", {
		"player": player_label,
		"device": device_label,
	}))
	_expression_wheel.call("open_at", current_viewport_size() * 0.5)


func _release_expression_wheel(player_id: int = -1) -> void:
	if _expression_wheel == null or not bool(_expression_wheel.call("is_open")):
		return
	var resolved_player_id := _keyboard_player_id() if player_id <= 0 else player_id
	if _expression_owner_id != resolved_player_id:
		return
	var expression_id := String(_expression_wheel.call("selected_expression_id"))
	_expression_wheel.call("close")
	_expression_owner_id = 0
	if expression_id != "":
		_send_expression(expression_id, resolved_player_id)


func _send_expression(expression_id: String, player_id: int = -1) -> void:
	if not _is_expression_id_allowed(expression_id):
		return
	var resolved_player_id := _keyboard_player_id() if player_id <= 0 else player_id
	if _play_mode == PlayMode.COUCH or _session == null or String(_session.call("active_transport")) == "offline":
		_show_player_expression(resolved_player_id, expression_id)
		return
	if resolved_player_id != int(_session.call("local_peer_id")):
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
	_peer_appearances.erase(peer_id)
	if is_instance_valid(player):
		player.queue_free()


func _clear_players() -> void:
	_reset_single_ultimate()
	_clear_merges()
	for peer_id in _players.keys():
		var player := _players[peer_id] as Node
		if is_instance_valid(player):
			player.queue_free()
	_players.clear()
	_peer_appearances.clear()


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


func _keyboard_player_id() -> int:
	if _play_mode == PlayMode.COUCH or _play_mode == PlayMode.SINGLE:
		return 1
	if _session == null:
		return 1
	return int(_session.call("local_peer_id"))


func _release_all_local_actions() -> void:
	var player_ids: Array[int] = []
	if _play_mode == PlayMode.COUCH and _local_input_router != null:
		for raw_player_id in _local_input_router.call("active_slot_ids"):
			player_ids.append(int(raw_player_id))
	else:
		player_ids.append(_keyboard_player_id())
	for player_id in player_ids:
		_fire_held_by_player[player_id] = false
		_set_local_merge_intent(false, player_id)
		_expression_held_by_player[player_id] = false
	if _expression_wheel != null and bool(_expression_wheel.call("is_open")):
		_expression_wheel.call("close")
	_expression_owner_id = 0


func _clear_local_input_state() -> void:
	_release_all_local_actions()
	_fire_held_by_player.clear()
	_merge_held_by_player.clear()
	_fire_cooldown_by_player.clear()
	_aim_direction_by_player.clear()
	_expression_held_by_player.clear()
	_expression_owner_id = 0
	_couch_buff_nav_y = 0.0
	_couch_buff_confirm_held = false


func _local_input_vector() -> Vector2:
	if _pause_menu_open:
		return Vector2.ZERO
	var input_vector := Input.get_vector(ACTION_MOVE_LEFT, ACTION_MOVE_RIGHT, ACTION_MOVE_UP, ACTION_MOVE_DOWN)
	return input_vector.limit_length(1.0)


func _spawn_position_for_slot(slot_index: int) -> Vector2:
	var world_rect := _world_rect()
	var index: int = maxi(0, slot_index)
	var steps := ceilf(float(index) * 0.5)
	var side := -1.0 if index % 2 == 1 else 1.0
	var x: float = clampf(
		world_rect.get_center().x + steps * 82.6667 * side,
		world_rect.position.x + 58.6667,
		world_rect.end.x - 58.6667
	)
	return Vector2(x, world_rect.end.y - 120.0)


func _dict_to_vector(data: Variant) -> Vector2:
	if not data is Dictionary:
		return Vector2.ZERO
	var dictionary: Dictionary = data
	return Vector2(float(dictionary.get("x", 0.0)), float(dictionary.get("y", 0.0)))


func _draw_menu_background() -> void:
	var viewport_size := current_viewport_size()
	for band_index in range(9):
		var y := float(band_index) * viewport_size.y / 9.0
		var alpha := 0.05 + float(band_index % 2) * 0.025
		draw_rect(Rect2(Vector2(0.0, y), Vector2(viewport_size.x, viewport_size.y / 9.0)), Color(0.06, 0.11, 0.09, alpha), true)

	var scan_y := fposmod(_ui_anim_time * 52.0, viewport_size.y + 120.0) - 60.0
	draw_rect(Rect2(Vector2(0.0, scan_y), Vector2(viewport_size.x, 2.0)), Color(0.42, 1.0, 0.66, 0.22), true)
	draw_rect(Rect2(Vector2(0.0, scan_y + 7.0), Vector2(viewport_size.x, 1.0)), Color(1.0, 0.72, 0.24, 0.12), true)

	var grid_color := Color(0.33, 0.75, 0.55, 0.10)
	var step := 48.0
	for x_index in range(int(viewport_size.x / step) + 1):
		var x := float(x_index) * step
		draw_line(Vector2(x, 0.0), Vector2(x, viewport_size.y), grid_color, 1.0)
	for y_index in range(int(viewport_size.y / step) + 1):
		var y := float(y_index) * step
		draw_line(Vector2(0.0, y), Vector2(viewport_size.x, y), grid_color, 1.0)

	var rail_offset := fposmod(_ui_anim_time * 34.0, 160.0)
	for index in range(-2, 8):
		var x0 := float(index) * 124.0 - rail_offset
		draw_line(Vector2(x0, viewport_size.y), Vector2(x0 + 230.0, 0.0), Color(0.28, 0.85, 0.90, 0.11), 2.0)
		draw_line(Vector2(viewport_size.x - x0, viewport_size.y), Vector2(viewport_size.x - x0 - 230.0, 0.0), Color(1.0, 0.45, 0.32, 0.08), 2.0)


func _draw_game_world() -> void:
	var world_rect := _world_rect()
	draw_rect(world_rect.grow(24.0), Color(0.0, 0.0, 0.0, 0.28), true)
	draw_rect(world_rect.grow(13.3333), Color(0.09, 0.16, 0.13, 0.35), true)
	draw_rect(world_rect, Color(0.044, 0.066, 0.064, 1.0), true)
	_draw_world_grid(world_rect)
	_draw_backdrop_stars(world_rect)
	var scan_y := world_rect.position.y + fposmod(_ui_anim_time * 80.0, world_rect.size.y)
	draw_line(Vector2(world_rect.position.x, scan_y), Vector2(world_rect.end.x, scan_y), Color(0.42, 1.0, 0.66, 0.13), 1.0)
	draw_rect(world_rect.grow(2.6667), Color(1.0, 0.72, 0.24, 0.18), false, 1.0)
	draw_rect(world_rect, Color(0.40, 0.82, 0.58, 0.62), false, 2.0)


func _draw_world_grid(world_rect: Rect2) -> void:
	var grid_color := Color(0.33, 0.55, 0.49, 0.12)
	var step := 40.0
	for x_index in range(int(world_rect.size.x / step) + 1):
		var x := world_rect.position.x + float(x_index) * step
		draw_line(Vector2(x, world_rect.position.y), Vector2(x, world_rect.position.y + world_rect.size.y), grid_color, 1.0)
	var scrolled := fmod(_world_scroll_offset, step)
	for y_index in range(int(world_rect.size.y / step) + 2):
		var y := world_rect.position.y + fposmod(float(y_index) * step + scrolled, world_rect.size.y + step) - step
		if y < world_rect.position.y or y > world_rect.end.y:
			continue
		draw_line(Vector2(world_rect.position.x, y), Vector2(world_rect.position.x + world_rect.size.x, y), grid_color, 1.0)


func _draw_backdrop_stars(world_rect: Rect2) -> void:
	for star in _backdrop_stars:
		var star_data: Dictionary = star
		var parallax := float(star_data.get("parallax", 0.5))
		var base := Vector2(float(star_data.get("x", 0.0)), float(star_data.get("y", 0.0)))
		var y := world_rect.position.y + fposmod(base.y + _world_scroll_offset * parallax, world_rect.size.y)
		var alpha := 0.10 + parallax * 0.22
		var star_radius := 1.0 + parallax * 1.6
		draw_circle(Vector2(world_rect.position.x + base.x, y), star_radius, Color(0.72, 0.92, 0.84, alpha))


func _generate_backdrop_stars() -> void:
	_backdrop_stars.clear()
	var star_rng := RandomNumberGenerator.new()
	star_rng.seed = 20260702
	for index in range(56):
		_backdrop_stars.append({
			"x": star_rng.randf_range(6.0, DESIGN_WORLD_RECT.size.x - 6.0),
			"y": star_rng.randf_range(0.0, DESIGN_WORLD_RECT.size.y),
			"parallax": 0.35 if index % 3 == 0 else star_rng.randf_range(0.55, 1.0),
		})


func _update_status() -> void:
	if _steam_status_label != null:
		var steam_available := bool(_session.call("steam_available"))
		_steam_status_label.text = String(_session.call("steam_status_text"))
		if _host_steam_button != null:
			_host_steam_button.disabled = not steam_available
		if _invite_steam_button != null:
			_invite_steam_button.disabled = not steam_available
		if _join_steam_button != null:
			_join_steam_button.disabled = not steam_available
	if _ready_room_label != null:
		var active_transport := String(_session.call("active_transport"))
		var host_active := bool(_session.call("is_host"))
		if _play_mode == PlayMode.COUCH:
			_ready_room_label.text = _t("ready_room_couch", {
				"players": _players.size(),
				"devices": _couch_device_summary(),
			})
		elif active_transport == "offline":
			_ready_room_label.text = _t("ready_room_empty")
		elif host_active:
			_ready_room_label.text = _t("ready_room_host", {"players": _players.size()})
		else:
			_ready_room_label.text = _t("ready_room_client", {"peer": int(_session.call("local_peer_id"))})
	if _start_battle_button != null:
		if _play_mode == PlayMode.COUCH:
			_start_battle_button.disabled = _players.size() < 2
		else:
			_start_battle_button.disabled = (
				not bool(_session.call("is_host"))
				or String(_session.call("active_transport")) == "offline"
				or _players.size() < 2
			)


func _couch_device_summary() -> String:
	if _local_input_router == null:
		return ""
	var lines: Array[String] = []
	var slots: Array = _local_input_router.call("slots")
	for raw_row in slots:
		if not raw_row is Dictionary:
			continue
		var row: Dictionary = raw_row
		var slot_id := int(row.get("slot_id", row.get("slot", 0)))
		if slot_id == 1:
			lines.append(_t("local_slot_keyboard"))
			continue
		var device_name := String(row.get("device_name", _t("local_slot_gamepad")))
		var suffix := " %s" % _t("local_slot_missing") if bool(row.get("missing", false)) else ""
		lines.append("P%d — %s%s" % [slot_id, device_name, suffix])
	var ignored_count := int(_local_input_router.call("ignored_controller_count"))
	if ignored_count > 0:
		lines.append(_t("local_controller_overflow", {"count": ignored_count}))
	return "\n".join(lines)


func _append_log(message: String) -> void:
	_log_lines.append(message)
	while _log_lines.size() > 14:
		_log_lines.pop_front()
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
	_register_key_action(ACTION_MERGE, KEY_E)
	_register_key_action(ACTION_PAUSE_MENU, KEY_ESCAPE)
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
