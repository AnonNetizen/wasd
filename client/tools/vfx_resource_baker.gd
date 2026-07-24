# Doc: docs/代码/visual_effects.md
extends SceneTree
## Deterministically creates the built-in VFX preset resources and composite scenes.


const PRESET_ROOT: String = "res://resources/vfx/presets"
const CURVE_ROOT: String = "res://resources/vfx/curves"
const COMPOSITE_ROOT: String = "res://scenes/vfx/composites"
const ACTOR_AFTERIMAGE_SCRIPT := preload(
	"res://scripts/vfx/vfx_actor_afterimage.gd"
)
const RIBBON_TRAIL_SCRIPT := preload(
	"res://scripts/vfx/vfx_ribbon_trail.gd"
)


func _initialize() -> void:
	var success: bool = true
	success = _ensure_directories() and success
	success = _save_target_presets() and success
	success = _save_shared_curves() and success
	success = _save_actor_afterimage(
		"%s/actor_defeat_afterimage.tscn" % COMPOSITE_ROOT
	) and success
	success = _save_ring_composite(
		"%s/skill_cast_pulse.tscn" % COMPOSITE_ROOT,
		Color(1.0, 0.76, 0.24, 1.0),
		0.34,
		false
	) and success
	success = _save_ring_composite(
		"%s/ground_telegraph.tscn" % COMPOSITE_ROOT,
		Color(1.0, 0.18, 0.12, 1.0),
		0.5,
		true
	) and success
	success = _save_screen_flash(
		"%s/player_damage_screen_flash.tscn" % COMPOSITE_ROOT,
		0.22,
		0.12
	) and success
	success = _save_screen_flash(
		"%s/player_damage_screen_flash_reduced.tscn" % COMPOSITE_ROOT,
		0.08,
		0.08
	) and success
	success = _ensure_bullet_trail() and success
	print("vfx resource bake passed" if success else "vfx resource bake failed")
	quit(0 if success else 1)


func _ensure_directories() -> bool:
	for resource_path: String in [PRESET_ROOT, CURVE_ROOT, COMPOSITE_ROOT]:
		var absolute_path: String = ProjectSettings.globalize_path(resource_path)
		var error: Error = DirAccess.make_dir_recursive_absolute(absolute_path)
		if error != OK:
			push_error("[VfxResourceBaker] failed to create %s: %d" % [
				resource_path,
				error,
			])
			return false
	return true


func _save_shared_curves() -> bool:
	var drift := Curve.new()
	drift.min_value = 0.0
	drift.max_value = 1.0
	drift.bake_resolution = 64
	drift.add_point(Vector2(0.0, 0.0))
	drift.add_point(Vector2(0.35, 0.22))
	drift.add_point(Vector2(1.0, 1.0))
	if not _save_resource(drift, "%s/damage_number_drift.tres" % CURVE_ROOT):
		return false

	var alpha := Curve.new()
	alpha.min_value = 0.0
	alpha.max_value = 1.0
	alpha.bake_resolution = 64
	alpha.add_point(Vector2(0.0, 1.0))
	alpha.add_point(Vector2(0.68, 0.86))
	alpha.add_point(Vector2(1.0, 0.0))
	if not _save_resource(alpha, "%s/damage_number_alpha.tres" % CURVE_ROOT):
		return false

	var scale_curve := Curve.new()
	scale_curve.min_value = 0.0
	scale_curve.max_value = 2.0
	scale_curve.bake_resolution = 64
	scale_curve.add_point(Vector2(0.0, 1.12))
	scale_curve.add_point(Vector2(0.24, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.92))
	return _save_resource(
		scale_curve,
		"%s/damage_number_scale.tres" % CURVE_ROOT
	)


func _save_target_presets() -> bool:
	var player_hurt := VfxTargetAnimationPreset.new()
	player_hurt.animation_name = &"flash"
	player_hurt.target_path = NodePath("Visual/Body")
	player_hurt.duration = 0.16
	player_hurt.tint = Color(1.0, 0.22, 0.18, 1.0)
	if not _save_resource(
		player_hurt,
		"%s/player_hurt_flash.tres" % PRESET_ROOT
	):
		return false

	var enemy_hit := VfxTargetAnimationPreset.new()
	enemy_hit.animation_name = &"flash"
	enemy_hit.target_path = NodePath("Visual/Body")
	enemy_hit.duration = 0.16
	enemy_hit.tint = Color(1.0, 0.92, 0.72, 1.0)
	if not _save_resource(
		enemy_hit,
		"%s/enemy_hit_flash.tres" % PRESET_ROOT
	):
		return false

	var enemy_defeat := VfxTargetAnimationPreset.new()
	enemy_defeat.animation_name = &"defeat"
	enemy_defeat.target_path = NodePath("Visual")
	enemy_defeat.duration = 0.18
	enemy_defeat.tint = Color(1.0, 0.42, 0.12, 1.0)
	enemy_defeat.start_scale = Vector2.ONE
	enemy_defeat.end_scale = Vector2.ONE * 1.35
	enemy_defeat.end_alpha = 0.0
	enemy_defeat.restore_target_state = false
	return _save_resource(
		enemy_defeat,
		"%s/enemy_defeat.tres" % PRESET_ROOT
	)


