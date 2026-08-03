# Doc: docs/代码/data_table_editor.md
@tool
class_name DataTableTreeColumnResizer
extends RefCounted
## Reusable header-boundary drag controller for editor-only Tree columns.

const DEFAULT_MINIMUM_WIDTH: int = 88
const DEFAULT_GRAB_WIDTH: float = 6.0
const DEFAULT_HEADER_MIN_HIT_HEIGHT: float = 32.0

var _tree: Tree
var _minimum_width: int = DEFAULT_MINIMUM_WIDTH
var _grab_width: float = DEFAULT_GRAB_WIDTH
var _header_min_hit_height: float = DEFAULT_HEADER_MIN_HIT_HEIGHT
var _widths_by_layout: Dictionary = {}
var _active_layout_key: String = ""
var _resize_column: int = -1
var _resize_start_x: float = 0.0
var _resize_start_widths := PackedInt32Array()
var _resize_current_widths := PackedInt32Array()
var _suppress_next_title_click: bool = false


static func resolve_resized_column_pair(
	left_width: int,
	right_width: int,
	delta: int,
	minimum_width: int = DEFAULT_MINIMUM_WIDTH
) -> Vector2i:
	var clamped_delta: int = clampi(
		delta,
		minimum_width - left_width,
		right_width - minimum_width
	)
	return Vector2i(left_width + clamped_delta, right_width - clamped_delta)


func attach(tree: Tree) -> void:
	if _tree == tree:
		return
	_tree = tree
	_tree.gui_input.connect(_on_tree_gui_input)
	_tree.mouse_exited.connect(_on_tree_mouse_exited)


func configure(
	layout_key: String,
	default_fixed_widths: PackedInt32Array = PackedInt32Array(),
	minimum_width: int = DEFAULT_MINIMUM_WIDTH,
	grab_width: float = DEFAULT_GRAB_WIDTH
) -> void:
	if _tree == null:
		return
	_active_layout_key = layout_key
	_minimum_width = maxi(1, minimum_width)
	_grab_width = maxf(1.0, grab_width)
	_resize_column = -1
	_resize_start_widths.clear()
	_resize_current_widths.clear()
	var saved_widths: Variant = _widths_by_layout.get(_active_layout_key, [])
	var has_saved_widths: bool = (
		saved_widths is Array
		and (saved_widths as Array).size() == maxi(_tree.columns - 1, 0)
	)
	for column: int in range(_tree.columns):
		_tree.set_column_clip_content(column, true)
		_tree.set_column_expand(column, true)
		_tree.set_column_expand_ratio(column, 1)
		_tree.set_column_custom_minimum_width(column, _minimum_width)
		if has_saved_widths and column < _tree.columns - 1:
			_tree.set_column_expand(column, false)
			_tree.set_column_custom_minimum_width(
				column,
				maxi(_minimum_width, int((saved_widths as Array)[column]))
			)
		elif column < mini(default_fixed_widths.size(), _tree.columns - 1):
			_tree.set_column_expand(column, false)
			_tree.set_column_custom_minimum_width(
				column, maxi(_minimum_width, default_fixed_widths[column])
			)


func consume_suppressed_title_click() -> bool:
	if _resize_column < 0 and not _suppress_next_title_click:
		return false
	_suppress_next_title_click = false
	return true


func _on_tree_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if _resize_column >= 0:
			_update_resize(motion.position.x)
			_tree.accept_event()
			return
		var boundary: int = _column_boundary_at(motion.position)
		_tree.mouse_default_cursor_shape = (
			Control.CURSOR_HSIZE if boundary >= 0 else Control.CURSOR_ARROW
		)
		return
	if not event is InputEventMouseButton:
		return
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button.button_index != MOUSE_BUTTON_LEFT:
		return
	if button.pressed:
		var boundary: int = _column_boundary_at(button.position)
		if boundary < 0:
			return
		_begin_resize(boundary, button.position.x)
		_tree.accept_event()
		return
	if _resize_column < 0:
		return
	_finish_resize()
	_tree.accept_event()


func _on_tree_mouse_exited() -> void:
	if _resize_column < 0:
		_tree.mouse_default_cursor_shape = Control.CURSOR_ARROW


func _column_boundary_at(position: Vector2) -> int:
	if (
		position.y < 0.0
		or position.y > _header_hit_height()
		or _tree.columns < 2
	):
		return -1
	var boundary_x: float = -_tree.get_scroll().x
	for column: int in range(_tree.columns - 1):
		boundary_x += float(_tree.get_column_width(column))
		if absf(position.x - boundary_x) <= _grab_width:
			return column
	return -1


func _header_hit_height() -> float:
	var title_font: Font = _tree.get_theme_font(&"title_button_font", &"Tree")
	var title_font_size: int = _tree.get_theme_font_size(
		&"title_button_font_size", &"Tree"
	)
	var title_style: StyleBox = _tree.get_theme_stylebox(
		&"title_button_normal", &"Tree"
	)
	return maxf(
		_header_min_hit_height,
		title_font.get_height(title_font_size) + title_style.get_minimum_size().y
	)


func _begin_resize(column: int, mouse_x: float) -> void:
	_resize_column = column
	_resize_start_x = mouse_x
	_resize_start_widths.clear()
	_resize_current_widths.clear()
	for current_column: int in range(_tree.columns):
		var width: int = maxi(
			_minimum_width, _tree.get_column_width(current_column)
		)
		_resize_start_widths.append(width)
		_resize_current_widths.append(width)
	for current_column: int in range(_tree.columns - 1):
		_tree.set_column_expand(current_column, false)
		_tree.set_column_custom_minimum_width(
			current_column, _resize_start_widths[current_column]
		)
	_tree.set_column_expand(_tree.columns - 1, true)
	_tree.set_column_custom_minimum_width(
		_tree.columns - 1, _minimum_width
	)
	_tree.mouse_default_cursor_shape = Control.CURSOR_HSIZE


func _update_resize(mouse_x: float) -> void:
	var right_column: int = _resize_column + 1
	if right_column >= _resize_start_widths.size():
		return
	var pair: Vector2i = resolve_resized_column_pair(
		_resize_start_widths[_resize_column],
		_resize_start_widths[right_column],
		roundi(mouse_x - _resize_start_x),
		_minimum_width
	)
	_resize_current_widths[_resize_column] = pair.x
	_resize_current_widths[right_column] = pair.y
	_tree.set_column_custom_minimum_width(_resize_column, pair.x)
	_tree.set_column_custom_minimum_width(right_column, pair.y)


func _finish_resize() -> void:
	var saved_widths: Array[int] = []
	for column: int in range(_tree.columns - 1):
		saved_widths.append(_resize_current_widths[column])
	_widths_by_layout[_active_layout_key] = saved_widths
	_tree.set_column_expand(_tree.columns - 1, true)
	_tree.set_column_custom_minimum_width(
		_tree.columns - 1, _minimum_width
	)
	_resize_column = -1
	_resize_start_widths.clear()
	_resize_current_widths.clear()
	_suppress_next_title_click = true
	call_deferred("_clear_title_click_suppression")


func _clear_title_click_suppression() -> void:
	_suppress_next_title_click = false
