extends SceneTree

const SCENE_PATH: String = "res://scenes/glow_orb_bullet_focus_test.tscn"
const SAMPLE_SCRIPT_PATH: String = "res://scripts/glow_orb_bullet_sample.gd"
const EXPECTED_SAMPLE_COUNT: int = 4

var _failed: bool = false


func _initialize() -> void:
	call_deferred("_run_smoke")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("[GlowOrbBulletFocusSmoke] %s" % message)


func _run_smoke() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("[GlowOrbBulletFocusSmoke] Failed to load scene: %s" % SCENE_PATH)
		quit(1)
		return

	var scene := packed_scene.instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	await process_frame

	_expect(
		int(scene.call("debug_sample_count")) == EXPECTED_SAMPLE_COUNT,
		"Scene must expose two large studies and two actual-scale flights."
	)
	_expect(
		bool(scene.call("debug_circle_geometry_locked")),
		"Player and enemy studies must share the same exact circle geometry."
	)
	_expect(
		bool(scene.call("debug_focus_pair_matches")),
		"Large player/enemy studies must share one geometry signature."
	)
	_expect(
		bool(scene.call("debug_gradient_pair_matches")),
		"Red and white studies must use the same interpolation segment count."
	)
	_expect(
		int(scene.call("debug_gradient_segment_count")) == 96,
		"Orb gradient must use the locked 96-segment interpolation fan."
	)
	_expect(
		bool(scene.call("debug_uses_interpolated_gradient")),
		"Orb body must use vertex-color interpolation rather than color bands."
	)
	_expect(
		float(scene.call("debug_focus_visual_diameter")) >= 280.0,
		"Large glow-orb study is not large enough."
	)
	_expect(
		bool(scene.call("debug_all_body_extents_fit")),
		"A solid orb body exceeds its displayed collision circle."
	)
	_expect(
		bool(scene.call("debug_no_external_glow")),
		"An orb still reports an external glow extent."
	)
	_expect(
		bool(scene.call("debug_enemy_is_red_dominant")),
		"Enemy orb main body is not red-dominant."
	)
	_expect(
		scene.call("debug_player_flight_config").is_equal_approx(Vector2(8.0, 520.0)),
		"Player flight preview must preserve r=8 / 520 px/s."
	)
	_expect(
		scene.call("debug_enemy_flight_config").is_equal_approx(Vector2(5.0, 280.0)),
		"Enemy flight preview must preserve r=5 / 280 px/s."
	)
	_expect(
		bool(scene.call("debug_all_effects_childless")),
		"Glow-orb samples must not create effect child nodes."
	)

	var sample_source: String = FileAccess.get_file_as_string(SAMPLE_SCRIPT_PATH)
	_expect(not sample_source.is_empty(), "Glow-orb sample source could not be read.")
	for forbidden_token in [
		"ShaderMaterial",
		"Texture2D",
		"GradientTexture",
		"PLAYER_OUTLINE",
		"ENEMY_OUTLINE",
		"PLAYER_GLOW",
		"ENEMY_GLOW",
		"_color(\"glow\"",
		"GRADIENT_STEP_COUNT",
		"ring_radius",
	]:
		_expect(
			not sample_source.contains(forbidden_token),
			"Glow-orb sample must not depend on %s." % forbidden_token
		)
	_expect(
		sample_source.contains("draw_primitive("),
		"Orb sample must render its continuous gradient with interpolated primitives."
	)

	scene.call("debug_set_preview_time", 0.62)
	await process_frame
	_expect(
		int(scene.call("debug_moving_trail_total")) > 0,
		"Actual-scale flights did not build trail samples."
	)
	_expect(
		bool(scene.call("debug_all_trails_bounded")),
		"A glow-orb trail exceeded its fixed capacity."
	)

	scene.call("debug_force_moving_impacts", 0.42)
	await process_frame
	_expect(
		bool(scene.call("debug_no_trail_residue")),
		"Impact did not clear actual-scale flight trails."
	)
	_expect(
		bool(scene.call("debug_all_effects_childless")),
		"Impact accumulated child nodes."
	)

	scene.call("debug_reset")
	_expect(
		bool(scene.call("debug_no_trail_residue")),
		"Reset retained trail samples."
	)
	scene.call("debug_set_preview_time", 0.35)
	scene.call("debug_set_focus_impact_mode", true)
	await process_frame
	_expect(
		bool(scene.call("debug_focus_impacts_active")),
		"H-mode did not switch both large studies to impact previews."
	)
	_expect(
		int(scene.call("debug_sample_count")) == EXPECTED_SAMPLE_COUNT,
		"Focus/impact switching changed the sample node count."
	)

	if _failed:
		quit(1)
		return
	print(
		"[GlowOrbBulletFocusSmoke] ALL PASS: textureless circular red/white bodies, "
		+ "no outline or external glow, vertex-interpolated gradients, bounded trails, actual r/speed, "
		+ "childless impacts, "
		+ "and clean reset."
	)
	quit(0)