func _save_ring_composite(
		resource_path: String,
		accent: Color,
		duration: float,
		ground_style: bool
	) -> bool:
	var root := VfxInstance.new()
	root.name = "VfxComposite"

	var core := VfxRingGeometry.new()
	core.name = "CoreRing"
	core.radius = 18.0 if not ground_style else 30.0
	core.width = 4.0
	core.tick_count = 8 if not ground_style else 12
	core.tick_length = 7.0
	core.ring_color = accent
	root.add_child(core)
	core.owner = root

	var hot_edge := VfxRingGeometry.new()
	hot_edge.name = "HotEdge"
	hot_edge.radius = 23.0 if not ground_style else 36.0
	hot_edge.width = 1.5
	hot_edge.tick_count = 4
	hot_edge.tick_length = 4.0
	hot_edge.ring_color = Color(1.0, 0.98, 0.88, 0.9)
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/vfx/energy_glow.gdshader") as Shader
	material.set_shader_parameter("glow_color", accent)
	material.set_shader_parameter("intensity", 1.35)
	hot_edge.material = material
	root.add_child(hot_edge)
	hot_edge.owner = root

	if not ground_style:
		var particles := CPUParticles2D.new()
		particles.name = "AccentParticles"
		particles.amount = 12
		particles.lifetime = duration
		particles.one_shot = true
		particles.explosiveness = 1.0
		particles.direction = Vector2.UP
		particles.spread = 180.0
		particles.gravity = Vector2.ZERO
		particles.initial_velocity_min = 28.0
		particles.initial_velocity_max = 52.0
		particles.scale_amount_min = 1.0
		particles.scale_amount_max = 2.0
		particles.color = accent
		root.add_child(particles)
		particles.owner = root

	var animation_player := AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	root.add_child(animation_player)
	animation_player.owner = root
	_add_ring_animations(animation_player, duration, ground_style)

	return _save_scene(root, resource_path)


func _save_actor_afterimage(resource_path: String) -> bool:
	var root: Node2D = ACTOR_AFTERIMAGE_SCRIPT.new() as Node2D
	root.name = "ActorDefeatAfterimage"

	var visual := Node2D.new()
	visual.name = "Visual"
	root.add_child(visual)
	visual.owner = root

	var outline := Polygon2D.new()
	outline.name = "Outline"
	outline.color = Color(0.12, 0.04, 0.03, 0.72)
	visual.add_child(outline)
	outline.owner = root

	var body := Polygon2D.new()
	body.name = "Body"
	body.color = Color(1.0, 0.32, 0.12, 0.72)
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/vfx/energy_glow.gdshader") as Shader
	material.set_shader_parameter("glow_color", Color(1.0, 0.22, 0.08, 1.0))
	material.set_shader_parameter("intensity", 1.1)
	body.material = material
	visual.add_child(body)
	body.owner = root

	var animation_player := AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	root.add_child(animation_player)
	animation_player.owner = root
	var library := AnimationLibrary.new()
	var reset := Animation.new()
	reset.length = 0.01
	_add_value_track(reset, NodePath(".:scale"), [0.0], [Vector2.ONE])
	_add_value_track(reset, NodePath(".:modulate"), [0.0], [Color.WHITE])
	library.add_animation(&"RESET", reset)
	var playback := Animation.new()
	playback.length = 0.45
	_add_value_track(
		playback,
		NodePath(".:scale"),
		[0.0, 0.45],
		[Vector2.ONE, Vector2.ONE * 1.18]
	)
	_add_value_track(
		playback,
		NodePath(".:modulate"),
		[0.0, 0.1, 0.45],
		[
			Color(1.0, 1.0, 1.0, 0.78),
			Color(1.0, 0.62, 0.42, 0.58),
			Color(0.62, 0.16, 0.08, 0.0),
		]
	)
	library.add_animation(&"play", playback)
	animation_player.add_animation_library(&"", library)
	return _save_scene(root, resource_path)


