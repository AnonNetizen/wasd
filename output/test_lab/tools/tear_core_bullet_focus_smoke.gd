extends SceneTree

const SCENE_PATH: String = "res://scenes/tear_core_bullet_focus_test.tscn"
const EXPECTED_SAMPLE_COUNT: int = 4

var _failed: bool = false


func _initialize() -> void:
	call_deferred("_run_smoke")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("[TearCoreBulletFocusSmoke] %s" % message)


func _run_smoke() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("[TearCoreBulletFocusSmoke] Failed to load scene: %s" % SCENE_PATH)
		quit(1)
		return

	var scene := packed_scene.instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	await process_frame

	_expect(
		int(scene.call("debug_sample_count")) == EXPECTED_SAMPLE_COUNT,
		"Focus scene must expose two large studies and two actual-scale flights."
	)
	_expect(
		bool(scene.call("debug_focus_pair_matches")),
		"Large player/enemy studies must share identical tear-core geometry."
	)
	_expect(
		float(scene.call("debug_focus_visual_diameter")) >= 270.0,
		"The dedicated tear-core study is not large enough."
	)
	_expect(
		bool(scene.call("debug_all_body_extents_fit")),
		"A tear-core silhouette exceeds its displayed collision circle."
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
		"Focus samples must not create effect child nodes."
	)

	scene.call("debug_set_preview_time", 0.62)
	await process_frame
	_expect(
		int(scene.call("debug_moving_trail_total")) > 0,
		"Actual-scale flights did not build trail samples."
	)
	_expect(
		bool(scene.call("debug_all_trails_bounded")),
		"A focus-scene trail exceeded its fixed capacity."
	)

	scene.call("debug_force_moving_impacts", 0.42)
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
	_expect(
		bool(scene.call("debug_focus_impacts_active")),
		"H-mode did not switch both large studies to active impact previews."
	)
	_expect(
		int(scene.call("debug_sample_count")) == EXPECTED_SAMPLE_COUNT,
		"Focus/impact switching changed the sample node count."
	)

	if _failed:
		quit(1)
		return
	print(
		"[TearCoreBulletFocusSmoke] TEAR CORE FOCUS ALL PASS: "
		+ "oversized same-geometry red/white studies, actual r/speed flights, "
		+ "bounded silhouettes/trails, childless impacts, and clean reset."
	)
	quit(0)
