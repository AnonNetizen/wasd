extends SceneTree

const OUTPUT_SCENE_PATH: String = "res://scenes/polygon_apple_test.tscn"
const SCENE_SCRIPT := preload("res://scripts/polygon_apple_test.gd")


func _initialize() -> void:
	var scene_root := Control.new()
	scene_root.name = "PolygonAppleTest"
	scene_root.set_script(SCENE_SCRIPT)
	scene_root.anchor_right = 1.0
	scene_root.anchor_bottom = 1.0
	scene_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	scene_root.grow_vertical = Control.GROW_DIRECTION_BOTH

	var packed_scene := PackedScene.new()
	var pack_error := packed_scene.pack(scene_root)
	if pack_error != OK:
		push_error(
			"Failed to pack Polygon apple test scene: %s"
			% error_string(pack_error)
		)
		scene_root.free()
		quit(pack_error)
		return
	var save_error := ResourceSaver.save(
		packed_scene,
		OUTPUT_SCENE_PATH
	)
	scene_root.free()
	if save_error != OK:
		push_error(
			"Failed to save Polygon apple test scene: %s"
			% error_string(save_error)
		)
		quit(save_error)
		return
	print("Saved scene: %s" % OUTPUT_SCENE_PATH)
	quit(0)
