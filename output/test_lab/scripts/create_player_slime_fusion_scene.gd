extends SceneTree

const OUTPUT_SCENE_PATH: String = "res://scenes/player_slime_fusion_test.tscn"
const SCENE_SCRIPT_PATH: String = "res://scripts/player_slime_fusion_test.gd"


func _initialize() -> void:
	var scene_script := load(SCENE_SCRIPT_PATH) as Script
	if scene_script == null or not scene_script.can_instantiate():
		push_error("Dual-vortex player slime scene script is not instantiable.")
		quit(1)
		return

	var scene_root := Node2D.new()
	scene_root.name = "PlayerSlimeFusionTest"
	scene_root.set_script(scene_script)

	var packed_scene := PackedScene.new()
	var pack_error: Error = packed_scene.pack(scene_root)
	if pack_error != OK:
		push_error("Failed to pack dual-vortex player slime scene: %s" % pack_error)
		scene_root.free()
		quit(pack_error)
		return

	var save_error: Error = ResourceSaver.save(
		packed_scene,
		OUTPUT_SCENE_PATH,
		ResourceSaver.FLAG_OMIT_EDITOR_PROPERTIES
	)
	if save_error != OK:
		push_error("Failed to save dual-vortex player slime scene: %s" % save_error)
		scene_root.free()
		quit(save_error)
		return

	print("Saved scene: %s" % OUTPUT_SCENE_PATH)
	scene_root.free()
	quit(0)
