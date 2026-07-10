class_name SteamLabMergedSlime
extends Node2D

const LAB_LOCALE_SCRIPT := preload("res://scripts/lab_locale.gd")

const HIT_RADIUS: float = 46.0
const NAME_OFFSET := Vector2(0.0, -66.0)
const STATUS_OFFSET := Vector2(0.0, 48.0)

var merge_id: int = 0
var driver_peer_id: int = 0
var gunner_peer_id: int = 0
var shield: int = 0
var max_shield: int = 3
var remaining: float = 0.0

var _fill_color: Color = Color(0.45, 0.92, 0.78, 0.62)
var _edge_color: Color = Color(0.86, 1.0, 0.92, 0.96)
var _core_color: Color = Color(0.22, 0.48, 0.52, 0.58)
var _driver_name: String = ""
var _gunner_name: String = ""
var _locale: String = LAB_LOCALE_SCRIPT.LOCALE_ZH_CN
var _pulse_time: float = 0.0

var _name_label: Label
var _status_label: Label


func _ready() -> void:
	_create_labels()
	queue_redraw()


func _process(delta: float) -> void:
	_pulse_time += delta
	if _name_label != null:
		_name_label.global_position = global_position + NAME_OFFSET
	if _status_label != null:
		_status_label.global_position = global_position + STATUS_OFFSET
	queue_redraw()


func configure(data: Dictionary) -> void:
	merge_id = int(data.get("id", merge_id))
	driver_peer_id = int(data.get("driver", driver_peer_id))
	gunner_peer_id = int(data.get("gunner", gunner_peer_id))
	_driver_name = String(data.get("driver_name", _driver_name))
	_gunner_name = String(data.get("gunner_name", _gunner_name))
	_fill_color = _color_from_value(data.get("fill", _fill_color), _fill_color)
	_edge_color = _color_from_value(data.get("edge", _edge_color), _edge_color)
	_core_color = _color_from_value(data.get("core", _core_color), _core_color)
	apply_state(data)


func apply_state(data: Dictionary) -> void:
	global_position = _vector_from_value(data.get("position", global_position), global_position)
	shield = int(data.get("shield", shield))
	max_shield = maxi(1, int(data.get("max_shield", max_shield)))
	remaining = float(data.get("remaining", remaining))
	_refresh_labels()
	queue_redraw()


func set_locale(locale: String) -> void:
	_locale = LAB_LOCALE_SCRIPT.normalize_locale(locale)
	_refresh_labels()


func hit_radius() -> float:
	return HIT_RADIUS


func fire_surface(direction: Vector2) -> Vector2:
	var shot_direction := direction.normalized()
	if shot_direction.length_squared() <= 0.0001:
		shot_direction = Vector2.UP
	return global_position + shot_direction * (HIT_RADIUS - 4.0)


func flash_hit() -> void:
	_pulse_time = 0.0


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_pulse_time * 5.8)
	var impact := maxf(0.0, 1.0 - _pulse_time * 3.0)
	draw_circle(Vector2.ZERO, HIT_RADIUS + 8.0 + pulse * 2.0, Color(_fill_color, 0.18))
	draw_circle(Vector2.ZERO, HIT_RADIUS + impact * 5.0, _fill_color)
	draw_circle(Vector2.ZERO, HIT_RADIUS * 0.58, _core_color)
	draw_circle(Vector2.ZERO, HIT_RADIUS + impact * 5.0, _edge_color, false, 4.0, true)
	draw_arc(Vector2.ZERO, HIT_RADIUS + 11.0, -PI * 0.5, TAU * clampf(remaining / 10.0, 0.0, 1.0) - PI * 0.5, 40, Color(1.0, 0.86, 0.36, 0.90), 3.0, true)
	for index in range(max_shield):
		var angle := -PI * 0.82 + float(index) * 0.24
		var center := Vector2(cos(angle), sin(angle)) * (HIT_RADIUS + 18.0)
		var color := Color(0.44, 0.96, 1.0, 0.96) if index < shield else Color(0.16, 0.22, 0.24, 0.72)
		draw_circle(center, 4.5, color)


func _create_labels() -> void:
	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 15)
	_name_label.add_theme_color_override("font_color", Color(0.92, 1.0, 0.86, 0.98))
	add_child(_name_label)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 12)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.44, 0.96))
	add_child(_status_label)
	_refresh_labels()


func _refresh_labels() -> void:
	if _name_label != null:
		_name_label.text = "%s + %s" % [_driver_name, _gunner_name]
	if _status_label != null:
		_status_label.text = LAB_LOCALE_SCRIPT.text(_locale, "merge_node_status", {
			"shield": shield,
			"time": int(ceil(remaining)),
		})


func _vector_from_value(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary:
		var data: Dictionary = value
		return Vector2(float(data.get("x", fallback.x)), float(data.get("y", fallback.y)))
	return fallback


func _color_from_value(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	if value is Dictionary:
		var data: Dictionary = value
		return Color(
			float(data.get("r", fallback.r)),
			float(data.get("g", fallback.g)),
			float(data.get("b", fallback.b)),
			float(data.get("a", fallback.a))
		)
	return fallback
