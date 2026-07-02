class_name SteamLabSlimePlayer
extends Node2D

const BODY_SCRIPT := preload("res://scripts/slime_body.gd")
const LAB_LOCALE_SCRIPT := preload("res://scripts/lab_locale.gd")
const FOLLOW_DISTANCE: float = 82.0
const REMOTE_INTERPOLATION: float = 14.0
const EXPRESSION_LABEL_SIZE := Vector2(190.0, 42.0)
const EXPRESSION_OFFSET := Vector2(-95.0, -14.0)
const NAME_OFFSET := Vector2(-54.0, -62.0)
const MAX_HP: int = 3
const INVULNERABILITY_DURATION: float = 1.2
const SPECTATOR_ALPHA: float = 0.28

var peer_id: int = 0
var display_name: String = "Player"
var hp: int = MAX_HP
var alive: bool = true
var invuln_remaining: float = 0.0

var _body: Node2D
var _name_label: Label
var _expression_label: Label
var _input_vector: Vector2 = Vector2.ZERO
var _authoritative_position: Vector2 = Vector2.ZERO
var _authoritative_velocity: Vector2 = Vector2.ZERO
var _is_local_or_host_simulated: bool = false
var _palette_index: int = 0
var _expression_time_remaining: float = 0.0
var _bullet_fill_color: Color = Color(0.82, 1.0, 0.70, 0.96)
var _bullet_edge_color: Color = Color(0.98, 1.0, 0.84, 0.98)
var _battle_timers_paused: bool = false
var _locale: String = LAB_LOCALE_SCRIPT.LOCALE_ZH_CN


func _ready() -> void:
	_create_body()
	_create_label()
	_create_expression_label()
	_apply_player_visuals()
	_authoritative_position = global_position


func _process(delta: float) -> void:
	if _body == null:
		return
	_name_label.global_position = _body.global_position + NAME_OFFSET
	_update_expression_label(delta)
	_update_invulnerability(delta)
	if not _is_local_or_host_simulated:
		var response := 1.0 - exp(-REMOTE_INTERPOLATION * delta)
		_body.global_position = _body.global_position.lerp(_authoritative_position, response)


func set_player_info(new_peer_id: int, new_display_name: String, palette_index: int) -> void:
	peer_id = new_peer_id
	display_name = new_display_name.strip_edges()
	_palette_index = palette_index
	_apply_player_visuals()


func set_locale(locale: String) -> void:
	_locale = LAB_LOCALE_SCRIPT.normalize_locale(locale)
	_refresh_name_label()


func set_local_or_host_simulated(enabled: bool) -> void:
	_is_local_or_host_simulated = enabled
	if _body != null:
		_body.call("set_position_drive_enabled", enabled)


func set_movement_bounds(bounds: Rect2) -> void:
	if _body != null:
		_body.call("set_movement_bounds", bounds)


func set_input_vector(input_vector: Vector2) -> void:
	if not alive:
		input_vector = Vector2.ZERO
	_input_vector = input_vector.limit_length(1.0)
	if _body == null:
		return
	if _input_vector.length_squared() <= 0.0001:
		_body.call("set_follow_target", _body.global_position)
		return
	_body.call("set_follow_target", _body.global_position + _input_vector.normalized() * FOLLOW_DISTANCE)


func set_authoritative_state(new_position: Vector2, new_velocity: Vector2) -> void:
	_authoritative_position = new_position
	_authoritative_velocity = new_velocity
	if _body == null:
		global_position = new_position
		return
	if _is_local_or_host_simulated:
		_body.call("warp_to", new_position)


func warp_to(new_position: Vector2) -> void:
	global_position = new_position
	_authoritative_position = new_position
	if _body != null:
		_body.call("warp_to", new_position)


func push_out_of_circle(circle_center: Vector2, circle_radius: float, padding: float = 0.0) -> bool:
	if _body == null:
		return false
	var pushed := bool(_body.call("push_core_out_of_circle", circle_center, circle_radius, padding))
	if pushed:
		_authoritative_position = _body.global_position
		_authoritative_velocity = _body.call("body_velocity")
	return pushed


func show_expression(expression_text: String, duration: float = 2.2) -> void:
	if expression_text == "":
		return
	if _expression_label == null:
		_create_expression_label()
	_expression_label.text = expression_text
	_expression_label.visible = true
	_expression_label.modulate = Color.WHITE
	_expression_time_remaining = maxf(duration, 0.1)


func body_center() -> Vector2:
	if _body == null:
		return global_position
	return _body.global_position


func hit_radius() -> float:
	if _body == null:
		return 21.0
	return float(_body.get("core_collision_radius"))


func apply_damage(amount: int) -> bool:
	if not alive or invuln_remaining > 0.0:
		return false
	hp = maxi(0, hp - amount)
	invuln_remaining = INVULNERABILITY_DURATION
	if _body != null:
		_body.call("flash_impact", 1.0)
	if hp <= 0:
		_enter_spectator()
	return true


func heal(amount: int) -> void:
	if not alive:
		return
	hp = mini(MAX_HP, hp + amount)


func revive_full() -> void:
	hp = MAX_HP
	alive = true
	invuln_remaining = 0.0
	modulate = Color.WHITE
	_refresh_name_label()


func set_move_speed(speed: float) -> void:
	if _body != null:
		_body.set("max_speed", maxf(speed, 1.0))


func set_battle_timers_paused(paused: bool) -> void:
	_battle_timers_paused = paused


