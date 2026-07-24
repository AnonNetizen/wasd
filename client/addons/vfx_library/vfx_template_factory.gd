# Doc: docs/代码/visual_effects.md
@tool
extends RefCounted
## Safe built-in template generator. Generated scenes never reference this add-on.

const TEMPLATE_NAMES := [
	"OneShot",
	"AttachedLoop",
	"GroundTelegraph",
	"UITransition",
	"ScreenOverlay",
	"GeometryComposite",
	"Particle",
	"Flipbook",
	"Shader",
	"AnimationTreeStateful",
]
const TARGET_DIRECTORY := "res://scenes/vfx/custom"
const BASE_EFFECT_SCRIPT_PATH := "res://scripts/vfx/vfx_instance.gd"
const DEFAULT_DURATION := 0.36


func create_scene(effect_id: String, template_name: String) -> Dictionary:
	if not TEMPLATE_NAMES.has(template_name):
		return _error("Unknown VFX template: %s" % template_name)
	var target_path := "%s/%s.tscn" % [TARGET_DIRECTORY, effect_id]
	if ResourceLoader.exists(target_path) or FileAccess.file_exists(target_path):
		return _error("Target scene already exists: %s" % target_path)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(TARGET_DIRECTORY)
	)
	if directory_error != OK:
		return _error("Cannot create VFX directory: %s" % error_string(directory_error))
	var root: Node = _make_root(template_name)
	root.name = _pascal_case(effect_id)
	_attach_runtime_script_if_available(root)
	_add_visual_template(root, template_name)
	_add_animation_system(root, template_name)
	var packed_scene := PackedScene.new()
	var pack_error: Error = packed_scene.pack(root)
	if pack_error != OK:
		root.free()
		return _error("Cannot pack VFX template: %s" % error_string(pack_error))
	var save_error: Error = ResourceSaver.save(packed_scene, target_path)
	root.free()
	if save_error != OK:
		return _error("Cannot save VFX template: %s" % error_string(save_error))
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"resource_path": target_path,
		"duration": DEFAULT_DURATION,
	}


func duplicate_scene(source_path: String, new_id: String) -> Dictionary:
	if not ResourceLoader.exists(source_path, "PackedScene"):
		return _error("Source effect scene does not exist: %s" % source_path)
	var target_path := "%s/%s.tscn" % [TARGET_DIRECTORY, new_id]
	if ResourceLoader.exists(target_path) or FileAccess.file_exists(target_path):
		return _error("Target scene already exists: %s" % target_path)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(TARGET_DIRECTORY)
	)
	if directory_error != OK:
		return _error("Cannot create VFX directory: %s" % error_string(directory_error))
	var source_resource: Resource = load(source_path)
	if not source_resource is PackedScene:
		return _error("Source effect is not a PackedScene: %s" % source_path)
	var duplicate_resource: Resource = source_resource.duplicate(true)
	var save_error: Error = ResourceSaver.save(duplicate_resource, target_path)
	if save_error != OK:
		return _error("Cannot save VFX variant: %s" % error_string(save_error))
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"resource_path": target_path,
	}


func remove_new_scene(resource_path: String) -> void:
	if not resource_path.begins_with(TARGET_DIRECTORY + "/"):
		return
	var absolute_path: String = ProjectSettings.globalize_path(resource_path)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)


func _make_root(template_name: String) -> Node:
	if template_name == "UITransition":
		var control := Control.new()
		control.custom_minimum_size = Vector2(320.0, 180.0)
		return control
	if template_name == "ScreenOverlay":
		var overlay := ColorRect.new()
		overlay.custom_minimum_size = Vector2(720.0, 430.0)
		overlay.color = Color(0.3, 0.75, 1.0, 0.0)
		return overlay
	return Node2D.new()


func _attach_runtime_script_if_available(root: Node) -> void:
	if not root is Node2D:
		return
	if not ResourceLoader.exists(BASE_EFFECT_SCRIPT_PATH, "Script"):
		return
	var script_resource: Resource = load(BASE_EFFECT_SCRIPT_PATH)
	if script_resource is Script and (script_resource as Script).can_instantiate():
		root.set_script(script_resource)


func _add_visual_template(root: Node, template_name: String) -> void:
	match template_name:
		"Particle":
			_add_particles(root)
		"Flipbook":
			_add_flipbook(root)
		"UITransition":
			_add_ui_motion_root(root)
		"ScreenOverlay":
			pass
		"GroundTelegraph":
			_add_ring(root, 56.0, Color(1.0, 0.25, 0.22, 0.9))
			_add_particles(root)
		"GeometryComposite":
			_add_ring(root, 44.0, Color(0.25, 0.82, 1.0, 0.95))
			_add_hot_core(root)
			_add_particles(root)
		"Shader":
			_add_shader_polygon(root)
		"AttachedLoop":
			_add_ring(root, 34.0, Color(0.95, 0.72, 0.2, 0.92))
			_add_particles(root)
		"AnimationTreeStateful":
			_add_hot_core(root)
		_:
			_add_hot_core(root)


