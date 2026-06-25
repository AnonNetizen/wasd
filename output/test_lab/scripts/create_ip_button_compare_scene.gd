extends SceneTree

const OUTPUT_SCENE_PATH := "res://scenes/ip_button_compare.tscn"
const SVG_NORMAL := "res://assets/ip_chitin_button_normal.svg"
const SVG_HOVER := "res://assets/ip_chitin_button_hover.svg"
const SVG_PRESSED := "res://assets/ip_chitin_button_pressed.svg"
const SVG_DISABLED := "res://assets/ip_chitin_button_disabled.svg"


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
	root.name = "IpButtonCompare"
	root.layout_mode = 3
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.custom_minimum_size = Vector2(1280.0, 760.0)

	_add_background(root)
	_add_title(root)
	_add_native_column(root)
	_add_svg_column(root)
	_add_palette_note(root)
	return root


func _add_background(root: Control) -> void:
	var background := ColorRect.new()
	background.name = "BackgroundBlackPurple"
	background.color = Color(0.020, 0.020, 0.030, 1.0)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)

	var lines := Control.new()
	lines.name = "ObliqueStageLines"
	lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(lines)
	_add_line(lines, "AmberStageLineA", Vector2(-60.0, 598.0), Vector2(1340.0, 312.0), Color(0.76, 0.54, 0.23, 0.10), 1.0)
	_add_line(lines, "VioletStageLineA", Vector2(-60.0, 646.0), Vector2(1340.0, 360.0), Color(0.45, 0.32, 0.78, 0.16), 1.0)
	_add_line(lines, "VioletStageLineB", Vector2(-60.0, 694.0), Vector2(1340.0, 408.0), Color(0.30, 0.20, 0.48, 0.13), 1.0)


func _add_title(root: Control) -> void:
	var title := Label.new()
	title.name = "Title"
	title.text = "Nestbreakers UI Button State Test"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0.0, 32.0)
	title.size = Vector2(1280.0, 42.0)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.94, 0.82, 0.56))
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "player/reward palette: graphite black, restrained amber, relic violet; cyan/red/white avoided as primary button color"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.position = Vector2(0.0, 78.0)
	subtitle.size = Vector2(1280.0, 24.0)
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color(0.56, 0.62, 0.60))
	root.add_child(subtitle)


func _add_native_column(root: Control) -> void:
	var panel := _make_column_panel("GodotNativeColumn", Vector2(64.0, 128.0), "GODOT NATIVE", "Button + StyleBoxFlat, editable controls")
	root.add_child(panel)

	_add_native_state_row(panel, "Normal", "EQUIP MOD", Vector2(128.0, 112.0), _native_normal_style(), false)
	_add_native_state_row(panel, "Hover", "EQUIP MOD", Vector2(128.0, 208.0), _native_hover_style(), false)
	_add_native_state_row(panel, "Pressed", "EQUIP MOD", Vector2(128.0, 304.0), _native_pressed_style(), false)
	_add_native_state_row(panel, "Disabled", "EQUIP MOD", Vector2(128.0, 400.0), _native_disabled_style(), true)

	var note := Label.new()
	note.name = "NativeNote"
	note.text = "Best for layout, localization, focus, hover/pressed logic, and fast iteration."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.position = Vector2(52.0, 502.0)
	note.size = Vector2(448.0, 44.0)
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color(0.62, 0.58, 0.70))
	panel.add_child(note)