func apply_snapshot_extras(new_hp: int, new_alive: bool, new_invuln: float) -> void:
	if new_hp < hp and _body != null:
		_body.call("flash_impact", 1.0)
	hp = new_hp
	invuln_remaining = new_invuln
	if alive and not new_alive:
		_enter_spectator()
	elif not alive and new_alive:
		revive_full()


func _enter_spectator() -> void:
	alive = false
	hp = 0
	invuln_remaining = 0.0
	modulate = Color(1.0, 1.0, 1.0, SPECTATOR_ALPHA)
	_refresh_name_label()
	set_input_vector(Vector2.ZERO)


func _update_invulnerability(delta: float) -> void:
	if invuln_remaining <= 0.0:
		return
	if not _battle_timers_paused:
		invuln_remaining = maxf(0.0, invuln_remaining - delta)
	if not alive:
		return
	if invuln_remaining > 0.0:
		var flicker := 0.55 + 0.45 * sin(invuln_remaining * 40.0)
		modulate = Color(1.0, 1.0, 1.0, clampf(flicker, 0.3, 1.0))
	else:
		modulate = Color.WHITE


func emit_fire_surface(direction: Vector2) -> Vector2:
	if _body == null:
		return global_position
	var surface_point: Vector2 = _body.call("emit_surface_bud", direction)
	return surface_point


func play_fire_surface_feedback(direction: Vector2) -> void:
	if _body != null:
		_body.call("emit_surface_bud", direction)


func bullet_palette() -> Dictionary:
	return {
		"fill": _bullet_fill_color,
		"edge": _bullet_edge_color,
	}


func snapshot_state() -> Dictionary:
	var position := global_position
	var velocity := _authoritative_velocity
	if _body != null:
		position = _body.global_position
		velocity = _body.call("body_velocity")
	return {
		"peer_id": peer_id,
		"name": display_name,
		"position": {"x": position.x, "y": position.y},
		"velocity": {"x": velocity.x, "y": velocity.y},
		"hp": hp,
		"alive": alive,
		"inv": invuln_remaining,
	}


func _create_body() -> void:
	_body = BODY_SCRIPT.new() as Node2D
	_body.name = "SlimeBody"
	add_child(_body)
	_body.call("warp_to", global_position)


func _create_label() -> void:
	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 15)
	_name_label.add_theme_color_override("font_color", Color(0.88, 0.98, 0.92, 0.92))
	add_child(_name_label)
	_refresh_name_label()


func _create_expression_label() -> void:
	_expression_label = Label.new()
	_expression_label.name = "ExpressionLabel"
	_expression_label.size = EXPRESSION_LABEL_SIZE
	_expression_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_expression_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_expression_label.visible = false
	_expression_label.add_theme_font_size_override("font_size", 24)
	_expression_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.88, 0.96))
	_expression_label.add_theme_color_override("font_outline_color", Color(0.03, 0.05, 0.05, 0.82))
	_expression_label.add_theme_constant_override("outline_size", 4)
	add_child(_expression_label)


func _apply_player_visuals() -> void:
	_refresh_name_label()
	if _body != null:
		var palette := _palette_for_index(_palette_index)
		_body.call("set_palette", palette["fill"], palette["edge"], palette["core"])
		var edge_color: Color = palette["edge"]
		_bullet_fill_color = Color(edge_color, 0.96)
		_bullet_edge_color = Color(1.0, 1.0, 0.86, 0.98)


func _update_expression_label(delta: float) -> void:
	if _expression_label == null:
		return
	_expression_label.global_position = _body.global_position + EXPRESSION_OFFSET
	if _expression_time_remaining <= 0.0:
		_expression_label.visible = false
		return
	_expression_time_remaining = maxf(0.0, _expression_time_remaining - delta)
	_expression_label.visible = true
	var fade_alpha := clampf(_expression_time_remaining / 0.25, 0.0, 1.0)
	_expression_label.modulate = Color(1.0, 1.0, 1.0, fade_alpha)


func _palette_for_index(index: int) -> Dictionary:
	var palettes: Array[Dictionary] = [
		{
			"fill": Color(0.42, 0.86, 0.70, 0.50),
			"edge": Color(0.76, 1.0, 0.86, 0.94),
			"core": Color(0.21, 0.44, 0.54, 0.44),
		},
		{
			"fill": Color(0.42, 0.68, 0.95, 0.50),
			"edge": Color(0.78, 0.92, 1.0, 0.94),
			"core": Color(0.18, 0.32, 0.62, 0.44),
		},
		{
			"fill": Color(0.90, 0.62, 0.36, 0.50),
			"edge": Color(1.0, 0.84, 0.58, 0.94),
			"core": Color(0.56, 0.28, 0.15, 0.44),
		},
		{
			"fill": Color(0.74, 0.52, 0.92, 0.50),
			"edge": Color(0.92, 0.78, 1.0, 0.94),
			"core": Color(0.38, 0.20, 0.58, 0.44),
		},
	]
	return palettes[posmod(index, palettes.size())]


func _display_name_text() -> String:
	if display_name == "":
		return ""
	if alive:
		return display_name
	return "%s%s" % [display_name, LAB_LOCALE_SCRIPT.text(_locale, "player_down_suffix")]


func _refresh_name_label() -> void:
	if _name_label == null:
		return
	var label_text := _display_name_text()
	_name_label.text = label_text
	_name_label.visible = label_text != ""
