class_name SteamLabExpressionWheel
extends Control

const WHEEL_RADIUS: float = 148.0
const INNER_RADIUS: float = 38.0
const TEXT_RADIUS: float = 94.0
const SECTOR_GAP: float = 0.035
const ARC_STEPS: int = 8

var _options: Array[Dictionary] = []
var _center_position: Vector2 = Vector2.ZERO
var _selected_index: int = -1
var _open_progress: float = 0.0
var _selection_flash: float = 0.0
var _closing: bool = false
var _wheel_tween: Tween
var _controller_mode: bool = false
var _controller_context: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	visible = false


func _process(_delta: float) -> void:
	if not _closing and not _controller_mode:
		_update_selected_index(get_global_mouse_position())
	_selection_flash = maxf(0.0, _selection_flash - _delta * 3.8)
	queue_redraw()


func set_options(options: Array[Dictionary]) -> void:
	_options = options.duplicate(true)
	_selected_index = -1
	queue_redraw()


func open_at(screen_position: Vector2) -> void:
	if _wheel_tween != null and _wheel_tween.is_valid():
		_wheel_tween.kill()
	_center_position = screen_position
	_selected_index = -1
	_open_progress = 0.0
	_closing = false
	visible = true
	set_process(true)
	if not _controller_mode:
		_update_selected_index(get_global_mouse_position())
	_wheel_tween = create_tween()
	_wheel_tween.tween_property(self, "_open_progress", 1.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	queue_redraw()


func close() -> void:
	if not visible:
		return
	if _wheel_tween != null and _wheel_tween.is_valid():
		_wheel_tween.kill()
	_closing = true
	_wheel_tween = create_tween()
	_wheel_tween.tween_property(self, "_open_progress", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_wheel_tween.tween_callback(_finish_close)


func _finish_close() -> void:
	visible = false
	set_process(false)
	_closing = false
	_selected_index = -1
	queue_redraw()


func selected_expression_id() -> String:
	if _selected_index < 0 or _selected_index >= _options.size():
		return ""
	return String(_options[_selected_index].get("id", ""))


func selected_expression_text() -> String:
	if _selected_index < 0 or _selected_index >= _options.size():
		return ""
	return String(_options[_selected_index].get("text", ""))


func selected_index() -> int:
	return _selected_index


func set_controller_mode(enabled: bool) -> void:
	_controller_mode = enabled
	if visible and not _closing and not _controller_mode:
		_update_selected_index(get_global_mouse_position())


func set_controller_context(context: String) -> void:
	_controller_context = context
	queue_redraw()


func controller_context() -> String:
	return _controller_context


func is_controller_mode() -> bool:
	return _controller_mode


func set_selection_direction(direction: Vector2) -> void:
	if not visible or _closing or direction.length_squared() <= 0.0001:
		return
	_update_selected_offset(direction.normalized() * WHEEL_RADIUS)


func is_open() -> bool:
	return visible and not _closing


func _draw() -> void:
	if not visible or _options.is_empty():
		return

	var eased_progress := clampf(_ease_out_cubic(_open_progress), 0.0, 1.12)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.22 * minf(eased_progress, 1.0)), true)
	draw_circle(_center_position, INNER_RADIUS * eased_progress, Color(0.05, 0.07, 0.07, 0.92))

	var font := get_theme_default_font()
	var expression_font_size := 24
	var label_font_size := 12
	for index in range(_options.size()):
		_draw_sector(font, index, expression_font_size, label_font_size, eased_progress)
	if _controller_context != "":
		var context_text := _controller_context.substr(0, 30)
		draw_string(
			font,
			_center_position + Vector2(-92.0, 4.0),
			context_text,
			HORIZONTAL_ALIGNMENT_CENTER,
			184.0,
			10,
			Color(0.92, 1.0, 0.86, minf(eased_progress, 1.0))
		)