func _add_svg_column(root: Control) -> void:
	var panel := _make_column_panel("SvgColumn", Vector2(672.0, 128.0), "SVG TEXTURE", "SVG frame assets inside TextureRect/TextureButton")
	root.add_child(panel)

	_add_svg_state_row(panel, "Normal", "EQUIP MOD", Vector2(128.0, 112.0), SVG_NORMAL, false)
	_add_svg_state_row(panel, "Hover", "EQUIP MOD", Vector2(128.0, 208.0), SVG_HOVER, false)
	_add_svg_state_row(panel, "Pressed", "EQUIP MOD", Vector2(128.0, 304.0), SVG_PRESSED, false)
	_add_svg_state_row(panel, "Disabled", "EQUIP MOD", Vector2(128.0, 400.0), SVG_DISABLED, true)

	var texture_button := TextureButton.new()
	texture_button.name = "InteractiveTextureButtonWithFourStates"
	texture_button.position = Vector2(52.0, 500.0)
	texture_button.size = Vector2(220.0, 46.0)
	texture_button.ignore_texture_size = true
	texture_button.stretch_mode = TextureButton.STRETCH_SCALE
	texture_button.texture_normal = _load_texture(SVG_NORMAL)
	texture_button.texture_hover = _load_texture(SVG_HOVER)
	texture_button.texture_pressed = _load_texture(SVG_PRESSED)
	texture_button.texture_disabled = _load_texture(SVG_DISABLED)
	panel.add_child(texture_button)

	var button_label := Label.new()
	button_label.name = "InteractiveTextureButtonLabel"
	button_label.text = "TEXTUREBUTTON"
	button_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button_label.position = texture_button.position
	button_label.size = texture_button.size
	button_label.add_theme_font_size_override("font_size", 13)
	button_label.add_theme_color_override("font_color", Color(0.95, 0.86, 0.66))
	panel.add_child(button_label)

	var note := Label.new()
	note.name = "SvgNote"
	note.text = "Best for detailed icon/frame art. State art is explicit but less flexible for text and resizing."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.position = Vector2(292.0, 500.0)
	note.size = Vector2(220.0, 50.0)
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color(0.62, 0.58, 0.70))
	panel.add_child(note)


func _add_palette_note(root: Control) -> void:
	var note := Label.new()
	note.name = "IpPaletteNote"
	note.text = "IP fit: graphite-black metal carries the UI body; violet suggests relic/overload tech; amber stays as a restrained loadout/reward accent. Cyan, red, and bone white are kept out of the primary player button signal."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.position = Vector2(178.0, 704.0)
	note.size = Vector2(924.0, 42.0)
	note.add_theme_font_size_override("font_size", 14)
	note.add_theme_color_override("font_color", Color(0.52, 0.58, 0.57))
	root.add_child(note)


func _make_column_panel(node_name: String, panel_position: Vector2, title_text: String, subtitle_text: String) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.position = panel_position
	panel.size = Vector2(544.0, 552.0)
	panel.add_theme_stylebox_override("panel", _panel_style())

	var title := Label.new()
	title.name = "ColumnTitle"
	title.text = title_text
	title.position = Vector2(32.0, 24.0)
	title.size = Vector2(480.0, 30.0)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.93, 0.76, 0.44))
	panel.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "ColumnSubtitle"
	subtitle.text = subtitle_text
	subtitle.position = Vector2(32.0, 58.0)
	subtitle.size = Vector2(480.0, 22.0)
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.58, 0.55, 0.66))
	panel.add_child(subtitle)
	return panel


func _add_native_state_row(parent: Node, state_name: String, text: String, row_position: Vector2, style: StyleBoxFlat, disabled: bool) -> void:
	var chip := _make_state_chip(state_name)
	chip.position = Vector2(36.0, row_position.y + 23.0)
	parent.add_child(chip)

	var button := Button.new()
	button.name = "Native%sButton" % state_name
	button.text = text
	button.position = row_position
	button.size = Vector2(360.0, 76.0)
	button.disabled = disabled
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color(0.95, 0.86, 0.66))
	button.add_theme_color_override("font_disabled_color", Color(0.46, 0.47, 0.43))
	button.add_theme_constant_override("outline_size", 2)
	button.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.78))
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("disabled", style)
	_add_native_chitin_frame(parent, state_name, row_position, disabled)
	parent.add_child(button)

	var eyebrow := Label.new()
	eyebrow.name = "Native%sEyebrow" % state_name
	eyebrow.text = "LOADOUT"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eyebrow.position = row_position + Vector2(0.0, 14.0)
	eyebrow.size = Vector2(360.0, 18.0)
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", Color(0.67, 0.58, 0.86) if not disabled else Color(0.40, 0.38, 0.45))
	parent.add_child(eyebrow)
	_add_native_hive_overlay(parent, state_name, row_position, disabled)


