extends SceneTree

const SCENE_PATH: String = "res://scenes/organic_vfx_pipeline_selection_test.tscn"
const CONFIG_PATH: String = "res://data/organic_vfx_pipeline_selection.json"
const STYLE_PACK_PATH: String = "res://assets/vfx_pipeline_selection/style_pack.json"
const EXPECTED_PIPELINES: PackedStringArray = [
	"flipbook", "flipbook",
	"particles", "particles",
	"shader", "shader",
	"hybrid", "hybrid",
]
const PHASE_SAMPLES: Array[Dictionary] = [
	{"time": 0.34, "phase": "CHARGE"},
	{"time": 0.56, "phase": "CONTACT"},
	{"time": 0.92, "phase": "AFTERMATH"},
	{"time": 1.32, "phase": "REST"},
]
const FORBIDDEN_RENDERING_TOKENS: PackedStringArray = [
	"_draw(",
	"Polygon2D",
	"Line2D",
	"VFXPrimitive.RING",
	"VFXPrimitive.WEDGE",
	"VFXPrimitive.RAY",
]

var _failed: bool = false


func _initialize() -> void:
	call_deferred("_run_smoke")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("[OrganicVfxPipelineSelectionSmoke] %s" % message)


func _run_smoke() -> void:
	var config: Dictionary = _load_json(CONFIG_PATH)
	var style_pack: Dictionary = _load_json(STYLE_PACK_PATH)
	_expect(not config.is_empty(), "Experiment config must load as JSON.")
	_expect(not style_pack.is_empty(), "Image-generation manifest must load as JSON.")
	_validate_config(config)
	_validate_assets(config, style_pack)
	_validate_sources()

	var packed_scene := load(SCENE_PATH) as PackedScene
	if packed_scene == null:
		push_error("[OrganicVfxPipelineSelectionSmoke] Failed to load scene: %s" % SCENE_PATH)
		quit(1)
		return
	var scene := packed_scene.instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var initial_node_count: int = int(scene.call("debug_recursive_node_count"))
	var sizes: Dictionary = scene.call("debug_asset_sizes") as Dictionary
	_expect(sizes.get("flipbook") == Vector2(1254.0, 1254.0), "Flipbook runtime texture size changed.")
	_expect(sizes.get("particles") == Vector2(1254.0, 1254.0), "Particle atlas runtime texture size changed.")
	_expect(sizes.get("flow_mask") == Vector2(1254.0, 1254.0), "Flow-mask runtime texture size changed.")
	_expect(int(sizes.get("particle_cells", 0)) == 16, "Particle atlas must slice into 16 runtime cells.")

	_validate_states(scene.call("debug_candidate_states") as Array, "initial")
	for sample: Dictionary in PHASE_SAMPLES:
		scene.call("debug_set_preview_time", float(sample["time"]))
		await process_frame
		var states: Array = scene.call("debug_candidate_states") as Array
		_validate_states(states, String(sample["phase"]))
		for state_variant: Variant in states:
			var state: Dictionary = state_variant as Dictionary
			_expect(String(state.get("phase", "")) == String(sample["phase"]), "All candidates must share the %s phase." % sample["phase"])
			_expect(is_equal_approx(float(state.get("preview_time", -1.0)), float(sample["time"])), "Absolute preview seek drifted at %s." % sample["phase"])
		if String(sample["phase"]) == "REST":
			for state_variant: Variant in states:
				var rest_state: Dictionary = state_variant as Dictionary
				_expect(int(rest_state.get("visible_particle_emitters", -1)) == 0, "Particle residue remained visible in REST.")
				_expect(int(rest_state.get("emitting_particle_emitters", -1)) == 0, "Particle emission continued in REST.")

	scene.call("debug_set_preview_time", 0.56)
	var locked_time: float = float(scene.call("debug_preview_time"))
	_expect(bool(scene.call("debug_is_paused")), "Fixed preview time must pause the shared controller.")
	for frame_index: int in range(5):
		await process_frame
	_expect(is_equal_approx(float(scene.call("debug_preview_time")), locked_time), "Paused preview time advanced.")

	var before_palette: Array = scene.call("debug_candidate_states") as Array
	scene.call("debug_toggle_palette")
	var after_palette: Array = scene.call("debug_candidate_states") as Array
	for index: int in range(after_palette.size()):
		_expect(String((before_palette[index] as Dictionary).get("palette_signature", "")) != String((after_palette[index] as Dictionary).get("palette_signature", "")), "Palette toggle did not reach candidate %d." % index)

	var initial_background: int = int(scene.call("debug_background_mode"))
	for index: int in range(3):
		scene.call("debug_cycle_background")
	_expect(int(scene.call("debug_background_mode")) == initial_background, "Three background modes must cycle without drift.")
	for index: int in range(4):
		scene.call("debug_focus_candidate", index)
		_expect(int(scene.call("debug_focused_candidate")) == index, "Candidate focus failed for card %d." % index)
	scene.call("debug_focus_candidate", -1)
	_expect(int(scene.call("debug_focused_candidate")) == -1, "Grid view did not restore after focus.")

	for round_index: int in range(12):
		for sample: Dictionary in PHASE_SAMPLES:
			scene.call("debug_set_preview_time", float(sample["time"]))
		scene.call("debug_reset_preview")
		_expect(int(scene.call("debug_recursive_node_count")) == initial_node_count, "Preview round %d accumulated nodes." % round_index)
	_validate_states(scene.call("debug_candidate_states") as Array, "reset")

	if _failed:
		quit(1)
		return
	print("[OrganicVfxPipelineSelectionSmoke] ALL PASS: external assets and manifest, four ordered pipelines, shared timing/palette/scale, absolute seeks, clean REST particles, stable reset nodes, focus, backgrounds, and non-geometric source gates.")
	quit(0)


