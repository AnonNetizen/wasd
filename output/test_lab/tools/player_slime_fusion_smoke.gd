extends SceneTree

const SCENE_PATH: String = "res://scenes/player_slime_fusion_test.tscn"
const EXPECTED_CONTROL_POINTS: int = 20
const EXPECTED_BOUNDARY_POINTS: int = 100
const MAXIMUM_EXTENT: float = 25.001
const MINIMUM_AREA_RATIO: float = 0.82
const MAXIMUM_AREA_RATIO: float = 1.18
const MAXIMUM_TURN_DEGREES: float = 18.0
const MAXIMUM_NEIGHBOR_DELTA: float = 2.8
const MAIN_A_PRIMARY := Color("7e63d8")
const MAIN_A_SECONDARY := Color("3d315e")
const MAIN_A_ACCENT := Color("a995ff")
const MAIN_B_PRIMARY := Color("f2a23a")
const MAIN_B_SECONDARY := Color("6a3f1f")
const MAIN_B_ACCENT := Color("ffd07a")

var _failed: bool = false


func _initialize() -> void:
	call_deferred("_run_smoke")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("[PlayerSlimeFusionSmoke] %s" % message)


func _run_smoke() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("[PlayerSlimeFusionSmoke] Failed to load scene: %s" % SCENE_PATH)
		quit(1)
		return

	var scene := packed_scene.instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await physics_frame

	scene.call("debug_set_fixed_step_mode", true)
	scene.call("debug_set_auto_demo", false)
	scene.call("debug_set_paused", false)
	scene.call("debug_reset")

	_expect(
		scene.get_node_or_null("ActualPlayer/Body") is Polygon2D,
		"Actual player Body Polygon2D is missing."
	)
	_expect(
		scene.get_node_or_null("ActualPlayer/Outline") is Line2D,
		"Actual player Outline is missing."
	)
	_expect(
		scene.get_node_or_null("ActualPlayer/WetRim") is Line2D,
		"Shared-boundary wet rim is missing."
	)
	_expect(
		scene.get_node_or_null("ActualPlayer/Direction/FacingBeam") is Line2D,
		"Center-to-muzzle facing beam is missing."
	)
	_expect(
		int(scene.call("debug_control_point_count")) == EXPECTED_CONTROL_POINTS,
		"Expected %d persistent membrane controls." % EXPECTED_CONTROL_POINTS
	)
	_expect(
		int(scene.call("debug_boundary_point_count")) == EXPECTED_BOUNDARY_POINTS,
		"Expected five quadratic samples per control (%d total)."
		% EXPECTED_BOUNDARY_POINTS
	)
	var body_polygon: PackedVector2Array = scene.call("debug_body_polygon")
	_expect(
		body_polygon.size() == EXPECTED_BOUNDARY_POINTS,
		"Body Polygon2D does not use the authoritative 100-point boundary."
	)
	var beam_end: Vector2 = scene.call("debug_beam_end")
	_expect(
		beam_end.is_equal_approx(Vector2(38.0, 0.0)),
		"Facing beam must terminate at the 38 px muzzle, got %s." % beam_end
	)

	var main_palette: Dictionary = scene.call("debug_preview_main_palette")
	var swap_palette: Dictionary = scene.call("debug_preview_swap_palette")
	_expect_palette(
		main_palette,
		MAIN_A_PRIMARY,
		MAIN_B_PRIMARY,
		MAIN_A_SECONDARY,
		MAIN_B_ACCENT,
		"main preview"
	)
	_expect_palette(
		swap_palette,
		MAIN_B_PRIMARY,
		MAIN_A_PRIMARY,
		MAIN_B_SECONDARY,
		MAIN_A_ACCENT,
		"swapped preview"
	)
	var material := scene.call("debug_body_material") as ShaderMaterial
	_expect(material != null, "Body ShaderMaterial is missing.")
	if material != null:
		_expect(
			_color_close(material.get_shader_parameter("main_primary"), MAIN_A_PRIMARY),
			"Main primary uniform is incorrect."
		)
		_expect(
			_color_close(material.get_shader_parameter("sub_primary"), MAIN_B_PRIMARY),
			"Sub primary uniform is incorrect."
		)
		_expect(
			_color_close(material.get_shader_parameter("rim_secondary"), MAIN_A_SECONDARY),
			"Main secondary rim uniform is incorrect."
		)
	var beam_colors: PackedColorArray = scene.call("debug_beam_gradient_colors")
	_expect(beam_colors.size() == 3, "Facing beam should use a three-stop fade.")
	if beam_colors.size() == 3:
		_expect(
			_color_rgb_close(beam_colors[1], MAIN_B_ACCENT),
			"Facing beam midpoint should use the sub fragment accent."
		)
		_expect(
			beam_colors[0].a < beam_colors[1].a and beam_colors[2].a < beam_colors[1].a,
			"Facing beam must fade at both ends."
		)

	var shader_source: String = str(scene.call("debug_shader_source"))
	_expect(
		shader_source.find("SCREEN_UV") < 0,
		"Dual-vortex shader must not use screen-space coordinates."
	)
	_expect(
		shader_source.find("local_position = VERTEX") >= 0,
		"Dual-vortex shader must anchor flow in character-local coordinates."
	)
	_expect(
		shader_source.find("clockwise_domain") >= 0
		and shader_source.find("counter_domain") >= 0,
		"Shader must retain two counter-rotating flow domains."
	)

	var initial_node_count: int = int(scene.call("debug_scene_node_count"))
	var initial_visual_node_count: int = int(scene.call("debug_visual_node_count"))
	var initial_material_signature: String = str(scene.call("debug_material_signature"))
	_check_frame_gates(scene, "rest")

	scene.call("debug_fire", Vector2(0.88, -0.48))
	_expect(
		int(scene.call("debug_last_impulse_control_count")) == 5,
		"Fire impulse must be distributed across five controls."
	)
	_expect(
		bool(scene.call("debug_last_impulse_controls_are_contiguous")),
		"Fire impulse controls must be contiguous."
	)
	scene.call("debug_hit", Vector2(-25.0, -8.0))
	_expect(
		int(scene.call("debug_last_impulse_control_count")) == 5,
		"Hit impulse must be distributed across five controls."
	)
	_expect(
		bool(scene.call("debug_last_impulse_controls_are_contiguous")),
		"Hit impulse controls must be contiguous."
	)

	var stress_metrics: Dictionary = _run_stress_sequence(scene)
	_expect(
		float(stress_metrics["minimum_area"]) >= MINIMUM_AREA_RATIO,
		"Stress area fell below %.2f: %.4f."
		% [MINIMUM_AREA_RATIO, stress_metrics["minimum_area"]]
	)
	_expect(
		float(stress_metrics["maximum_area"]) <= MAXIMUM_AREA_RATIO,
		"Stress area exceeded %.2f: %.4f."
		% [MAXIMUM_AREA_RATIO, stress_metrics["maximum_area"]]
	)
	_expect(
		float(stress_metrics["maximum_extent"]) <= MAXIMUM_EXTENT,
		"Rendered rim escaped the 25 px hit circle: %.4f."
		% stress_metrics["maximum_extent"]
	)
	_expect(
		float(stress_metrics["maximum_turn"]) <= MAXIMUM_TURN_DEGREES,
		"Stress motion produced a spike-like turn: %.3f degrees."
		% stress_metrics["maximum_turn"]
	)
	_expect(
		float(stress_metrics["maximum_neighbor_delta"]) <= MAXIMUM_NEIGHBOR_DELTA,
		"Stress motion isolated a control point: %.3f px."
		% stress_metrics["maximum_neighbor_delta"]
	)

	var pre_pause_geometry: String = str(scene.call("debug_geometry_signature"))
	var pre_pause_animation: float = float(scene.call("debug_animation_time"))
	var pre_pause_simulation: float = float(scene.call("debug_simulation_time"))
	scene.call("debug_set_paused", true)
	for _frame in range(45):
		scene.call(
			"debug_advance_fixed_step",
			1.0 / 60.0,
			Vector2(220.0, -70.0),
			Vector2(0.9, -0.4)
		)
	_expect(bool(scene.call("debug_is_paused")), "Pause state did not latch.")
	_expect(
		str(scene.call("debug_geometry_signature")) == pre_pause_geometry,
		"Pause changed the membrane geometry."
	)
	_expect(
		is_equal_approx(float(scene.call("debug_animation_time")), pre_pause_animation),
		"Pause advanced the local Shader animation clock."
	)
	_expect(
		is_equal_approx(float(scene.call("debug_simulation_time")), pre_pause_simulation),
		"Pause advanced the scene simulation clock."
	)
	scene.call("debug_set_paused", false)
	scene.call(
		"debug_advance_fixed_step",
		1.0 / 60.0,
		Vector2(140.0, 40.0),
		Vector2.RIGHT
	)
	_expect(
		float(scene.call("debug_animation_time")) > pre_pause_animation,
		"Animation clock did not resume after pause."
	)

	scene.call("debug_reset")
	var before_swap: Dictionary = scene.call("debug_actual_palette")
	scene.call("debug_swap_actual_fragments")
	var after_swap: Dictionary = scene.call("debug_actual_palette")
	_expect(
		_color_close(before_swap["main_primary"], MAIN_A_PRIMARY)
		and _color_close(before_swap["sub_primary"], MAIN_B_PRIMARY),
		"Actual player did not reset to main A / sub B."
	)
	_expect(
		_color_close(after_swap["main_primary"], MAIN_B_PRIMARY)
		and _color_close(after_swap["sub_primary"], MAIN_A_PRIMARY),
		"Actual player main/sub swap did not reverse both primary colors."
	)
	var swapped_material := scene.call("debug_body_material") as ShaderMaterial
	if swapped_material != null:
		_expect(
			_color_close(
				swapped_material.get_shader_parameter("main_primary"),
				MAIN_B_PRIMARY
			),
			"Main primary Shader uniform did not reverse after swap."
		)
		_expect(
			_color_close(
				swapped_material.get_shader_parameter("sub_primary"),
				MAIN_A_PRIMARY
			),
			"Sub primary Shader uniform did not reverse after swap."
		)
	var swapped_beam_colors: PackedColorArray = scene.call("debug_beam_gradient_colors")
	_expect(
		swapped_beam_colors.size() == 3
		and _color_rgb_close(swapped_beam_colors[1], MAIN_A_ACCENT),
		"Facing beam did not switch to the new sub fragment accent."
	)

	var deterministic_a: String = _capture_deterministic_signature(scene)
	var deterministic_b: String = _capture_deterministic_signature(scene)
	_expect(
		deterministic_a == deterministic_b,
		"Identical fixed-step sequences produced different geometry."
	)
	_expect(
		int(scene.call("debug_scene_node_count")) == initial_node_count,
		"Scene node count changed during continuous movement/fire/hit."
	)
	_expect(
		int(scene.call("debug_visual_node_count")) == initial_visual_node_count,
		"Player visual node count changed during simulation."
	)
	_expect(
		str(scene.call("debug_material_signature")) == initial_material_signature,
		"ShaderMaterial or beam Gradient was recreated during simulation."
	)

	if _failed:
		quit(1)
		return
	print(
		(
			"[PlayerSlimeFusionSmoke] area %.4f..%.4f, extent %.4f px, "
			+ "turn %.3f deg, neighbor delta %.3f px."
		) % [
			stress_metrics["minimum_area"],
			stress_metrics["maximum_area"],
			stress_metrics["maximum_extent"],
			stress_metrics["maximum_turn"],
			stress_metrics["maximum_neighbor_delta"],
		]
	)
	print(
		"[PlayerSlimeFusionSmoke] Passed 20/100 topology, 25 px containment, "
		+ "dual-primary local Shader, 38 px beam, five-point impulses, pause, "
		+ "palette swap, stable resources, and deterministic stress checks."
	)
	quit(0)


