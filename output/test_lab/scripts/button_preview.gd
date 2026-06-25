extends Control

const SCREENSHOT_PATH := "res://button_preview.png"
const PANEL_COLOR := Color(0.035, 0.047, 0.052, 1.0)
const BUTTON_TEXT := "EQUIP MOD"
const BUTTON_SUBTEXT := "LOADOUT"

var _saved := false


func _ready() -> void:
	custom_minimum_size = Vector2(960.0, 360.0)
	_build_preview()
	call_deferred("_save_after_render")


func _build_preview() -> void:
	var background := ColorRect.new()
	background.color = PANEL_COLOR
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var field := Control.new()
	field.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(field)
	_add_line_to(field, Vector2(-40.0, 272.0), Vector2(1000.0, 80.0), Color(0.63, 0.44, 0.18, 0.12), 1.0)
	_add_line_to(field, Vector2(-40.0, 306.0), Vector2(1000.0, 114.0), Color(0.27, 0.58, 0.43, 0.15), 1.0)
	_add_line_to(field, Vector2(-40.0, 340.0), Vector2(1000.0, 148.0), Color(0.63, 0.44, 0.18, 0.12), 1.0)

	var shadow := Panel.new()
	shadow.position = Vector2(254.0, 96.0)
	shadow.size = Vector2(452.0, 120.0)
	shadow.add_theme_stylebox_override("panel", _style(Color(0.0, 0.0, 0.0, 0.36), Color.TRANSPARENT, 0, 7))
	add_child(shadow)

	var button := Button.new()
	button.text = BUTTON_TEXT
	button.position = Vector2(260.0, 82.0)
	button.size = Vector2(440.0, 112.0)
	button.focus_mode = Control.FOCUS_ALL
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_color_override("font_color", Color(0.95, 0.86, 0.66))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.94, 0.72))
	button.add_theme_color_override("font_pressed_color", Color(0.77, 0.96, 0.78))
	button.add_theme_color_override("font_focus_color", Color(1.0, 0.94, 0.72))
	button.add_theme_constant_override("outline_size", 2)
	button.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.72))
	button.add_theme_stylebox_override("normal", _button_style(Color(0.09, 0.125, 0.14), Color(0.72, 0.55, 0.25)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.12, 0.17, 0.18), Color(0.94, 0.74, 0.34)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.055, 0.075, 0.08), Color(0.46, 0.76, 0.56)))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, Color(0.48, 0.82, 0.64, 0.85), 2, 6))
	add_child(button)

	var top_label := Label.new()
	top_label.text = BUTTON_SUBTEXT
	top_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_label.position = Vector2(260.0, 104.0)
	top_label.size = Vector2(440.0, 24.0)
	top_label.add_theme_font_size_override("font_size", 15)
	top_label.add_theme_color_override("font_color", Color(0.50, 0.70, 0.58))
	top_label.add_theme_constant_override("outline_size", 1)
	top_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.75))
	add_child(top_label)

	_add_corner_marks()
	_add_side_bars()
	_add_caption()


func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := _style(fill, border, 3, 6)
	style.content_margin_left = 34.0
	style.content_margin_right = 34.0
	style.content_margin_top = 34.0
	style.content_margin_bottom = 18.0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 14
	style.shadow_offset = Vector2(0.0, 10.0)
	style.border_blend = true
	style.corner_detail = 8
	return style


func _style(fill: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


func _add_corner_marks() -> void:
	var mark_color := Color(0.85, 0.67, 0.31, 0.78)
	_add_line(Vector2(276.0, 98.0), Vector2(316.0, 98.0), mark_color, 2.0)
	_add_line(Vector2(644.0, 98.0), Vector2(684.0, 98.0), mark_color, 2.0)
	_add_line(Vector2(276.0, 178.0), Vector2(316.0, 178.0), mark_color, 2.0)
	_add_line(Vector2(644.0, 178.0), Vector2(684.0, 178.0), mark_color, 2.0)


func _add_side_bars() -> void:
	_add_rect(Vector2(300.0, 116.0), Vector2(5.0, 44.0), Color(0.85, 0.67, 0.31, 0.95))
	_add_rect(Vector2(315.0, 116.0), Vector2(5.0, 44.0), Color(0.30, 0.54, 0.43, 0.95))
	_add_rect(Vector2(640.0, 116.0), Vector2(5.0, 44.0), Color(0.30, 0.54, 0.43, 0.95))
	_add_rect(Vector2(655.0, 116.0), Vector2(5.0, 44.0), Color(0.85, 0.67, 0.31, 0.95))


func _add_caption() -> void:
	var caption := Label.new()
	caption.text = "Godot native preview: Button + StyleBoxFlat + labels, no bitmap texture"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.position = Vector2(180.0, 284.0)
	caption.size = Vector2(600.0, 24.0)
	caption.add_theme_font_size_override("font_size", 14)
	caption.add_theme_color_override("font_color", Color(0.58, 0.64, 0.66))
	add_child(caption)


func _add_rect(rect_position: Vector2, rect_size: Vector2, color: Color) -> void:
	var rect := ColorRect.new()
	rect.position = rect_position
	rect.size = rect_size
	rect.color = color
	add_child(rect)


func _add_line_to(parent: Node, from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var line := Line2D.new()
	line.points = PackedVector2Array([from, to])
	line.default_color = color
	line.width = width
	parent.add_child(line)


func _add_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	_add_line_to(self, from, to, color, width)


func _save_after_render() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _saved:
		return
	_saved = true
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(SCREENSHOT_PATH)
	if error != OK:
		push_error("Failed to save preview screenshot: %s" % error)
	get_tree().quit(error)