func _validate_config(config: Dictionary) -> void:
	var timing: Dictionary = config.get("timing", {}) as Dictionary
	_expect(is_equal_approx(float(timing.get("charge_end", 0.0)), 0.48), "CHARGE end must remain 0.48 s.")
	_expect(is_equal_approx(float(timing.get("contact_end", 0.0)), 0.64), "CONTACT end must remain 0.64 s.")
	_expect(is_equal_approx(float(timing.get("aftermath_end", 0.0)), 1.20), "AFTERMATH end must remain 1.20 s.")
	_expect(is_equal_approx(float(timing.get("cycle_end", 0.0)), 1.44), "Cycle end must remain 1.44 s.")
	_expect(is_equal_approx(float(config.get("core_radius", 0.0)), 48.0), "Core radius must remain 48 px.")
	_expect(is_equal_approx(float(config.get("max_decorative_radius", 0.0)), 72.0), "Decorative extent must remain 72 px.")
	var palette: Dictionary = config.get("palette", {}) as Dictionary
	_expect(String(palette.get("calm", "")).to_lower() == "#68bcdd", "Calm color changed.")
	_expect(String(palette.get("angry", "")).to_lower() == "#ed2f72", "Angry color changed.")
	_expect(String(palette.get("hot", "")).to_lower() == "#ffffff", "Hot color changed.")
	var assets: Dictionary = config.get("assets", {}) as Dictionary
	_expect(int(assets.get("atlas_columns", 0)) == 4 and int(assets.get("atlas_rows", 0)) == 4, "Both source atlases must use a 4x4 logical layout.")
	var candidates: Array = config.get("candidates", []) as Array
	_expect(candidates.size() == 4, "Selection wall must contain exactly four candidates.")
	var ordered_ids: PackedStringArray = []
	for candidate_variant: Variant in candidates:
		var candidate: Dictionary = candidate_variant as Dictionary
		ordered_ids.append(String(candidate.get("id", "")))
		for field: String in ["production_cost", "memory_pressure", "recolor_capability", "reuse_capability"]:
			_expect(not String(candidate.get(field, "")).is_empty(), "Candidate %s must declare %s." % [candidate.get("id", "?"), field])
	_expect(ordered_ids == PackedStringArray(["flipbook", "particles", "shader", "hybrid"]), "Candidate A/B/C/D order changed.")


