extends Control

const TEST_SCENES := {
	"Panel/Margin/Rows/AiBitmapButton": "res://scenes/ai_bitmap_button_test.tscn",
	"Panel/Margin/Rows/NativeButton": "res://scenes/native_button_scene.tscn",
	"Panel/Margin/Rows/CompareButton": "res://scenes/ip_button_compare.tscn",
	"Panel/Margin/Rows/CodeButton": "res://scenes/button_preview.tscn",
}

func _ready() -> void:
	for button_path in TEST_SCENES:
		var button := get_node_or_null(button_path) as Button
		if button == null:
			continue
		button.pressed.connect(_open_scene.bind(TEST_SCENES[button_path]))

func _open_scene(scene_path: String) -> void:
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("Failed to open test scene: %s (%s)" % [scene_path, error])