func _run_stress_sequence(scene: Node2D) -> Dictionary:
	var metrics := {
		"minimum_area": INF,
		"maximum_area": 0.0,
		"maximum_extent": 0.0,
		"maximum_turn": 0.0,
		"maximum_neighbor_delta": 0.0,
	}
	for frame in range(720):
		var phase: float = float(frame) / 60.0
		var motion := Vector2(
			cos(phase * 1.9) * 245.0,
			sin(phase * 2.7) * 205.0
		)
		var aim := Vector2(cos(phase * 0.73), sin(phase * 0.73)).normalized()
		if frame % 31 == 0:
			scene.call("debug_fire", aim)
		if frame % 97 == 53:
			scene.call("debug_hit", -aim * 25.0)
		scene.call("debug_advance_fixed_step", 1.0 / 60.0, motion, aim)
		var area: float = float(scene.call("debug_area_ratio"))
		var extent: float = float(scene.call("debug_maximum_render_extent"))
		var turn: float = float(scene.call("debug_maximum_render_turn_degrees"))
		var neighbor_delta: float = float(
			scene.call("debug_maximum_neighbor_displacement_delta")
		)
		metrics["minimum_area"] = minf(float(metrics["minimum_area"]), area)
		metrics["maximum_area"] = maxf(float(metrics["maximum_area"]), area)
		metrics["maximum_extent"] = maxf(float(metrics["maximum_extent"]), extent)
		metrics["maximum_turn"] = maxf(float(metrics["maximum_turn"]), turn)
		metrics["maximum_neighbor_delta"] = maxf(
			float(metrics["maximum_neighbor_delta"]),
			neighbor_delta
		)
	return metrics