func _add_svg_state_row(parent: Node, state_name: String, text: String, row_position: Vector2, texture_path: String, disabled: bool) -> void:
	var chip := _make_state_chip(state_name)
	chip.position = Vector2(36.0, row_position.y + 23.0)
	parent.add_child(chip)

	var frame := TextureRect.new()
	frame.name = "Svg%sFrame" % state_name
	frame.position = row_position
	frame.size = Vector2(360.0, 76.0)
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.texture = _load_texture(texture_path)
	parent.add_child(frame)

	var eyebrow := Label.new()
	eyebrow.name = "Svg%sEyebrow" % state_name
	eyebrow.text = "LOADOUT"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.position = row_position + Vector2(0.0, 17.0)
	eyebrow.size = Vector2(360.0, 18.0)
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", Color(0.67, 0.58, 0.86) if not disabled else Color(0.40, 0.38, 0.45))
	parent.add_child(eyebrow)

	var label := Label.new()
	label.name = "Svg%sText" % state_name
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = row_position + Vector2(0.0, 20.0)
	label.size = Vector2(360.0, 46.0)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.95, 0.86, 0.66) if not disabled else Color(0.46, 0.47, 0.43))
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.78))
	parent.add_child(label)


func _make_state_chip(text: String) -> Label:
	var chip := Label.new()
	chip.name = "%sStateChip" % text
	chip.text = text
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	chip.size = Vector2(76.0, 24.0)
	chip.add_theme_font_size_override("font_size", 11)
	chip.add_theme_color_override("font_color", Color(0.62, 0.67, 0.63))
	return chip


func _add_native_hive_overlay(parent: Node, state_name: String, row_position: Vector2, disabled: bool) -> void:
	var overlay := Control.new()
	overlay.name = "Native%sHiveOverlay" % state_name
	overlay.position = row_position
	overlay.size = Vector2(360.0, 76.0)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(overlay)

	var rib_color := Color(0.78, 0.60, 0.30, 0.68) if not disabled else Color(0.33, 0.30, 0.38, 0.42)
	var membrane_color := Color(0.55, 0.40, 0.82, 0.48) if not disabled else Color(0.30, 0.26, 0.40, 0.32)
	var hole_edge := Color(0.45, 0.34, 0.70, 0.78) if not disabled else Color(0.28, 0.25, 0.36, 0.48)

	_add_polyline(overlay, "LeftChitinRibA", PackedVector2Array([Vector2(18.0, 40.0), Vector2(30.0, 25.0), Vector2(48.0, 23.0), Vector2(63.0, 30.0)]), rib_color, 2.0)
	_add_polyline(overlay, "LeftChitinRibB", PackedVector2Array([Vector2(22.0, 52.0), Vector2(38.0, 42.0), Vector2(56.0, 45.0)]), membrane_color, 1.5)
	_add_polyline(overlay, "RightChitinRibA", PackedVector2Array([Vector2(342.0, 40.0), Vector2(330.0, 25.0), Vector2(312.0, 23.0), Vector2(297.0, 30.0)]), rib_color, 2.0)
	_add_polyline(overlay, "RightChitinRibB", PackedVector2Array([Vector2(338.0, 52.0), Vector2(322.0, 42.0), Vector2(304.0, 45.0)]), membrane_color, 1.5)
	_add_polyline(overlay, "LeftLowerMembrane", PackedVector2Array([Vector2(84.0, 60.0), Vector2(110.0, 55.0), Vector2(136.0, 58.0)]), membrane_color, 1.8)
	_add_polyline(overlay, "RightLowerMembrane", PackedVector2Array([Vector2(224.0, 58.0), Vector2(250.0, 54.0), Vector2(278.0, 59.0)]), membrane_color, 1.8)

	_add_hive_pore(overlay, "PoreLeftUpper", Vector2(99.0, 22.0), Vector2(8.0, 5.0), hole_edge, disabled)
	_add_hive_pore(overlay, "PoreRightLower", Vector2(258.0, 52.0), Vector2(10.0, 6.0), hole_edge, disabled)
	_add_hive_pore(overlay, "PoreRightUpper", Vector2(280.0, 26.0), Vector2(6.0, 4.0), rib_color, disabled)


