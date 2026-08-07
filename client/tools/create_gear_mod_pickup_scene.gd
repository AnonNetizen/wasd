extends SceneTree


const OUTPUT_SCENE_PATH: String = "res://scenes/gameplay/gear_mod_pickup.tscn"
const SCRIPT_PATH: String = "res://scripts/gameplay/gear_mod_pickup.gd"
const TEXTURE_PATH: String = "res://assets/icons/gear_mod_pickup_cpu.svg"
const SHADER_PATH: String = "res://shaders/gear_mod_pickup_star_window.gdshader"
const ICON_SCALE: float = 0.084


func _initialize() -> void:
	var scene_root := Node2D.new()
	scene_root.name = "GearModPickup"
	scene_root.z_index = -8
	scene_root.set_script(load(SCRIPT_PATH) as Script)

	var visual := Node2D.new()
	visual.name = "Visual"
	scene_root.add_child(visual)
	visual.owner = scene_root

	var icon := Sprite2D.new()
	icon.name = "Icon"
	icon.texture = load(TEXTURE_PATH) as Texture2D
	icon.scale = Vector2.ONE * ICON_SCALE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var material := ShaderMaterial.new()
	material.shader = load(SHADER_PATH) as Shader
	material.set_shader_parameter("star_scale", 1.8)
	material.set_shader_parameter("outline_texels", 23.8)
	material.set_shader_parameter(
		"outline_color",
		Color(0.407843, 0.737255, 0.866667, 1.0)
	)
	icon.material = material
	visual.add_child(icon)
	icon.owner = scene_root

	var packed_scene := PackedScene.new()
	var pack_error: Error = packed_scene.pack(scene_root)
	if pack_error != OK:
		push_error("Failed to pack Gear Mod pickup scene: %s" % pack_error)
		scene_root.free()
		quit(pack_error)
		return
	var save_error: Error = ResourceSaver.save(
		packed_scene,
		OUTPUT_SCENE_PATH,
		ResourceSaver.FLAG_OMIT_EDITOR_PROPERTIES
	)
	if save_error != OK:
		push_error("Failed to save Gear Mod pickup scene: %s" % save_error)
		scene_root.free()
		quit(save_error)
		return
	print("Saved scene: %s" % OUTPUT_SCENE_PATH)
	scene_root.free()
	quit(0)