func _validate_assets(config: Dictionary, style_pack: Dictionary) -> void:
	var configured_assets: Dictionary = config.get("assets", {}) as Dictionary
	var manifest_assets: Array = style_pack.get("assets", []) as Array
	_expect(manifest_assets.size() == 3, "Manifest must record exactly three generated sources.")
	var configured_paths: PackedStringArray = [
		String(configured_assets.get("flipbook", "")),
		String(configured_assets.get("particles", "")),
		String(configured_assets.get("flow_mask", "")),
	]
	for index: int in range(manifest_assets.size()):
		var entry: Dictionary = manifest_assets[index] as Dictionary
		var path: String = configured_paths[index]
		_expect(path.get_file() == String(entry.get("file", "")), "Manifest file order no longer matches config at index %d." % index)
		var absolute_path: String = ProjectSettings.globalize_path(path)
		_expect(FileAccess.file_exists(path), "Generated source is missing: %s" % path)
		if not FileAccess.file_exists(path):
			continue
		var image := Image.new()
		var error: Error = image.load(absolute_path)
		_expect(error == OK, "Generated source failed to decode: %s" % path)
		_expect(image.get_width() == int(entry.get("width", 0)) and image.get_height() == int(entry.get("height", 0)), "Manifest dimensions changed for %s." % path.get_file())
		_expect(FileAccess.get_sha256(absolute_path).to_lower() == String(entry.get("sha256", "")).to_lower(), "Manifest SHA-256 changed for %s." % path.get_file())


func _validate_sources() -> void:
	var implementation_paths: PackedStringArray = [
		"res://scripts/organic_vfx_candidate.gd",
		"res://shaders/organic_vfx_luma_atlas.gdshader",
		"res://shaders/organic_vfx_flow.gdshader",
	]
	for path: String in implementation_paths:
		var source: String = _read_text(path)
		_expect(not source.is_empty(), "Implementation source is missing: %s" % path)
		for token: String in FORBIDDEN_RENDERING_TOKENS:
			_expect(source.find(token) < 0, "Forbidden geometric rendering token %s found in %s." % [token, path])
	var scene_text: String = _read_text(SCENE_PATH)
	for token: String in ["PackedByteArray", "sub_resource type=\"Image\"", ".godot/imported"]:
		_expect(scene_text.find(token) < 0, "Scene embeds or depends on image cache token: %s" % token)


func _validate_states(states: Array, context: String) -> void:
	_expect(states.size() == 8, "%s must expose two previews for each of four candidates." % context)
	if states.size() != 8:
		return
	for index: int in range(states.size()):
		var state: Dictionary = states[index] as Dictionary
		_expect(String(state.get("pipeline_id", "")) == EXPECTED_PIPELINES[index], "%s pipeline order changed at index %d." % [context, index])
		_expect(is_equal_approx(float(state.get("core_radius", 0.0)), 48.0), "%s candidate %d changed core radius." % [context, index])
		_expect(is_equal_approx(float(state.get("decorative_radius", 0.0)), 72.0), "%s candidate %d changed decorative extent." % [context, index])
		var expected_scale: float = 2.5 if index % 2 == 0 else 1.0
		_expect(is_equal_approx(float(state.get("display_scale", 0.0)), expected_scale), "%s candidate %d changed display scale." % [context, index])
		var pipeline: String = String(state.get("pipeline_id", ""))
		_expect(bool(state.get("has_flipbook", false)) == (pipeline == "flipbook" or pipeline == "hybrid"), "%s flipbook composition flag is wrong for %s." % [context, pipeline])
		_expect(bool(state.get("has_flow_mask", false)) == (pipeline == "shader" or pipeline == "hybrid"), "%s flow-mask composition flag is wrong for %s." % [context, pipeline])
		var emitter_count: int = int(state.get("particle_emitter_count", -1))
		_expect((emitter_count > 0) == (pipeline == "particles" or pipeline == "hybrid"), "%s particle composition flag is wrong for %s." % [context, pipeline])


func _load_json(path: String) -> Dictionary:
	var text: String = _read_text(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {}
	return parsed as Dictionary


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()