func _draw_sector(font: Font, index: int, expression_font_size: int, label_font_size: int, progress: float) -> void:
	var segment_size := TAU / float(maxi(1, _options.size()))
	var start_angle := float(index) * segment_size + SECTOR_GAP
	var end_angle := float(index + 1) * segment_size - SECTOR_GAP
	var selected := index == _selected_index
	var fill_color := Color(0.13, 0.20, 0.18, 0.84)
	var edge_color := Color(0.52, 0.85, 0.72, 0.62)
	var text_color := Color(0.78, 1.0, 0.88, 0.96)
	if selected:
		fill_color = Color(0.34, 0.70, 0.54, 0.92).lerp(Color(1.0, 0.72, 0.24, 0.92), _selection_flash * 0.35)
		edge_color = Color(0.87, 1.0, 0.80, 0.95).lerp(Color(0.36, 0.92, 0.96, 1.0), _selection_flash * 0.45)
		text_color = Color(1.0, 1.0, 0.88, 1.0)

	fill_color.a *= minf(progress, 1.0)
	edge_color.a *= minf(progress, 1.0)
	text_color.a *= minf(progress, 1.0)

	var outer_radius := (WHEEL_RADIUS + (8.0 * _selection_flash if selected else 0.0)) * progress
	var inner_radius := INNER_RADIUS * progress
	var text_radius := TEXT_RADIUS * progress
	var sector_points := _sector_points(start_angle, end_angle, inner_radius, outer_radius)
	draw_colored_polygon(sector_points, fill_color)
	draw_polyline(_closed_points(sector_points), edge_color, 2.0, true)

	var middle_angle := (start_angle + end_angle) * 0.5
	var text_position := _center_position + _direction_from_wheel_angle(middle_angle) * text_radius
	var expression_text := String(_options[index].get("text", ""))
	var label_text := String(_options[index].get("label", ""))
	_draw_centered_string(font, expression_text, text_position + Vector2(0.0, -5.0), expression_font_size, text_color)
	_draw_centered_string(font, label_text, text_position + Vector2(0.0, 18.0), label_font_size, Color(text_color, 0.74))


func _sector_points(start_angle: float, end_angle: float, inner_radius: float, outer_radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for step_index in range(ARC_STEPS + 1):
		var ratio := float(step_index) / float(ARC_STEPS)
		var angle := lerpf(start_angle, end_angle, ratio)
		points.append(_center_position + _direction_from_wheel_angle(angle) * outer_radius)
	for step_index in range(ARC_STEPS, -1, -1):
		var ratio := float(step_index) / float(ARC_STEPS)
		var angle := lerpf(start_angle, end_angle, ratio)
		points.append(_center_position + _direction_from_wheel_angle(angle) * inner_radius)
	return points


func _closed_points(points: PackedVector2Array) -> PackedVector2Array:
	var closed := PackedVector2Array(points)
	if not points.is_empty():
		closed.append(points[0])
	return closed


func _draw_centered_string(font: Font, text: String, text_position: Vector2, font_size: int, color: Color) -> void:
	if text == "":
		return
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	draw_string(
		font,
		text_position + Vector2(text_size.x * -0.5, text_size.y * 0.35),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		color
	)


func _update_selected_index(mouse_position: Vector2) -> void:
	_update_selected_offset(mouse_position - _center_position)


func _update_selected_offset(offset: Vector2) -> void:
	if _options.is_empty():
		_selected_index = -1
		return

	if offset.length() < INNER_RADIUS:
		if _selected_index != -1:
			_selected_index = -1
			queue_redraw()
		return

	var angle := fposmod(atan2(offset.y, offset.x) + PI * 0.5, TAU)
	var next_selected_index := int(floor(angle / TAU * float(_options.size())))
	next_selected_index = clampi(next_selected_index, 0, _options.size() - 1)
	if next_selected_index != _selected_index:
		_selected_index = next_selected_index
		_selection_flash = 1.0
		queue_redraw()


func _direction_from_wheel_angle(angle: float) -> Vector2:
	return Vector2(sin(angle), -cos(angle))


func _ease_out_cubic(value: float) -> float:
	var clamped_value := clampf(value, 0.0, 1.0)
	return 1.0 - pow(1.0 - clamped_value, 3.0)
