class_name SteamLabActivePickup
extends Node2D

const REMOTE_INTERPOLATION: float = 14.0

var pickup_id: int = 0
var item_id: int = 0
var item_name: String = ""
var radius: float = 16.0
var life_remaining: float = 18.0

var _remote_driven: bool = false
var _authoritative_position: Vector2 = Vector2.ZERO
var _color: Color = Color(0.66, 0.95, 0.78, 0.96)
var _pulse_time: float = 0.0


func configure(
	new_pickup_id: int,
	new_item_id: int,
	new_item_name: String,
	spawn_position: Vector2,
	new_lifetime: float,
	new_color: Color
) -> void:
	pickup_id = new_pickup_id
	item_id = new_item_id
	item_name = new_item_name
	global_position = spawn_position
	_authoritative_position = spawn_position
	life_remaining = maxf(new_lifetime, 0.1)
	_color = new_color
	_pulse_time = 0.0
	queue_redraw()


func set_remote_driven(remote: bool) -> void:
	_remote_driven = remote


func set_authoritative_state(new_position: Vector2, new_life_remaining: float) -> void:
	_authoritative_position = new_position
	life_remaining = maxf(new_life_remaining, 0.0)


func advance(delta: float) -> void:
	life_remaining = maxf(0.0, life_remaining - delta)
	_pulse_time += delta
	queue_redraw()


func is_expired() -> bool:
	return life_remaining <= 0.0


func _process(delta: float) -> void:
	if _remote_driven:
		var response := 1.0 - exp(-REMOTE_INTERPOLATION * delta)
		global_position = global_position.lerp(_authoritative_position, response)
	_pulse_time += delta
	queue_redraw()


func _draw() -> void:
	var pulse := 0.5 + 0.5 * sin(_pulse_time * TAU * 1.4)
	var fade := clampf(life_remaining / 4.0, 0.25, 1.0)
	var body_color := Color(_color, _color.a * fade)
	var ring_color := Color(_color.lightened(0.28), 0.32 + pulse * 0.26)
	draw_circle(Vector2.ZERO, radius + 5.0 + pulse * 2.0, ring_color, false, 2.0, true)
	draw_circle(Vector2.ZERO, radius, body_color)
	draw_circle(Vector2.ZERO, radius, Color(0.98, 1.0, 0.86, 0.9 * fade), false, 2.0, true)
	match item_id:
		0:
			_draw_repair_glyph(fade)
		1:
			_draw_pulse_glyph(fade)
		2:
			_draw_stasis_glyph(fade)
		3:
			_draw_overload_glyph(fade)
		4:
			_draw_shield_glyph(fade)
		_:
			draw_circle(Vector2.ZERO, 4.0, Color(1.0, 1.0, 0.88, fade))


func _draw_repair_glyph(alpha: float) -> void:
	var glyph_color := Color(0.04, 0.13, 0.10, 0.88 * alpha)
	draw_rect(Rect2(Vector2(-3.0, -10.0), Vector2(6.0, 20.0)), glyph_color, true)
	draw_rect(Rect2(Vector2(-10.0, -3.0), Vector2(20.0, 6.0)), glyph_color, true)


func _draw_pulse_glyph(alpha: float) -> void:
	var glyph_color := Color(0.06, 0.08, 0.10, 0.86 * alpha)
	for index in range(8):
		var direction := Vector2(cos(TAU * float(index) / 8.0), sin(TAU * float(index) / 8.0))
		draw_line(direction * 3.0, direction * 11.0, glyph_color, 2.0, true)
	draw_circle(Vector2.ZERO, 4.0, glyph_color)


func _draw_stasis_glyph(alpha: float) -> void:
	var glyph_color := Color(0.03, 0.09, 0.14, 0.88 * alpha)
	draw_line(Vector2(-8.0, -8.0), Vector2(8.0, 8.0), glyph_color, 2.4, true)
	draw_line(Vector2(8.0, -8.0), Vector2(-8.0, 8.0), glyph_color, 2.4, true)
	draw_circle(Vector2.ZERO, 9.0, glyph_color, false, 1.8, true)


func _draw_overload_glyph(alpha: float) -> void:
	var glyph_color := Color(0.12, 0.08, 0.02, 0.88 * alpha)
	var points := PackedVector2Array([
		Vector2(-3.0, -11.0),
		Vector2(8.0, -2.0),
		Vector2(2.0, -2.0),
		Vector2(5.0, 11.0),
		Vector2(-8.0, 0.0),
		Vector2(-1.0, 0.0),
	])
	draw_colored_polygon(points, glyph_color)


func _draw_shield_glyph(alpha: float) -> void:
	var glyph_color := Color(0.03, 0.08, 0.13, 0.88 * alpha)
	var points := PackedVector2Array([
		Vector2(0.0, -11.0),
		Vector2(9.0, -5.0),
		Vector2(7.0, 6.0),
		Vector2(0.0, 12.0),
		Vector2(-7.0, 6.0),
		Vector2(-9.0, -5.0),
	])
	draw_colored_polygon(points, glyph_color)
