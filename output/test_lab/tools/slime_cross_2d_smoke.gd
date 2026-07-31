extends SceneTree

const EXPECTED_CONTROL_POINT_COUNT: int = 20
const EXPECTED_CONCAVE_CORNER_COUNT: int = 4
const SCENE_PATH: String = "res://scenes/slime_cross_2d_test.tscn"

var _failed: bool = false


func _initialize() -> void:
	call_deferred("_run_smoke")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("[SlimeCross2DSmoke] %s" % message)


func _run_smoke() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("[SlimeCross2DSmoke] Failed to load scene: %s" % SCENE_PATH)
		quit(1)
		return

	var scene := packed_scene.instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await physics_frame

	var slime_cross := scene.get_node_or_null("SlimeCross") as Node2D
	var overlay := scene.get_node_or_null("Overlay") as CanvasLayer
	_expect(slime_cross != null, "Dynamic 2D slime cross is missing.")
	_expect(overlay != null, "Experiment overlay is missing.")
	_expect(
		scene.call("debug_control_point_count") == EXPECTED_CONTROL_POINT_COUNT,
		"Cross contour should expose %d control points." % EXPECTED_CONTROL_POINT_COUNT
	)
	_expect(
		scene.call("debug_concave_corner_count") == EXPECTED_CONCAVE_CORNER_COUNT,
		"Cross should preserve exactly four structural concave corners."
	)

	scene.call("debug_set_auto_pulse", false)
	scene.call("debug_reset")
	await physics_frame
	var rest_size: Vector2 = scene.call("debug_silhouette_size")
	var rest_area_ratio: float = scene.call("debug_area_ratio")
	var rest_deformation: float = scene.call("debug_deformation_amount")
	var rest_arm_span: float = scene.call("debug_arm_span")
	var rest_stem_width: float = scene.call("debug_stem_width")
	var rest_notch_clearance: float = scene.call("debug_notch_clearance")
	var rest_maximum_turn: float = scene.call("debug_maximum_render_turn_degrees")
	_expect(
		rest_size.y > rest_size.x * 1.55,
		"Rest shape no longer reads as a tall cross silhouette: %s." % rest_size
	)
	_expect(
		rest_arm_span > rest_stem_width * 2.75,
		"Horizontal arms are no longer distinct from the vertical stem."
	)
	_expect(
		rest_notch_clearance > 62.0,
		"Resting concave notches are too shallow: %.2f." % rest_notch_clearance
	)
	_expect(
		absf(rest_area_ratio - 1.0) < 0.03,
		"Rest shape should begin near its authored area, got %.3f." % rest_area_ratio
	)
	_expect(
		rest_maximum_turn < 45.0,
		"Bounded corner rounding is too sharp at rest: %.2f degrees." % rest_maximum_turn
	)

	scene.call("debug_poke", Vector2(-120.0, -102.0), 1.2)
	for _frame in range(9):
		await physics_frame
		await process_frame
	var impact_deformation: float = scene.call("debug_deformation_amount")
	var impact_area_ratio: float = scene.call("debug_area_ratio")
	var impact_notch_clearance: float = scene.call("debug_notch_clearance")
	var impact_maximum_turn: float = scene.call("debug_maximum_render_turn_degrees")
	var impact_displacement_delta: float = scene.call(
		"debug_maximum_neighbor_displacement_delta"
	)
	_expect(
		impact_deformation > rest_deformation + 5.0,
		"Localized arm poke did not produce a readable deformation."
	)
	_expect(
		impact_area_ratio > 0.76 and impact_area_ratio < 1.24,
		"Area pressure failed during the arm impact: %.3f." % impact_area_ratio
	)
	_expect(
		impact_notch_clearance > 34.0,
		"Concave arm notch collapsed during local deformation."
	)
	_expect(
		impact_maximum_turn < 46.0,
		"Local deformation produced a spike-like render turn: %.2f degrees."
		% impact_maximum_turn
	)
	_expect(
		impact_displacement_delta < 12.0,
		"Neighbor displacement diverged into a point spike: %.2f px."
		% impact_displacement_delta
	)

	for _frame in range(170):
		await physics_frame
	var recovered_deformation: float = scene.call("debug_deformation_amount")
	var recovered_notch_clearance: float = scene.call("debug_notch_clearance")
	_expect(
		recovered_deformation < impact_deformation * 0.48,
		"Spring membrane did not recover toward the authored cross."
	)
	_expect(
		recovered_notch_clearance > rest_notch_clearance * 0.84,
		"Concave notch did not recover after the local poke."
	)

	scene.call("debug_reset")
	var burst_points: Array[Vector2] = [
		Vector2(-120.0, -105.0),
		Vector2(120.0, -91.0),
		Vector2(29.0, -208.0),
		Vector2(-38.0, 116.0),
	]
	for pulse_index in range(8):
		scene.call("debug_poke", burst_points[pulse_index % burst_points.size()], 1.1)
		for _frame in range(2):
			await physics_frame
	var burst_maximum_turn: float = scene.call("debug_maximum_render_turn_degrees")
	var burst_displacement_delta: float = scene.call(
		"debug_maximum_neighbor_displacement_delta"
	)
	var burst_notch_clearance: float = scene.call("debug_notch_clearance")
	_expect(
		burst_maximum_turn < 50.0,
		"Repeated motion produced a spike-like render turn: %.2f degrees."
		% burst_maximum_turn
	)
	_expect(
		burst_displacement_delta < 24.0,
		"Repeated motion created an isolated point displacement: %.2f px."
		% burst_displacement_delta
	)
	_expect(
		burst_notch_clearance > 26.0,
		"Repeated motion collapsed a structural cross notch."
	)

	scene.call("debug_reset")
	await physics_frame
	scene.call("debug_squash", 1.0)
	for _frame in range(9):
		await physics_frame
	var squash_deformation: float = scene.call("debug_deformation_amount")
	var squash_size: Vector2 = scene.call("debug_silhouette_size")
	_expect(
		squash_deformation > recovered_deformation + 4.0,
		"Squash action did not excite the 2D membrane."
	)
	_expect(
		squash_size.y > rest_size.y * 0.74,
		"Squash destroyed the recognizable vertical cross silhouette."
	)

	if _failed:
		quit(1)
		return
	print(
		(
			"[SlimeCross2DSmoke] Curvature rest=%.2f impact=%.2f burst=%.2f deg; "
			+ "neighbor delta impact=%.2f burst=%.2f px."
		) % [
			rest_maximum_turn,
			impact_maximum_turn,
			burst_maximum_turn,
			impact_displacement_delta,
			burst_displacement_delta,
		]
	)
	print(
		"[SlimeCross2DSmoke] Passed concave silhouette, arm/stem readability, "
		+ "bounded curvature, displacement continuity, area pressure, recovery, "
		+ "repeated motion, and squash checks."
	)
	quit(0)
