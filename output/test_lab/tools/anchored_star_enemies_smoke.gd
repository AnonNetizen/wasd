extends SceneTree

const SCENE_PATH: String = "res://scenes/anchored_star_enemies_test.tscn"
const SHADER_PATH: String = "res://shaders/anchored_star_window.gdshader"


func _initialize() -> void:
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	var shader_source := FileAccess.get_file_as_string(SHADER_PATH)
	if shader_source.is_empty():
		_fail("Failed to read anchored star shader.")
		return
	if not shader_source.contains("vec2 screen_point = (SCREEN_UV - 0.5)"):
		_fail("Star positions are not anchored to SCREEN_UV.")
		return
	if shader_source.contains("MODEL_MATRIX") or shader_source.contains("CANVAS_MATRIX"):
		_fail("Anchored star shader unexpectedly depends on CanvasItem transforms.")
		return

	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		_fail("Failed to load anchored star enemies scene.")
		return
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame

	var enemies := get_nodes_in_group("star_enemy")
	if enemies.size() != 3:
		_fail("Expected exactly three star enemies, got %d." % enemies.size())
		return
	if not bool(scene.call("debug_uses_single_material")):
		_fail("The three star fills do not share one ShaderMaterial instance.")
		return

	var shared_material := scene.call("debug_shared_material") as ShaderMaterial
	if shared_material == null or shared_material.shader == null:
		_fail("Shared star material is missing its shader.")
		return
	var aspect := float(shared_material.get_shader_parameter("viewport_aspect"))
	if aspect <= 0.01:
		_fail("Viewport aspect was not propagated to the shared material.")
		return

	scene.call("set_preview_time", 0.0)
	var start_positions: Array = scene.call("debug_enemy_positions")
	scene.call("set_preview_time", 2.4)
	var moved_positions: Array = scene.call("debug_enemy_positions")
	var minimum_motion := maxf(float(root.size.x) * 0.01, 0.5)
	for enemy_index in range(3):
		var distance := (moved_positions[enemy_index] as Vector2).distance_to(
			start_positions[enemy_index] as Vector2
		)
		if distance < minimum_motion:
			_fail("Enemy %d did not move far enough to demonstrate screen-space sampling." % enemy_index)
			return

	var paused_positions: Array = scene.call("debug_enemy_positions")
	for _frame_index in range(8):
		await process_frame
	var after_pause_positions: Array = scene.call("debug_enemy_positions")
	for enemy_index in range(3):
		var paused_distance := (after_pause_positions[enemy_index] as Vector2).distance_to(
			paused_positions[enemy_index] as Vector2
		)
		if paused_distance > 0.01:
			_fail("Paused enemy %d continued moving." % enemy_index)
			return

	print("ANCHORED STAR ENEMIES SMOKE PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
