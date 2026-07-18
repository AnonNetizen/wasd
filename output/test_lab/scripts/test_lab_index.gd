extends Control

const STATIC_TEST_SCENES := {
	"Orthographic3DButton": "res://scenes/orthographic_3d_test.tscn",
	"SlimeRoomShooterButton": "res://scenes/slime_room_shooter_3d.tscn",
	"AiBitmapButton": "res://scenes/ai_bitmap_button_test.tscn",
	"NativeButton": "res://scenes/native_button_scene.tscn",
	"CompareButton": "res://scenes/ip_button_compare.tscn",
	"CodeButton": "res://scenes/button_preview.tscn",
}

const EXTRA_TEST_SCENES := [
	{
		"button_name": "AiUniversalTileButton",
		"label": "AI Universal Tile Scene",
		"scene_path": "res://scenes/ai_universal_tile_test.tscn",
		"featured": true,
	},
	{
		"button_name": "NeonGeometryCombatButton",
		"label": "Neon Geometry Combat Test",
		"scene_path": "res://scenes/neon_geometry_combat_test.tscn",
		"featured": true,
	},
	{
		"button_name": "MyceliumGrowthButton",
		"label": "Mycelium Growth Test",
		"scene_path": "res://scenes/mycelium_growth_test.tscn",
	},
	{
		"button_name": "SoftBodyCellButton",
		"label": "Soft Body Cell Edge Test",
		"scene_path": "res://scenes/soft_body_cell_test.tscn",
	},
	{
		"button_name": "EmotionBlobButton",
		"label": "Emotion Blob Test",
		"scene_path": "res://scenes/emotion_blob_test.tscn",
	},
	{
		"button_name": "InkWashButton",
		"label": "Ink Wash Test",
		"scene_path": "res://scenes/ink_test.tscn",
	},
	{
		"button_name": "CloudMistButton",
		"label": "Cloud Mist Test",
		"scene_path": "res://scenes/cloud_mist_test.tscn",
	},
	{
		"button_name": "AdvancedCellButton",
		"label": "Advanced Cell Test",
		"scene_path": "res://scenes/advanced_cell_test.tscn",
	},
]


func _ready() -> void:
	var button_rows := _ensure_scrollable_button_area()
	if button_rows == null:
		return

	_add_extra_test_buttons(button_rows)
	_connect_static_test_buttons(button_rows)


func _ensure_scrollable_button_area() -> VBoxContainer:
	var rows := get_node_or_null("Panel/Margin/Rows") as VBoxContainer
	if rows == null:
		push_error("Test Lab index is missing its Rows container.")
		return null

	var existing_scroll := rows.get_node_or_null("ButtonScroll") as ScrollContainer
	if existing_scroll != null:
		return existing_scroll.get_node_or_null("ButtonRows") as VBoxContainer

	var scroll := ScrollContainer.new()
	scroll.name = "ButtonScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	rows.add_child(scroll)

	var button_rows := VBoxContainer.new()
	button_rows.name = "ButtonRows"
	button_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_rows.add_theme_constant_override("separation", 12)
	scroll.add_child(button_rows)

	for child in rows.get_children():
		if child is Button:
			child.reparent(button_rows)

	return button_rows


func _connect_static_test_buttons(button_rows: VBoxContainer) -> void:
	for button_name in STATIC_TEST_SCENES:
		var button := button_rows.get_node_or_null(String(button_name)) as Button
		if button == null:
			continue
		button.pressed.connect(_open_scene.bind(String(STATIC_TEST_SCENES[button_name])))


func _add_extra_test_buttons(button_rows: VBoxContainer) -> void:
	var template := button_rows.get_node_or_null("CodeButton") as Button
	for scene_info in EXTRA_TEST_SCENES:
		var button: Button
		if template != null:
			button = template.duplicate() as Button
		else:
			button = Button.new()
		button.name = String(scene_info["button_name"])
		button.text = String(scene_info["label"])
		button.custom_minimum_size.y = 54.0
		button_rows.add_child(button)
		if bool(scene_info.get("featured", false)):
			button_rows.move_child(button, 0)
		button.pressed.connect(_open_scene.bind(String(scene_info["scene_path"])))


func _open_scene(scene_path: String) -> void:
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("Failed to open test scene: %s (%s)" % [scene_path, error])
