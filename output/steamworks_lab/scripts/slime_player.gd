class_name SteamLabSlimePlayer
extends Node2D

const BODY_SCRIPT := preload("res://scripts/slime_body.gd")
const FOLLOW_DISTANCE: float = 90.0
const REMOTE_INTERPOLATION: float = 14.0

var peer_id: int = 0
var display_name: String = "Player"

var _body: Node2D
var _name_label: Label
var _input_vector: Vector2 = Vector2.ZERO
var _authoritative_position: Vector2 = Vector2.ZERO
var _authoritative_velocity: Vector2 = Vector2.ZERO
var _is_local_or_host_simulated: bool = false
var _palette_index: int = 0


func _ready() -> void:
	_create_body()
	_create_label()
	_apply_player_visuals()
	_authoritative_position = global_position


func _process(delta: float) -> void:
	if _body == null:
		return
	_name_label.global_position = _body.global_position + Vector2(-54.0, -96.0)
	if not _is_local_or_host_simulated:
		var response := 1.0 - exp(-REMOTE_INTERPOLATION * delta)
		_body.global_position = _body.global_position.lerp(_authoritative_position, response)


func set_player_info(new_peer_id: int, new_display_name: String, palette_index: int) -> void:
	peer_id = new_peer_id
	display_name = new_display_name
	_palette_index = palette_index
	_apply_player_visuals()


func set_local_or_host_simulated(enabled: bool) -> void:
	_is_local_or_host_simulated = enabled
	if _body != null:
		_body.call("set_position_drive_enabled", enabled)


func set_input_vector(input_vector: Vector2) -> void:
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
	}


func _create_body() -> void:
	_body = BODY_SCRIPT.new() as Node2D
	_body.name = "SlimeBody"
	add_child(_body)
	_body.call("warp_to", global_position)


func _create_label() -> void:
	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.text = display_name
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 15)
	_name_label.add_theme_color_override("font_color", Color(0.88, 0.98, 0.92, 0.92))
	add_child(_name_label)


func _apply_player_visuals() -> void:
	if _name_label != null:
		_name_label.text = display_name
	if _body != null:
		var palette := _palette_for_index(_palette_index)
		_body.call("set_palette", palette["fill"], palette["edge"], palette["core"])


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