func _add_animation_system(root: Node, template_name: String) -> void:
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	root.add_child(player)
	player.owner = root
	var library := AnimationLibrary.new()
	var reset := Animation.new()
	reset.length = 0.0
	var reset_track: int = reset.add_track(Animation.TYPE_VALUE)
	reset.track_set_path(reset_track, NodePath(".:modulate"))
	reset.track_insert_key(reset_track, 0.0, Color.WHITE)
	library.add_animation(&"RESET", reset)

	var animation := Animation.new()
	animation.length = DEFAULT_DURATION
	if template_name == "AttachedLoop" or template_name == "AnimationTreeStateful":
		animation.loop_mode = Animation.LOOP_LINEAR
	var modulate_track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(modulate_track, NodePath(".:modulate"))
	if template_name == "AttachedLoop" or template_name == "AnimationTreeStateful":
		animation.track_insert_key(modulate_track, 0.0, Color.WHITE)
		animation.track_insert_key(
			modulate_track,
			DEFAULT_DURATION * 0.5,
			Color(1.0, 1.0, 1.0, 0.58)
		)
		animation.track_insert_key(modulate_track, DEFAULT_DURATION, Color.WHITE)
	else:
		animation.track_insert_key(modulate_track, 0.0, Color(1.0, 1.0, 1.0, 0.0))
		animation.track_insert_key(
			modulate_track,
			DEFAULT_DURATION * 0.28,
			Color.WHITE
		)
		animation.track_insert_key(
			modulate_track,
			DEFAULT_DURATION,
			Color(1.0, 1.0, 1.0, 0.0)
		)
	library.add_animation(&"play", animation)
	player.add_animation_library(&"", library)
	player.autoplay = &"play"

	if template_name == "AnimationTreeStateful":
		var tree := AnimationTree.new()
		tree.name = "AnimationTree"
		tree.anim_player = NodePath("../AnimationPlayer")
		tree.tree_root = AnimationNodeStateMachine.new()
		tree.active = false
		root.add_child(tree)
		tree.owner = root


func _add_hot_core(root: Node) -> void:
	var core := Polygon2D.new()
	core.name = "HotCore"
	core.polygon = PackedVector2Array(
		[
			Vector2(0.0, -18.0),
			Vector2(18.0, 0.0),
			Vector2(0.0, 18.0),
			Vector2(-18.0, 0.0),
		]
	)
	core.color = Color(0.95, 0.72, 0.2, 0.96)
	root.add_child(core)
	core.owner = root


func _add_ring(root: Node, radius: float, color: Color) -> void:
	var ring := Line2D.new()
	ring.name = "ReadabilityRing"
	ring.width = 4.0
	ring.closed = true
	ring.default_color = color
	var points := PackedVector2Array()
	for index: int in range(48):
		var angle := TAU * float(index) / 48.0
		points.append(Vector2.from_angle(angle) * radius)
	ring.points = points
	root.add_child(ring)
	ring.owner = root


func _add_particles(root: Node) -> void:
	var particles := GPUParticles2D.new()
	particles.name = "SecondaryParticles"
	particles.amount = 18
	particles.lifetime = DEFAULT_DURATION
	particles.one_shot = true
	particles.explosiveness = 0.9
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = 12.0
	process_material.direction = Vector3(0.0, -1.0, 0.0)
	process_material.spread = 180.0
	process_material.initial_velocity_min = 24.0
	process_material.initial_velocity_max = 62.0
	process_material.gravity = Vector3.ZERO
	process_material.color = Color(0.32, 0.82, 1.0, 0.75)
	particles.process_material = process_material
	root.add_child(particles)
	particles.owner = root


func _add_flipbook(root: Node) -> void:
	var sprite := AnimatedSprite2D.new()
	sprite.name = "Flipbook"
	sprite.sprite_frames = SpriteFrames.new()
	root.add_child(sprite)
	sprite.owner = root


func _add_ui_motion_root(root: Node) -> void:
	var panel := Panel.new()
	panel.name = "MotionRoot"
	panel.custom_minimum_size = Vector2(320.0, 180.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	panel.owner = root


func _add_shader_polygon(root: Node) -> void:
	var polygon := Polygon2D.new()
	polygon.name = "ShaderSurface"
	polygon.polygon = PackedVector2Array(
		[
			Vector2(-42.0, -24.0),
			Vector2(42.0, -24.0),
			Vector2(42.0, 24.0),
			Vector2(-42.0, 24.0),
		]
	)
	polygon.color = Color(0.2, 0.72, 1.0, 0.88)
	var shader := Shader.new()
	shader.code = (
		"shader_type canvas_item;\n"
		+ "uniform vec4 tint : source_color = vec4(1.0);\n"
		+ "void fragment() {\n"
		+ "\tvec4 base = texture(TEXTURE, UV) * COLOR;\n"
		+ "\tCOLOR = vec4(base.rgb * tint.rgb, base.a * tint.a);\n"
		+ "}\n"
	)
	var material := ShaderMaterial.new()
	material.shader = shader
	polygon.material = material
	root.add_child(polygon)
	polygon.owner = root


func _pascal_case(value: String) -> String:
	var result := ""
	for segment: String in value.split("_", false):
		result += segment.capitalize().replace(" ", "")
	return result if not result.is_empty() else "VfxEffect"


func _error(message: String) -> Dictionary:
	return {"ok": false, "errors": PackedStringArray([message])}