func _capture_deterministic_signature(scene: Node2D) -> String:
	scene.call("debug_set_paused", false)
	scene.call("debug_set_auto_demo", false)
	scene.call("debug_reset")
	for frame in range(240):
		var phase: float = float(frame) / 60.0
		var motion := Vector2(cos(phase * 1.3) * 190.0, sin(phase * 1.8) * 140.0)
		var aim := Vector2(cos(phase * 0.5), sin(phase * 0.5)).normalized()
		if frame in [24, 77, 131, 198]:
			scene.call("debug_fire", aim)
		if frame in [92, 184]:
			scene.call("debug_hit", -aim * 25.0)
		scene.call("debug_advance_fixed_step", 1.0 / 60.0, motion, aim)
	return str(scene.call("debug_geometry_signature"))


func _check_frame_gates(scene: Node2D, label: String) -> void:
	var area: float = float(scene.call("debug_area_ratio"))
	var extent: float = float(scene.call("debug_maximum_render_extent"))
	var turn: float = float(scene.call("debug_maximum_render_turn_degrees"))
	var neighbor_delta: float = float(
		scene.call("debug_maximum_neighbor_displacement_delta")
	)
	_expect(
		area >= MINIMUM_AREA_RATIO and area <= MAXIMUM_AREA_RATIO,
		"%s area ratio is outside the gate: %.4f." % [label, area]
	)
	_expect(
		extent <= MAXIMUM_EXTENT,
		"%s rendered extent escaped the hit circle: %.4f." % [label, extent]
	)
	_expect(
		turn <= MAXIMUM_TURN_DEGREES,
		"%s render turn exceeded the anti-spike gate: %.3f." % [label, turn]
	)
	_expect(
		neighbor_delta <= MAXIMUM_NEIGHBOR_DELTA,
		"%s neighbor displacement delta exceeded the gate: %.3f."
		% [label, neighbor_delta]
	)


