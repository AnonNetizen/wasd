extends SceneTree

const GRID_SCRIPT := preload("res://scripts/universal_tile_grid.gd")
const OUTPUT_SCENE_PATH: String = "res://scenes/ai_universal_tile_test.tscn"
const SCENE_SCRIPT := preload("res://scripts/ai_universal_tile_test.gd")


func _initialize() -> void:
	var scene_root := _build_scene()
	_assign_owner(scene_root, scene_root)

	var packed_scene := PackedScene.new()
	var pack_error := packed_scene.pack(scene_root)
	if pack_error != OK:
		push_error("Failed to pack AI universal Tile test scene: %s" % error_string(pack_error))
		scene_root.free()
		quit(pack_error)
		return

	var save_error := ResourceSaver.save(packed_scene, OUTPUT_SCENE_PATH)
	if save_error != OK:
		push_error("Failed to save AI universal Tile test scene: %s" % error_string(save_error))
		scene_root.free()
		quit(save_error)
		return

	scene_root.free()
	call_deferred("_finish_successfully")


func _finish_successfully() -> void:
	print("Saved scene: %s" % OUTPUT_SCENE_PATH)
	quit(0)


func _build_scene() -> Control:
	var scene_root := Control.new()
	scene_root.name = "AIUniversalTileTest"
	scene_root.set_script(SCENE_SCRIPT)
	scene_root.anchor_right = 1.0
	scene_root.anchor_bottom = 1.0
	scene_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	scene_root.grow_vertical = Control.GROW_DIRECTION_BOTH

	_add_background(scene_root)
	_add_world_frame(scene_root)

	var grid := Node2D.new()
	grid.name = "UniversalTileGrid"
	grid.position = Vector2(48.0, 152.0)
	grid.set_script(GRID_SCRIPT)
	scene_root.add_child(grid)

	_add_header(scene_root)
	_add_sidebar(scene_root)
	return scene_root


func _add_background(scene_root: Control) -> void:
	var background := ColorRect.new()
	background.name = "Background"
	background.anchor_right = 1.0
	background.anchor_bottom = 1.0
	background.grow_horizontal = Control.GROW_DIRECTION_BOTH
	background.grow_vertical = Control.GROW_DIRECTION_BOTH
	background.color = Color(0.025, 0.035, 0.034)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_root.add_child(background)

	var top_glow := ColorRect.new()
	top_glow.name = "TopGlow"
	top_glow.anchor_right = 1.0
	top_glow.offset_bottom = 126.0
	top_glow.color = Color(0.12, 0.18, 0.14, 0.34)
	top_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_root.add_child(top_glow)


func _add_world_frame(scene_root: Control) -> void:
	var frame := PanelContainer.new()
	frame.name = "WorldFrame"
	frame.position = Vector2(36.0, 140.0)
	frame.size = Vector2(792.0, 536.0)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override(
		"panel",
		_make_panel_style(Color(0.038, 0.052, 0.048, 0.98), Color(0.36, 0.50, 0.38), 3, 8)
	)
	scene_root.add_child(frame)


func _add_header(scene_root: Control) -> void:
	var title := Label.new()
	title.name = "Title"
	title.position = Vector2(44.0, 24.0)
	title.size = Vector2(780.0, 42.0)
	title.text = "AI UNIVERSAL TILE WORKFLOW"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.90, 0.93, 0.79))
	scene_root.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.position = Vector2(46.0, 68.0)
	subtitle.size = Vector2(770.0, 50.0)
	subtitle.text = "Style Pack → runtime PNG → one CellTileLayer → deterministic composition"
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color(0.62, 0.72, 0.62))
	scene_root.add_child(subtitle)

	var badge := Label.new()
	badge.name = "StyleBadge"
	badge.position = Vector2(590.0, 92.0)
	badge.size = Vector2(228.0, 28.0)
	badge.text = "ABANDONED MARBLE CONSERVATORY"
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.add_theme_font_size_override("font_size", 10)
	badge.add_theme_color_override("font_color", Color(0.73, 0.58, 0.35))
	scene_root.add_child(badge)


func _add_sidebar(scene_root: Control) -> void:
	var sidebar := PanelContainer.new()
	sidebar.name = "Sidebar"
	sidebar.position = Vector2(844.0, 24.0)
	sidebar.size = Vector2(400.0, 712.0)
	sidebar.add_theme_stylebox_override(
		"panel",
		_make_panel_style(Color(0.060, 0.071, 0.066, 0.98), Color(0.39, 0.47, 0.36), 2, 10)
	)
	scene_root.add_child(sidebar)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 20)
	sidebar.add_child(margin)

	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", 9)
	margin.add_child(rows)

	_add_sidebar_heading(rows)
	_add_separator(rows)
	_add_generation_status(rows)
	_add_layer_controls(rows)
	_add_hover_panel(rows)
	_add_sidebar_actions(rows)


func _add_sidebar_heading(rows: VBoxContainer) -> void:
	var title := Label.new()
	title.name = "SidebarTitle"
	title.text = "Generated Tile Scene"
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", Color(0.91, 0.87, 0.70))
	rows.add_child(title)

	var description := Label.new()
	description.name = "Description"
	description.custom_minimum_size.y = 38.0
	description.text = "Three mutually exclusive full-cell Tiles, one portable Style Pack, no import-cache dependency."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", 13)
	description.add_theme_color_override("font_color", Color(0.67, 0.71, 0.64))
	rows.add_child(description)