func _ensure_bullet_trail() -> bool:
	var resource_path: String = "res://scenes/gameplay/bullet.tscn"
	var raw_scene: Resource = load(resource_path)
	if not raw_scene is PackedScene:
		push_error("[VfxResourceBaker] bullet scene is not a PackedScene")
		return false
	var root: Node = (raw_scene as PackedScene).instantiate()
	var existing: Node = root.get_node_or_null("RibbonTrail")
	if existing == null:
		var trail: Line2D = RIBBON_TRAIL_SCRIPT.new() as Line2D
		trail.name = "RibbonTrail"
		trail.width = 5.0
		trail.default_color = Color(1.0, 0.76, 0.22, 0.72)
		trail.z_index = -1
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([
			Color(1.0, 0.35, 0.08, 0.0),
			Color(1.0, 0.96, 0.52, 0.82),
		])
		trail.gradient = gradient
		var material := ShaderMaterial.new()
		material.shader = load("res://shaders/vfx/energy_glow.gdshader") as Shader
		material.set_shader_parameter("glow_color", Color(1.0, 0.55, 0.12, 1.0))
		material.set_shader_parameter("intensity", 1.0)
		trail.material = material
		root.add_child(trail)
		trail.owner = root
	return _save_scene(root, resource_path)


func _add_ring_animations(
		player: AnimationPlayer,
		duration: float,
		ground_style: bool
	) -> void:
	var library := AnimationLibrary.new()
	var reset := Animation.new()
	reset.length = 0.01
	_add_value_track(
		reset,
		NodePath(".:scale"),
		[0.0],
		[Vector2.ONE]
	)
	_add_value_track(
		reset,
		NodePath(".:modulate"),
		[0.0],
		[Color.WHITE]
	)
	_add_value_track(
		reset,
		NodePath("CoreRing:rotation"),
		[0.0],
		[0.0]
	)
	_add_value_track(
		reset,
		NodePath("HotEdge:rotation"),
		[0.0],
		[0.0]
	)
	library.add_animation(&"RESET", reset)

	var playback := Animation.new()
	playback.length = duration
	_add_value_track(
		playback,
		NodePath(".:scale"),
		[0.0, duration],
		[
			Vector2.ONE * (0.9 if ground_style else 0.68),
			Vector2.ONE * (1.08 if ground_style else 1.42),
		]
	)
	_add_value_track(
		playback,
		NodePath(".:modulate"),
		[0.0, duration * 0.18, duration],
		[
			Color(1.0, 1.0, 1.0, 0.0),
			Color.WHITE,
			Color(1.0, 1.0, 1.0, 0.0),
		]
	)
	_add_value_track(
		playback,
		NodePath("CoreRing:rotation"),
		[0.0, duration],
		[0.0, PI * 0.25]
	)
	_add_value_track(
		playback,
		NodePath("HotEdge:rotation"),
		[0.0, duration],
		[0.0, -PI * 0.5]
	)
	library.add_animation(&"play", playback)
	player.add_animation_library(&"", library)


func _save_screen_flash(
		resource_path: String,
		peak_alpha: float,
		duration: float
	) -> bool:
	var root := ScreenVfxInstance.new()
	root.name = "ScreenFlash"
	root.color = Color(1.0, 0.12, 0.08, 0.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var animation_player := AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	root.add_child(animation_player)
	animation_player.owner = root
	var library := AnimationLibrary.new()
	var reset := Animation.new()
	reset.length = 0.01
	_add_value_track(
		reset,
		NodePath(".:color"),
		[0.0],
		[Color(1.0, 0.12, 0.08, 0.0)]
	)
	library.add_animation(&"RESET", reset)
	var playback := Animation.new()
	playback.length = duration
	_add_value_track(
		playback,
		NodePath(".:color"),
		[0.0, duration * 0.25, duration],
		[
			Color(1.0, 0.12, 0.08, 0.0),
			Color(1.0, 0.12, 0.08, peak_alpha),
			Color(1.0, 0.12, 0.08, 0.0),
		]
	)
	library.add_animation(&"play", playback)
	animation_player.add_animation_library(&"", library)
	return _save_scene(root, resource_path)


func _add_value_track(
		animation: Animation,
		path: NodePath,
		times: Array[float],
		values: Array
	) -> void:
	var track: int = animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, path)
	animation.value_track_set_update_mode(
		track,
		Animation.UPDATE_CONTINUOUS
	)
	for index: int in range(times.size()):
		animation.track_insert_key(track, times[index], values[index])


func _save_resource(resource: Resource, resource_path: String) -> bool:
	var error: Error = ResourceSaver.save(resource, resource_path)
	if error != OK:
		push_error("[VfxResourceBaker] failed to save %s: %d" % [
			resource_path,
			error,
		])
		return false
	return true


func _save_scene(root: Node, resource_path: String) -> bool:
	var packed := PackedScene.new()
	var pack_error: Error = packed.pack(root)
	if pack_error != OK:
		push_error("[VfxResourceBaker] failed to pack %s: %d" % [
			resource_path,
			pack_error,
		])
		root.free()
		return false
	var save_error: Error = ResourceSaver.save(packed, resource_path)
	root.free()
	if save_error != OK:
		push_error("[VfxResourceBaker] failed to save %s: %d" % [
			resource_path,
			save_error,
		])
		return false
	return true