func _expect_palette(
	palette: Dictionary,
	main_primary: Color,
	sub_primary: Color,
	main_secondary: Color,
	sub_accent: Color,
	label: String
) -> void:
	_expect(
		_color_close(palette.get("main_primary", Color.TRANSPARENT), main_primary),
		"%s main primary is incorrect." % label
	)
	_expect(
		_color_close(palette.get("sub_primary", Color.TRANSPARENT), sub_primary),
		"%s sub primary is incorrect." % label
	)
	_expect(
		_color_close(palette.get("main_secondary", Color.TRANSPARENT), main_secondary),
		"%s dark rim color is incorrect." % label
	)
	_expect(
		_color_close(palette.get("sub_accent", Color.TRANSPARENT), sub_accent),
		"%s beam accent is incorrect." % label
	)


func _color_close(left: Variant, right: Color) -> bool:
	if not left is Color:
		return false
	var color := left as Color
	return (
		is_equal_approx(color.r, right.r)
		and is_equal_approx(color.g, right.g)
		and is_equal_approx(color.b, right.b)
		and is_equal_approx(color.a, right.a)
	)


func _color_rgb_close(left: Color, right: Color) -> bool:
	return (
		is_equal_approx(left.r, right.r)
		and is_equal_approx(left.g, right.g)
		and is_equal_approx(left.b, right.b)
	)