func _add_generation_status(rows: VBoxContainer) -> void:
	var seed_label := Label.new()
	seed_label.name = "SeedLabel"
	seed_label.text = "Seed  —"
	seed_label.add_theme_font_size_override("font_size", 18)
	seed_label.add_theme_color_override("font_color", Color(0.79, 0.86, 0.59))
	rows.add_child(seed_label)

	var summary_label := Label.new()
	summary_label.name = "SummaryLabel"
	summary_label.custom_minimum_size.y = 50.0
	summary_label.text = "Waiting for scene generation…"
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_label.add_theme_font_size_override("font_size", 13)
	summary_label.add_theme_color_override("font_color", Color(0.68, 0.74, 0.68))
	rows.add_child(summary_label)


func _add_layer_controls(rows: VBoxContainer) -> void:
	var layer_title := Label.new()
	layer_title.name = "LayerTitle"
	layer_title.text = "LAYER VISIBILITY"
	layer_title.add_theme_font_size_override("font_size", 12)
	layer_title.add_theme_color_override("font_color", Color(0.74, 0.60, 0.38))
	rows.add_child(layer_title)

	var toggles := GridContainer.new()
	toggles.name = "LayerToggles"
	toggles.columns = 2
	toggles.add_theme_constant_override("h_separation", 20)
	toggles.add_theme_constant_override("v_separation", 4)
	rows.add_child(toggles)
	_add_layer_toggle(toggles, "CellTilesToggle", "Cell Tiles", true)
	_add_layer_toggle(toggles, "CollisionToggle", "Collision", true)
	_add_layer_toggle(toggles, "DetailToggle", "Detail (empty)", true)
	_add_layer_toggle(toggles, "MetadataToggle", "Metadata", true)


func _add_layer_toggle(parent: GridContainer, node_name: String, text: String, pressed: bool) -> void:
	var toggle := CheckButton.new()
	toggle.name = node_name
	toggle.custom_minimum_size = Vector2(160.0, 28.0)
	toggle.text = text
	toggle.button_pressed = pressed
	toggle.add_theme_font_size_override("font_size", 13)
	toggle.add_theme_color_override("font_color", Color(0.81, 0.83, 0.75))
	parent.add_child(toggle)


func _add_hover_panel(rows: VBoxContainer) -> void:
	var hover_title := Label.new()
	hover_title.name = "HoverTitle"
	hover_title.text = "CELL METADATA"
	hover_title.add_theme_font_size_override("font_size", 12)
	hover_title.add_theme_color_override("font_color", Color(0.74, 0.60, 0.38))
	rows.add_child(hover_title)

	var hover_panel := PanelContainer.new()
	hover_panel.name = "HoverPanel"
	hover_panel.custom_minimum_size.y = 164.0
	hover_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(Color(0.025, 0.036, 0.033, 0.90), Color(0.24, 0.31, 0.25), 1, 6)
	)
	rows.add_child(hover_panel)

	var hover_margin := MarginContainer.new()
	hover_margin.name = "Margin"
	hover_margin.add_theme_constant_override("margin_left", 12)
	hover_margin.add_theme_constant_override("margin_top", 10)
	hover_margin.add_theme_constant_override("margin_right", 12)
	hover_margin.add_theme_constant_override("margin_bottom", 10)
	hover_panel.add_child(hover_margin)

	var hover_label := Label.new()
	hover_label.name = "HoverLabel"
	hover_label.text = "Hover a cell to inspect its metadata."
	hover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hover_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	hover_label.add_theme_font_size_override("font_size", 12)
	hover_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.70))
	hover_margin.add_child(hover_label)


func _add_sidebar_actions(rows: VBoxContainer) -> void:
	var instructions := Label.new()
	instructions.name = "Instructions"
	instructions.custom_minimum_size.y = 38.0
	instructions.text = "R: next deterministic seed  ·  Esc: Test Lab index"
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructions.add_theme_font_size_override("font_size", 12)
	instructions.add_theme_color_override("font_color", Color(0.58, 0.64, 0.59))
	rows.add_child(instructions)

	var regenerate_button := Button.new()
	regenerate_button.name = "RegenerateButton"
	regenerate_button.custom_minimum_size.y = 42.0
	regenerate_button.text = "Regenerate · R"
	_style_button(regenerate_button, true)
	rows.add_child(regenerate_button)

	var back_button := Button.new()
	back_button.name = "BackButton"
	back_button.custom_minimum_size.y = 38.0
	back_button.text = "Back to Test Lab · Esc"
	_style_button(back_button, false)
	rows.add_child(back_button)

	var error_label := Label.new()
	error_label.name = "ErrorLabel"
	error_label.visible = false
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.add_theme_font_size_override("font_size", 11)
	error_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.38))
	rows.add_child(error_label)


func _add_separator(rows: VBoxContainer) -> void:
	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 8)
	rows.add_child(separator)


func _style_button(button: Button, emphasized: bool) -> void:
	var base_color := Color(0.20, 0.28, 0.18) if emphasized else Color(0.12, 0.16, 0.14)
	var border_color := Color(0.58, 0.68, 0.35) if emphasized else Color(0.32, 0.39, 0.31)
	button.add_theme_stylebox_override("normal", _make_panel_style(base_color, border_color, 1, 6))
	button.add_theme_stylebox_override(
		"hover",
		_make_panel_style(base_color.lightened(0.10), border_color.lightened(0.14), 2, 6)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_make_panel_style(base_color.darkened(0.10), border_color, 2, 6)
	)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", Color(0.91, 0.90, 0.77))


func _make_panel_style(
	background_color: Color,
	border_color: Color,
	border_width: int,
	corner_radius: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	return style


func _assign_owner(node: Node, owner_node: Node) -> void:
	if node != owner_node:
		node.owner = owner_node
	for child: Node in node.get_children():
		_assign_owner(child, owner_node)
