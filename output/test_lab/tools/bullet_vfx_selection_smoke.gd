extends SceneTree

const EXPECTED_VARIANT_COUNT: int = 6
const EXPECTED_SAMPLE_COUNT: int = 24
const SCENE_PATH: String = "res://scenes/bullet_vfx_selection_test.tscn"

var _failed: bool = false


func _initialize() -> void:
	call_deferred("_run_smoke")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("[BulletVfxSelectionSmoke] %s" % message)


func _run_smoke() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("[BulletVfxSelectionSmoke] Failed to load scene: %s" % SCENE_PATH)
		quit(1)
		return

	var scene := packed_scene.instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	await process_frame

	_expect(
		int(scene.call("debug_variant_count")) == EXPECTED_VARIANT_COUNT,
		"Selection wall must expose exactly six variants."
	)
	_expect(
		int(scene.call("debug_team_pair_count")) == EXPECTED_VARIANT_COUNT,
		"Every variant must expose one white/red team pair."
	)
	_expect(
		int(scene.call("debug_sample_count")) == EXPECTED_SAMPLE_COUNT,
		"Selection wall must expose 24 static/moving samples."
	)
	_expect(
		bool(scene.call("debug_geometry_pairs_match")),
		"White and red versions must share identical geometry."
	)
	_expect(
		int(scene.call("debug_unique_geometry_count")) == EXPECTED_VARIANT_COUNT,
		"All six candidates must expose distinct silhouette geometry."
	)
	_expect(
		bool(scene.call("debug_all_body_extents_fit")),
		"A primary bullet silhouette exceeds its declared collision radius."
	)
	_expect(
		bool(scene.call("debug_red_palette_dominant")),
		"Enemy shell palette is not red-dominant."
	)
	_expect(
		bool(scene.call("debug_all_effects_childless")),
		"Bullet effects must not accumulate child nodes."
	)

	scene.call("debug_set_preview_time", 0.43)
	await process_frame
	_expect(
		bool(scene.call("debug_all_trails_bounded")),
		"A trail exceeded its fixed sample capacity."
	)
	_expect(
		int(scene.call("debug_moving_trail_sample_total")) > 0,
		"Moving previews did not build trail history."
	)

	scene.call("debug_force_all_impacts", 0.45)
	await process_frame
	_expect(
		bool(scene.call("debug_no_trail_residue")),
		"Impact did not clear all trail samples."
	)
	_expect(
		int(scene.call("debug_sample_count")) == EXPECTED_SAMPLE_COUNT,
		"Impact created or removed sample nodes."
	)
	_expect(
		bool(scene.call("debug_all_effects_childless")),
		"Impact accumulated child effect nodes."
	)

	scene.call("debug_reset")
	_expect(
		bool(scene.call("debug_no_trail_residue")),
		"Reset retained trail samples from the previous cycle."
	)
	scene.call("debug_set_preview_time", 0.43)
	await process_frame
	_expect(
		int(scene.call("debug_sample_count")) == EXPECTED_SAMPLE_COUNT,
		"Reset changed the sample node count."
	)
	_expect(
		bool(scene.call("debug_all_trails_bounded")),
		"Reset/replay produced an unbounded trail."
	)

	if _failed:
		quit(1)
		return
	print(
		"[BulletVfxSelectionSmoke] BULLET VFX SELECTION ALL PASS: "
		+ "six variants, same-geometry red/white pairs, bounded silhouettes, "
		+ "bounded trails, childless impacts, and deterministic reset."
	)
	quit(0)
