extends Control

const TEST_SCENES := {
	"Panel/Margin/Rows/Orthographic3DButton": "res://scenes/orthographic_3d_test.tscn",
	"Panel/Margin/Rows/AiBitmapButton": "res://scenes/ai_bitmap_button_test.tscn",
	"Panel/Margin/Rows/NativeButton": "res://scenes/native_button_scene.tscn",
	"Panel/Margin/Rows/CompareButton": "res://scenes/ip_button_compare.tscn",
	"Panel/Margin/Rows/CodeButton": "res://scenes/button_preview.tscn",
}

const EXTRA_TEST_SCENES := [
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
]


func _ready() -> void:
	_add_extra_test_buttons()
	for button_path in TEST_SCENES:
		var button := get_node_or_null(button_path) as Button
		if button == null:
			continue
		button.pressed.connect(_open_scene.bind(TEST_SCENES[button_path]))


func _add_extra_test_buttons() -> void:
	var panel := get_node_or_null("Panel") as PanelContainer
	if panel != null:
		panel.anchor_top = 0.10
		panel.anchor_bottom = 0.90

	var rows := get_node_or_null("Panel/Margin/Rows") as VBoxContainer
	if rows == null:
		return

	rows.add_theme_constant_override("separation", 12)
	var template := rows.get_node_or_null("CodeButton") as Button
	for scene_info in EXTRA_TEST_SCENES:
		var button: Button
		if template != null:
			button = template.duplicate() as Button
		else:
			button = Button.new()
		button.name = String(scene_info["button_name"])
		button.text = String(scene_info["label"])
		button.custom_minimum_size.y = 54.0
		rows.add_child(button)
		button.pressed.connect(_open_scene.bind(String(scene_info["scene_path"])))


func _open_scene(scene_path: String) -> void:
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("Failed to open test scene: %s (%s)" % [scene_path, error])
