extends SceneTree

const SCENE_PATH := "res://scenes/shader_lab.tscn"
const STARFIELD_SHADER_PATH := "res://shaders/rotating_starfield.gdshader"
const WATER_FIRE_SHADER_PATH := "res://shaders/water_fire_flow.gdshader"
const REQUIRED_UNIFORMS: Array[String] = [
	"animation_time",
	"motion_speed",
	"effect_intensity",
	"pattern_scale",
	"gameplay_mix",
	"viewport_aspect",
]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	_validate_shader_resources()

	var packed_scene := load(SCENE_PATH) as PackedScene
	_check(packed_scene != null, "Shader Lab scene loads.")
	if packed_scene == null:
		_finish()
		return

	var scene := packed_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	for _index in range(3):
		await process_frame

	var state: Dictionary = scene.call("debug_state")
	_check(String(state.get("shader_id", "")) == "rotating_starfield", "Starfield is the initial Shader.")
	_check(String(state.get("preset_id", "")) == "showcase", "Showcase is the initial preset.")
	_check(int(state.get("selector_count", 0)) == 2, "Selector exposes both Shader entries.")
	_check(String(state.get("shader_path", "")) == STARFIELD_SHADER_PATH, "Initial material uses the starfield resource.")
	_check(is_equal_approx(float(state.get("speed", -1.0)), 1.0), "Starfield showcase speed defaults to 1.0.")
	_check(is_equal_approx(float(state.get("intensity", -1.0)), 1.0), "Starfield showcase intensity defaults to 1.0.")
	_check(is_equal_approx(float(state.get("scale", -1.0)), 1.0), "Starfield showcase scale defaults to 1.0.")
	_check(bool(state.get("panel_exists", false)), "Control panel exists.")
	_check(bool(state.get("fps_label_exists", false)), "FPS readout exists.")
	_check(String(state.get("pause_button_text", "")) == "暂停", "Pause button has its initial label.")

	scene.call("debug_set_controls", 1.42, 0.73, 1.31)
	scene.call("debug_select_shader", "water_fire_flow")
	state = scene.call("debug_state")
	_check(String(state.get("shader_path", "")) == WATER_FIRE_SHADER_PATH, "Selector switches to the water-fire resource.")
	_check(is_equal_approx(float(state.get("speed", -1.0)), 0.85), "Water-fire showcase speed defaults to 0.85.")

	_check(bool(scene.call("debug_set_preset", "gameplay")), "Gameplay preset is accepted.")
	state = scene.call("debug_state")
	_check(is_equal_approx(float(state.get("speed", -1.0)), 0.55), "Water-fire gameplay speed defaults to 0.55.")
	_check(is_equal_approx(float(state.get("intensity", -1.0)), 0.5), "Water-fire gameplay intensity defaults to 0.5.")
	_check(is_equal_approx(float(state.get("scale", -1.0)), 1.15), "Water-fire gameplay scale defaults to 1.15.")
	_check(is_equal_approx(float(state.get("gameplay_mix", -1.0)), 1.0), "Gameplay preset writes gameplay_mix=1.")

	scene.call("debug_set_controls", 1.21, 0.61, 1.44)
	state = scene.call("debug_state")
	_check(is_equal_approx(float(state.get("speed", -1.0)), 1.21), "Speed control updates the material state.")
	_check(is_equal_approx(float(state.get("intensity", -1.0)), 0.61), "Intensity control updates the material state.")
	_check(is_equal_approx(float(state.get("scale", -1.0)), 1.44), "Scale control updates the material state.")

	scene.call("debug_set_preset", "showcase")
	scene.call("debug_select_shader", "rotating_starfield")
	state = scene.call("debug_state")
	_check(is_equal_approx(float(state.get("speed", -1.0)), 1.42), "Per-Shader showcase controls persist for the session.")
	_check(is_equal_approx(float(state.get("intensity", -1.0)), 0.73), "Persisted intensity survives Shader switching.")
	_check(is_equal_approx(float(state.get("scale", -1.0)), 1.31), "Persisted scale survives Shader switching.")

	scene.call("debug_set_animation_time", 3.0)
	scene.call("debug_set_paused", true)
	for _index in range(3):
		await process_frame
	state = scene.call("debug_state")
	_check(is_equal_approx(float(state.get("animation_time", -1.0)), 3.0), "Pause freezes animation_time.")
	_check(String(state.get("pause_button_text", "")) == "继续", "Paused state updates the button label.")
	scene.call("debug_set_paused", false)
	for _index in range(3):
		await process_frame
	state = scene.call("debug_state")
	_check(float(state.get("animation_time", 0.0)) > 3.0, "Resume advances animation_time.")

	scene.call("debug_set_ui_visible", false)
	state = scene.call("debug_state")
	_check(not bool(state.get("ui_visible", true)), "Control panel can be hidden.")
	scene.call("debug_set_ui_visible", true)
	state = scene.call("debug_state")
	_check(bool(state.get("ui_visible", false)), "Control panel can be restored.")

	scene.call("debug_reset_current")
	state = scene.call("debug_state")
	_check(is_equal_approx(float(state.get("animation_time", -1.0)), 0.0), "Reset returns animation_time to zero.")
	_check(is_equal_approx(float(state.get("speed", -1.0)), 1.0), "Reset restores the active preset speed.")
	_check(is_equal_approx(float(state.get("intensity", -1.0)), 1.0), "Reset restores the active preset intensity.")
	_check(is_equal_approx(float(state.get("scale", -1.0)), 1.0), "Reset restores the active preset scale.")

	var viewport_size := root.size
	var expected_aspect := float(viewport_size.x) / maxf(float(viewport_size.y), 1.0)
	_check(
		is_equal_approx(float(state.get("viewport_aspect", -1.0)), expected_aspect),
		"Shader receives the current viewport aspect."
	)
	for action_name in [
		"lab_back",
		"shader_lab_next",
		"shader_lab_toggle_preset",
		"shader_lab_toggle_pause",
		"shader_lab_reset",
		"shader_lab_toggle_ui",
		"shader_lab_select_1",
		"shader_lab_select_2",
	]:
		_check(InputMap.has_action(action_name), "%s is registered in InputMap." % action_name)

	_finish()


func _validate_shader_resources() -> void:
	for shader_path in [STARFIELD_SHADER_PATH, WATER_FIRE_SHADER_PATH]:
		var shader := load(shader_path) as Shader
		_check(shader != null, "%s loads as a Shader." % shader_path)
		if shader == null:
			continue
		_check(shader.code.find("shader_type canvas_item") >= 0, "%s is a CanvasItem Shader." % shader_path)
		for uniform_name in REQUIRED_UNIFORMS:
			_check(shader.code.find("uniform float %s" % uniform_name) >= 0, "%s exposes %s." % [shader_path, uniform_name])
		_check(shader.code.find("TIME") < 0, "%s uses controller time instead of built-in TIME." % shader_path)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: %s" % message)
		return
	_failures.append(message)
	push_error("FAIL: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("Shader Lab smoke: ALL PASS")
		quit(0)
		return
	push_error("Shader Lab smoke failed with %d failure(s)." % _failures.size())
	quit(1)
