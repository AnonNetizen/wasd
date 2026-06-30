extends SceneTree

const OUTPUT_SCENE_PATH := "res://scenes/mycelium_growth_test.tscn"
const SCENE_SCRIPT := preload("res://scripts/mycelium_growth_test.gd")


func _initialize() -> void:
	var scene_root := Node2D.new()
	scene_root.name = "MyceliumGrowthTest"
	scene_root.set_script(SCENE_SCRIPT)

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
