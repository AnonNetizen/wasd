extends SceneTree

const SCENE_PATH: String = "res://scenes/tear_core_material_switcher_test.tscn"
const EXPECTED_SAMPLE_COUNT: int = 4
const EXPECTED_MATERIAL_LABELS: Array[String] = [
	"0  胶质基准 / GEL",
	"1  水晶玻璃 / CRYSTAL GLASS",
	"2  金属珐琅 / ENAMEL METAL",
	"3  哑光陶瓷 / MATTE CERAMIC",
	"4  能量电浆 / PLASMA ENERGY",
	"5  墨液烟雾 / INK SMOKE",
	"6  矿石晶核 / MINERAL CORE",
]

var _failed: bool = false


func _initialize() -> void:
	call_deferred("_run_smoke")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("[TearCoreMaterialSwitcherSmoke] %s" % message)


func _run_smoke() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("[TearCoreMaterialSwitcherSmoke] Failed to load scene: %s" % SCENE_PATH)
		quit(1)
		return

	var scene := packed_scene.instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	await process_frame

	_expect(
		int(scene.call("debug_sample_count")) == EXPECTED_SAMPLE_COUNT,
		"Scene must keep two large studies and two actual-scale flights."
	)
	_expect(
		int(scene.call("debug_material_item_count")) == EXPECTED_MATERIAL_LABELS.size(),
		"Material picker must expose exactly seven entries."
	)
	_expect(
		Array(scene.call("debug_material_labels")) == EXPECTED_MATERIAL_LABELS,
		"Material picker order or labels changed."
	)
	_expect(
		int(scene.call("debug_selected_material")) == 1,
		"Crystal glass must be the default material."
	)
	_expect(
		bool(scene.call("debug_material_signatures_unique")),
		"All seven material styles must expose unique diagnostic signatures."
	)
	_expect(
		bool(scene.call("debug_focus_pair_matches")),
		"Large player/enemy studies must share identical tear-core geometry."
	)
	_expect(
		bool(scene.call("debug_all_body_extents_fit")),
		"A material body exceeds its displayed collision circle."
	)
	_expect(
		scene.call("debug_player_flight_config").is_equal_approx(Vector2(8.0, 520.0)),
		"Player flight preview must preserve r=8 / 520 px/s."
	)
	_expect(
		scene.call("debug_enemy_flight_config").is_equal_approx(Vector2(5.0, 280.0)),
		"Enemy flight preview must preserve r=5 / 280 px/s."
	)

	var initial_node_count: int = int(scene.call("debug_total_node_count"))
	var locked_geometry_signature: String = str(scene.call("debug_focus_geometry_signature"))
	for round_index in range(4):
		for style in range(EXPECTED_MATERIAL_LABELS.size()):
			scene.call("debug_apply_material_style", style)
			_expect(
				int(scene.call("debug_selected_material")) == style,
				"Material picker did not retain style %d in round %d." % [style, round_index]
			)
			_expect(
				bool(scene.call("debug_all_materials_synced")),
				"Large and actual-scale samples diverged at style %d." % style
			)
			_expect(
				str(scene.call("debug_focus_geometry_signature")) == locked_geometry_signature,
				"Material style %d changed the locked tear-core geometry." % style
			)
			_expect(
				int(scene.call("debug_sample_count")) == EXPECTED_SAMPLE_COUNT,
				"Material switching recreated sample nodes."
			)
			_expect(
				int(scene.call("debug_total_node_count")) == initial_node_count,
				"Material switching accumulated UI or effect nodes."
			)
			_expect(
				bool(scene.call("debug_all_effects_childless")),
				"A material style created effect child nodes."
			)
			scene.call("debug_set_preview_time", 0.62)
			await process_frame
			_expect(
				int(scene.call("debug_moving_trail_total")) > 0,
				"Material style %d did not draw actual-scale trails." % style
			)
			_expect(
				bool(scene.call("debug_all_trails_bounded")),
				"Material style %d exceeded the fixed trail capacity." % style
			)
			scene.call("debug_force_moving_impacts", 0.42)
			await process_frame
			_expect(
				bool(scene.call("debug_no_trail_residue")),
				"Material style %d retained trails during impact." % style
			)
			_expect(
				int(scene.call("debug_total_node_count")) == initial_node_count,
				"Material style %d impact accumulated nodes." % style
			)

	scene.call("debug_apply_material_style", 5)
	scene.call("debug_reset")
	_expect(
		int(scene.call("debug_selected_material")) == 5,
		"R/reset must preserve the current material selection."
	)
	_expect(
		bool(scene.call("debug_all_materials_synced")),
		"R/reset desynchronized material styles."
	)
	_expect(
		bool(scene.call("debug_no_trail_residue")),
		"R/reset retained trail samples."
	)
	scene.call("debug_set_preview_time", 0.35)
	scene.call("debug_set_focus_impact_mode", true)
	_expect(
		bool(scene.call("debug_focus_impacts_active")),
		"H-mode did not switch both large material studies to impact previews."
	)
	_expect(
		int(scene.call("debug_total_node_count")) == initial_node_count,
		"Material impact accumulated nodes."
	)

	if _failed:
		quit(1)
		return
	print(
		"[TearCoreMaterialSwitcherSmoke] ALL PASS: seven ordered materials, "
		+ "crystal default, synchronized same-geometry red/white samples, actual r/speed, "
		+ "bounded trails, stable nodes, childless impacts, and style-preserving reset."
	)
	quit(0)