func _add_native_chitin_frame(parent: Node, state_name: String, row_position: Vector2, disabled: bool) -> void:
	var frame := Control.new()
	frame.name = "Native%sChitinFrame" % state_name
	frame.position = row_position
	frame.size = Vector2(360.0, 76.0)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(frame)

	var shell_fill := Color(0.19, 0.13, 0.26, 0.82) if not disabled else Color(0.10, 0.10, 0.13, 0.62)
	var shell_edge := Color(0.58, 0.43, 0.86, 0.90) if not disabled else Color(0.25, 0.23, 0.34, 0.72)
	var amber := Color(0.77, 0.58, 0.29, 0.72) if not disabled else Color(0.34, 0.30, 0.24, 0.45)
	var shadow := Polygon2D.new()
	shadow.name = "OrganicShadow"
	shadow.position = Vector2(0.0, 7.0)
	shadow.polygon = PackedVector2Array([
		Vector2(16.0, 15.0), Vector2(42.0, 4.0), Vector2(318.0, 4.0), Vector2(344.0, 15.0),
		Vector2(352.0, 38.0), Vector2(344.0, 62.0), Vector2(318.0, 72.0), Vector2(42.0, 72.0),
		Vector2(16.0, 62.0), Vector2(8.0, 38.0),
	])
	shadow.color = Color(0.0, 0.0, 0.0, 0.34)
	frame.add_child(shadow)

	var body := Polygon2D.new()
	body.name = "ChitinBody"
	body.polygon = PackedVector2Array([
		Vector2(18.0, 14.0), Vector2(44.0, 5.0), Vector2(316.0, 5.0), Vector2(342.0, 14.0),
		Vector2(350.0, 38.0), Vector2(342.0, 61.0), Vector2(316.0, 70.0), Vector2(44.0, 70.0),
		Vector2(18.0, 61.0), Vector2(10.0, 38.0),
	])
	body.color = shell_fill
	frame.add_child(body)
	_add_polyline(frame, "ChitinBodyRim", PackedVector2Array([
		Vector2(18.0, 14.0), Vector2(44.0, 5.0), Vector2(316.0, 5.0), Vector2(342.0, 14.0),
		Vector2(350.0, 38.0), Vector2(342.0, 61.0), Vector2(316.0, 70.0), Vector2(44.0, 70.0),
		Vector2(18.0, 61.0), Vector2(10.0, 38.0), Vector2(18.0, 14.0),
	]), shell_edge, 1.8)

	var left_plate := Polygon2D.new()
	left_plate.name = "LeftShellPlate"
	left_plate.polygon = PackedVector2Array([Vector2(22.0, 17.0), Vector2(47.0, 8.0), Vector2(84.0, 9.0), Vector2(72.0, 27.0), Vector2(31.0, 30.0)])
	left_plate.color = Color(0.43, 0.30, 0.19, 0.70) if not disabled else Color(0.18, 0.16, 0.18, 0.52)
	frame.add_child(left_plate)
	var right_plate := Polygon2D.new()
	right_plate.name = "RightShellPlate"
	right_plate.polygon = PackedVector2Array([Vector2(338.0, 17.0), Vector2(313.0, 8.0), Vector2(276.0, 9.0), Vector2(288.0, 27.0), Vector2(329.0, 30.0)])
	right_plate.color = left_plate.color
	frame.add_child(right_plate)

	_add_polyline(frame, "TopCarapaceCurve", PackedVector2Array([Vector2(90.0, 14.0), Vector2(134.0, 9.0), Vector2(225.0, 9.0), Vector2(270.0, 14.0)]), amber, 1.4)
	_add_polyline(frame, "BottomMembraneCurve", PackedVector2Array([Vector2(90.0, 62.0), Vector2(132.0, 68.0), Vector2(226.0, 68.0), Vector2(272.0, 62.0)]), shell_edge, 1.4)


