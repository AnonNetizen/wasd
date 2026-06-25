extends SceneTree

const OUTPUT_SCENE_PATH := "res://scenes/native_button_scene.tscn"


func _initialize() -> void:
	var scene_root := _build_scene()
	_assign_owner(scene_root, scene_root)

	var packed_scene := PackedScene.new()
	var pack_error := packed_scene.pack(scene_root)
	if pack_error != OK:
		push_error("Failed to pack scene: %s" % pack_error)
		quit(pack_error)
		return

	var save_error := ResourceSaver.save(packed_scene, OUTPUT_SCENE_PATH)
	if save_error != OK:
		push_error("Failed to save scene: %s" % save_error)
		quit(save_error)
		return

	print("Saved scene: %s" % OUTPUT_SCENE_PATH)
	quit(0)


func _build_scene() -> Control:
	var root := Control.new()
	root.name = "NativeButtonScene"
	root.layout_mode = 3
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.custom_minimum_size = Vector2(960.0, 360.0)

	var background := ColorRect.new()
	background.name = "Background"
	background.color = Color(0.035, 0.047, 0.052, 1.0)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)

	var diagonal_lines := Control.new()
	diagonal_lines.name = "DiagonalBackgroundLines"
	diagonal_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(diagonal_lines)
	_add_line(diagonal_lines, "AmberLineTop", Vector2(-40.0, 272.0), Vector2(1000.0, 80.0), Color(0.63, 0.44, 0.18, 0.12), 1.0)
	_add_line(diagonal_lines, "GreenLine", Vector2(-40.0, 306.0), Vector2(1000.0, 114.0), Color(0.27, 0.58, 0.43, 0.15), 1.0)
	_add_line(diagonal_lines, "AmberLineBottom", Vector2(-40.0, 340.0), Vector2(1000.0, 148.0), Color(0.63, 0.44, 0.18, 0.12), 1.0)

	var button_group := Control.new()
	button_group.name = "ButtonGroup"
	button_group.position = Vector2(260.0, 82.0)
	button_group.size = Vector2(440.0, 112.0)
	root.add_child(button_group)

	var shadow := Panel.new()
	shadow.name = "DropShadow"
	shadow.position = Vector2(-6.0, 14.0)
	shadow.size = Vector2(452.0, 120.0)
	shadow.add_theme_stylebox_override("panel", _style(Color(0.0, 0.0, 0.0, 0.36), Color.TRANSPARENT, 0, 7))
	button_group.add_child(shadow)

	var button := Button.new()
	button.name = "EquipModButton"
	button.text = "EQUIP MOD"
	button.position = Vector2.ZERO
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
	button_group.add_child(button)

	var eyebrow := Label.new()
	eyebrow.name = "EyebrowLabel"
	eyebrow.text = "LOADOUT"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.position = Vector2(0.0, 22.0)
	eyebrow.size = Vector2(440.0, 24.0)
	eyebrow.add_theme_font_size_override("font_size", 15)
	eyebrow.add_theme_color_override("font_color", Color(0.50, 0.70, 0.58))
	eyebrow.add_theme_constant_override("outline_size", 1)
	eyebrow.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.75))
	button_group.add_child(eyebrow)

	var side_bars := Control.new()
	side_bars.name = "SideBars"
	side_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button_group.add_child(side_bars)
	_add_rect(side_bars, "LeftAmberBar", Vector2(40.0, 34.0), Vector2(5.0, 44.0), Color(0.85, 0.67, 0.31, 0.95))
	_add_rect(side_bars, "LeftGreenBar", Vector2(55.0, 34.0), Vector2(5.0, 44.0), Color(0.30, 0.54, 0.43, 0.95))
	_add_rect(side_bars, "RightGreenBar", Vector2(380.0, 34.0), Vector2(5.0, 44.0), Color(0.30, 0.54, 0.43, 0.95))
	_add_rect(side_bars, "RightAmberBar", Vector2(395.0, 34.0), Vector2(5.0, 44.0), Color(0.85, 0.67, 0.31, 0.95))

	var corner_marks := Control.new()
	corner_marks.name = "CornerMarks"
	corner_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button_group.add_child(corner_marks)
	var mark_color := Color(0.85, 0.67, 0.31, 0.78)
	_add_line(corner_marks, "TopLeftMark", Vector2(16.0, 16.0), Vector2(56.0, 16.0), mark_color, 2.0)
	_add_line(corner_marks, "TopRightMark", Vector2(384.0, 16.0), Vector2(424.0, 16.0), mark_color, 2.0)
	_add_line(corner_marks, "BottomLeftMark", Vector2(16.0, 96.0), Vector2(56.0, 96.0), mark_color, 2.0)
	_add_line(corner_marks, "BottomRightMark", Vector2(384.0, 96.0), Vector2(424.0, 96.0), mark_color, 2.0)

	var caption := Label.new()
	caption.name = "Caption"
	caption.text = "Visible .tscn preview: editable nodes + StyleBoxFlat resources, no runtime-built button"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.position = Vector2(140.0, 284.0)
	caption.size = Vector2(680.0, 24.0)
	caption.add_theme_font_size_override("font_size", 14)
	caption.add_theme_color_override("font_color", Color(0.58, 0.64, 0.66))
	root.add_child(caption)

	return root


func _assign_owner(node: Node, owner_node: Node) -> void:
	if node != owner_node:
		node.owner = owner_node
	for child in node.get_children():
		_assign_owner(child, owner_node)


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


func _add_rect(parent: Node, node_name: String, rect_position: Vector2, rect_size: Vector2, color: Color) -> void:
	var rect := ColorRect.new()
	rect.name = node_name
	rect.position = rect_position
	rect.size = rect_size
	rect.color = color
	parent.add_child(rect)


func _add_line(parent: Node, node_name: String, from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var line := Line2D.new()
	line.name = node_name
	line.points = PackedVector2Array([from, to])
	line.default_color = color
	line.width = width
	parent.add_child(line)