func _panel_style() -> StyleBoxFlat:
	var style := _style(Color(0.057, 0.064, 0.070, 0.94), Color(0.15, 0.13, 0.11, 1.0), 1, 6)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.34)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0.0, 10.0)
	return style


func _native_normal_style() -> StyleBoxFlat:
	var style := _button_style(Color(0.075, 0.070, 0.105, 0.62), Color(0.48, 0.36, 0.75, 0.35))
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.44)
	return style


func _native_hover_style() -> StyleBoxFlat:
	var style := _button_style(Color(0.105, 0.080, 0.145, 0.66), Color(0.70, 0.55, 0.98, 0.42))
	style.shadow_color = Color(0.45, 0.30, 0.78, 0.36)
	style.shadow_size = 18
	return style


func _native_pressed_style() -> StyleBoxFlat:
	var style := _button_style(Color(0.052, 0.050, 0.072, 0.64), Color(0.78, 0.58, 0.28, 0.50))
	style.content_margin_top = 20.0
	style.shadow_size = 8
	style.shadow_offset = Vector2(0.0, 4.0)
	return style


func _native_disabled_style() -> StyleBoxFlat:
	var style := _button_style(Color(0.065, 0.065, 0.080, 0.58), Color(0.27, 0.25, 0.34, 0.36))
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.18)
	style.shadow_size = 6
	return style


func _button_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := _style(fill, border, 2, 6)
	style.content_margin_left = 28.0
	style.content_margin_right = 28.0
	style.content_margin_top = 18.0
	style.content_margin_bottom = 8.0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0.0, 8.0)
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


func _load_texture(path: String) -> Texture2D:
	var texture := load(path) as Texture2D
	if texture != null:
		return texture

	var import_config := ConfigFile.new()
	var import_error := import_config.load("%s.import" % path)
	if import_error == OK:
		var imported_path := str(import_config.get_value("remap", "path", ""))
		if not imported_path.is_empty():
			texture = load(imported_path) as Texture2D
	if texture == null:
		push_error("Failed to load texture: %s" % path)
	return texture


func _add_polyline(parent: Node, node_name: String, points: PackedVector2Array, color: Color, width: float) -> void:
	var line := Line2D.new()
	line.name = node_name
	line.points = points
	line.default_color = color
	line.width = width
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	parent.add_child(line)


func _add_hive_pore(parent: Node, node_name: String, center: Vector2, radius: Vector2, edge_color: Color, disabled: bool) -> void:
	var pore := Polygon2D.new()
	pore.name = node_name
	var points := PackedVector2Array()
	for index in range(12):
		var angle := TAU * float(index) / 12.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	pore.polygon = points
	pore.color = Color(0.025, 0.020, 0.035, 0.88) if not disabled else Color(0.030, 0.030, 0.038, 0.62)
	parent.add_child(pore)

	var rim := Line2D.new()
	rim.name = "%sRim" % node_name
	points.append(points[0])
	rim.points = points
	rim.default_color = edge_color
	rim.width = 1.0
	rim.joint_mode = Line2D.LINE_JOINT_ROUND
	parent.add_child(rim)


func _add_line(parent: Node, node_name: String, from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var line := Line2D.new()
	line.name = node_name
	line.points = PackedVector2Array([from, to])
	line.default_color = color
	line.width = width
	parent.add_child(line)


func _assign_owner(node: Node, owner_node: Node) -> void:
	if node != owner_node:
		node.owner = owner_node
	for child in node.get_children():
		_assign_owner(child, owner_node)
