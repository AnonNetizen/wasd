extends SceneTree

const SCENE_PATH: String = "res://scenes/underground_spawn_beacon_test.tscn"
const INDEX_SCENE_PATH: String = "res://scenes/test_lab_index.tscn"
const CONFIG_PATH: String = "res://data/underground_spawn_beacon.json"
const STYLE_PACK_PATH: String = "res://assets/underground_spawn_beacon/style_pack.json"
const SOURCE_PATHS: PackedStringArray = [
	"res://scripts/underground_spawn_beacon.gd",
	"res://scripts/underground_spawn_beacon_test.gd",
	"res://shaders/underground_spawn_luma.gdshader",
	"res://shaders/underground_spawn_dark.gdshader",
	"res://shaders/underground_spawn_beam.gdshader",
]
const FORBIDDEN_RENDERING_TOKENS: PackedStringArray = [
	"RingGeometry",
	"_draw(",
	"Polygon2D",
	"Line2D",
	"PackedByteArray",
	"sub_resource type=\"Image\"",
	".godot/imported",
]
const PHASE_SAMPLES: Array[Dictionary] = [
	{"time": 0.30, "phase": "CHARGE"},
	{"time": 0.90, "phase": "ERUPTION"},
	{"time": 1.38, "phase": "BREAKOUT"},
	{"time": 1.62, "phase": "REST"},
]

var _failed: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var config: Dictionary = _load_json(CONFIG_PATH)
	var style_pack: Dictionary = _load_json(STYLE_PACK_PATH)
	_validate_config(config)
	_validate_assets(config, style_pack)
	_validate_sources()
	_validate_index()

	var index_packed := load(INDEX_SCENE_PATH) as PackedScene
	_expect(index_packed != null, "Test Lab index scene failed explicit load.")
	if index_packed != null:
		var index_scene := index_packed.instantiate()
		_expect(index_scene != null, "Test Lab index scene failed instantiation.")
		index_scene.free()

	var packed_scene := load(SCENE_PATH) as PackedScene
	_expect(packed_scene != null, "Underground spawn beacon scene failed explicit load.")
	if packed_scene == null:
		quit(1)
		return
	var scene := packed_scene.instantiate() as Node2D
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame

	var asset_sizes: Dictionary = scene.call("debug_asset_sizes") as Dictionary
	_expect(asset_sizes.get("ground_atlas") == Vector2(1254.0, 1254.0), "Ground atlas runtime size changed.")
	_expect(asset_sizes.get("upward_beam") == Vector2(1254.0, 1254.0), "Upward beam runtime size changed.")
	_expect(asset_sizes.get("particle_atlas") == Vector2(1254.0, 1254.0), "Particle atlas runtime size changed.")
	_expect(int(asset_sizes.get("ground_cells", 0)) == 16, "Ground atlas must slice to 16 cells.")
	_expect(int(asset_sizes.get("particle_cells", 0)) == 16, "Particle atlas must slice to 16 cells.")

	var initial_node_count: int = int(scene.call("debug_recursive_node_count"))
	_validate_states(scene.call("debug_instance_states") as Array, "initial")
	for sample: Dictionary in PHASE_SAMPLES:
		scene.call("debug_set_preview_time", float(sample["time"]))
		var states: Array = scene.call("debug_instance_states") as Array
		_validate_states(states, String(sample["phase"]))
		for index: int in range(states.size()):
			var state: Dictionary = states[index] as Dictionary
			_expect(String(state.get("phase", "")) == String(sample["phase"]), "Instance %d phase mismatch at %.2f." % [index, sample["time"]])
			_expect(is_equal_approx(float(state.get("beam_anchor_y", 99.0)), 0.0), "Beam anchor moved off the ground for instance %d." % index)
			_expect(String(state.get("beam_direction", "")) == "UPWARD_FROM_FIXED_BASE", "Beam direction contract changed for instance %d." % index)
			_expect(bool(state.get("particles_at_or_above_ground", false)), "Particle moved below ground for instance %d." % index)
			_expect(float(state.get("particle_vertical_velocity_max", 0.0)) < 0.0, "Particle vertical velocity must remain upward.")
		if String(sample["phase"]) == "REST":
			for state_variant: Variant in states:
				var state: Dictionary = state_variant as Dictionary
				_expect(int(state.get("active_particles", -1)) == 0, "REST must stop every particle.")
				_expect(is_zero_approx(float(state.get("beam_reveal", -1.0))), "REST must hide the beam reveal.")
				_expect(not bool(state.get("beam_node_visible", true)), "REST must hide the beam node.")

	var beam_sprite_y: float = 0.0
	var last_visible_height: float = -1.0
	for index: int in range(5):
		var sample_time: float = lerpf(0.46, 1.20, float(index) / 4.0)
		scene.call("debug_set_preview_time", sample_time)
		var state: Dictionary = (scene.call("debug_instance_states") as Array)[0] as Dictionary
		var visible_height: float = float(state.get("beam_visible_height", -1.0))
		if index == 0:
			beam_sprite_y = float(state.get("beam_sprite_y", 0.0))
		else:
			_expect(is_equal_approx(float(state.get("beam_sprite_y", 999.0)), beam_sprite_y), "Beam sprite moved instead of revealing from its fixed base.")
		_expect(visible_height > last_visible_height, "Beam visible height must grow monotonically during ERUPTION.")
		last_visible_height = visible_height

	scene.call("debug_set_preview_time", 0.90)
	var locked_time: float = float(scene.call("debug_preview_time"))
	_expect(bool(scene.call("debug_is_paused")), "Absolute preview time must pause the shared controller.")
	for frame_index: int in range(5):
		await process_frame
	_expect(is_equal_approx(float(scene.call("debug_preview_time")), locked_time), "Paused absolute preview time advanced.")

	var initial_background: int = int(scene.call("debug_background_mode"))
	for index: int in range(3):
		scene.call("debug_cycle_background")
		var mode: int = int(scene.call("debug_background_mode"))
		var visibility: Dictionary = scene.call("debug_background_visibility") as Dictionary
		_expect(int(visibility.get("mind", -1)) == (3 if mode == 1 else 0), "Mind-layer background visibility mismatch in mode %d." % mode)
		_expect(int(visibility.get("combat", -1)) == (12 if mode == 2 else 0), "Combat-clutter background visibility mismatch in mode %d." % mode)
	_expect(int(scene.call("debug_background_mode")) == initial_background, "Three background modes must cycle without drift.")

	for checkpoint_index: int in range(3):
		scene.call("debug_set_checkpoint", checkpoint_index)
		var states: Array = scene.call("debug_instance_states") as Array
		_expect(String((states[0] as Dictionary).get("phase", "")) == ["CHARGE", "ERUPTION", "BREAKOUT"][checkpoint_index], "Checkpoint phase %d failed." % checkpoint_index)

	_validate_duration_probe(scene, 0.75, 0.15, "CHARGE")
	_validate_duration_probe(scene, 0.75, 0.45, "ERUPTION")
	_validate_duration_probe(scene, 0.75, 0.70, "BREAKOUT")
	_validate_duration_probe(scene, 0.75, 0.82, "REST")

	for round_index: int in range(16):
		for sample: Dictionary in PHASE_SAMPLES:
			scene.call("debug_set_preview_time", float(sample["time"]))
		scene.call("debug_reset_preview")
		_expect(int(scene.call("debug_recursive_node_count")) == initial_node_count, "Playback/reset round %d accumulated nodes." % round_index)
	_validate_states(scene.call("debug_instance_states") as Array, "reset")

	if _failed:
		quit(1)
		return
	print("[UndergroundSpawnBeaconSmoke] ALL PASS: external Image.load assets and manifest, 1.50 s phase contract, absolute seek/pause/reset, duration scaling, fixed-base bottom-up beam growth, upward-only particles, five stable previews, three backgrounds, clean REST, index registration, and non-geometric source gates.")
	quit(0)


func _validate_config(config: Dictionary) -> void:
	var timing: Dictionary = config.get("timing", {}) as Dictionary
	_expect(is_equal_approx(float(timing.get("charge_end", 0.0)), 0.45), "CHARGE end must remain 0.45 s.")
	_expect(is_equal_approx(float(timing.get("eruption_end", 0.0)), 1.25), "ERUPTION end must remain 1.25 s.")
	_expect(is_equal_approx(float(timing.get("breakout_end", 0.0)), 1.50), "BREAKOUT end must remain 1.50 s.")
	_expect(is_equal_approx(float(timing.get("cycle_end", 0.0)), 1.75), "Cycle end must remain 1.75 s.")
	var palette: Dictionary = config.get("palette", {}) as Dictionary
	_expect(String(palette.get("deep", "")).to_lower() == "#5a0b20", "Deep danger color changed.")
	_expect(String(palette.get("danger", "")).to_lower() == "#ed2f72", "Danger pink changed.")
	_expect(String(palette.get("hot", "")).to_lower() == "#ffffff", "White-hot color changed.")
	var geometry: Dictionary = config.get("geometry", {}) as Dictionary
	_expect(is_equal_approx(float(geometry.get("well_diameter", 0.0)), 20.0), "Dark well diameter changed.")
	_expect(is_equal_approx(float(geometry.get("inner_ring_radius", 0.0)), 28.0), "Inner ring radius changed.")
	_expect(is_equal_approx(float(geometry.get("outer_ring_radius", 0.0)), 42.0), "Outer ring radius changed.")
	var assets: Dictionary = config.get("assets", {}) as Dictionary
	_expect(int(assets.get("atlas_columns", 0)) == 4 and int(assets.get("atlas_rows", 0)) == 4, "Generated atlases must retain a 4x4 logical layout.")
	var samples: Dictionary = config.get("samples", {}) as Dictionary
	_expect(is_equal_approx(float(samples.get("detail_scale", 0.0)), 3.0), "Detail preview must remain 3x.")
	_expect(is_equal_approx(float(samples.get("gameplay_scale", 0.0)), 1.0), "Gameplay preview must remain 1x.")
	_expect(int(samples.get("crowded_count", 0)) == 3, "Crowded preview must retain three spawn points.")


func _validate_assets(config: Dictionary, style_pack: Dictionary) -> void:
	var configured: Dictionary = config.get("assets", {}) as Dictionary
	var entries: Array = style_pack.get("assets", []) as Array
	_expect(entries.size() == 3, "Style-pack manifest must record exactly three generated sources.")
	var paths: PackedStringArray = [
		String(configured.get("ground_atlas", "")),
		String(configured.get("upward_beam", "")),
		String(configured.get("particle_atlas", "")),
	]
	for index: int in range(mini(entries.size(), paths.size())):
		var entry: Dictionary = entries[index] as Dictionary
		var path: String = paths[index]
		_expect(path.get_file() == String(entry.get("file", "")), "Manifest/config asset order changed at index %d." % index)
		_expect(FileAccess.file_exists(path), "Generated source is missing: %s" % path)
		if not FileAccess.file_exists(path):
			continue
		var absolute_path: String = ProjectSettings.globalize_path(path)
		var image := Image.new()
		var error: Error = image.load(absolute_path)
		_expect(error == OK, "Generated source failed decode: %s" % path)
		_expect(image.get_width() == int(entry.get("width", 0)) and image.get_height() == int(entry.get("height", 0)), "Manifest dimensions changed for %s." % path.get_file())
		_expect(FileAccess.get_sha256(absolute_path).to_lower() == String(entry.get("sha256", "")).to_lower(), "Manifest SHA-256 changed for %s." % path.get_file())


func _validate_sources() -> void:
	for path: String in SOURCE_PATHS:
		var source: String = _read_text(path)
		_expect(not source.is_empty(), "Implementation source is missing: %s" % path)
		for token: String in FORBIDDEN_RENDERING_TOKENS:
			_expect(source.find(token) < 0, "Forbidden rendering/embed token %s found in %s." % [token, path])
	var beacon_source: String = _read_text("res://scripts/underground_spawn_beacon.gd")
	_expect(beacon_source.count("_beam.position =") == 1, "Beam position must be assigned exactly once at construction.")
	var scene_source: String = _read_text(SCENE_PATH)
	for token: String in ["PackedByteArray", "sub_resource type=\"Image\"", ".godot/imported"]:
		_expect(scene_source.find(token) < 0, "Scene embeds or depends on image-cache token: %s" % token)


func _validate_index() -> void:
	var index_source: String = _read_text("res://scripts/test_lab_index.gd")
	_expect(index_source.find("UndergroundSpawnBeaconButton") >= 0, "Test Lab index button is missing.")
	_expect(index_source.find(SCENE_PATH) >= 0, "Test Lab index does not point to the underground spawn beacon scene.")


func _validate_states(states: Array, context: String) -> void:
	_expect(states.size() == 5, "%s must expose one 3x, one 1x, and three crowded previews." % context)
	if states.size() != 5:
		return
	for index: int in range(states.size()):
		var state: Dictionary = states[index] as Dictionary
		var expected_scale: float = 3.0 if index == 0 else 1.0
		_expect(is_equal_approx(float(state.get("display_scale", 0.0)), expected_scale), "%s preview %d scale changed." % [context, index])
		_expect(is_equal_approx(float(state.get("duration", 0.0)), 1.5), "%s preview %d duration changed." % [context, index])
		_expect(int(state.get("particle_count", 0)) == 14, "%s preview %d particle-node count changed." % [context, index])
		_expect(int(state.get("node_count", 0)) > 14, "%s preview %d visual tree is incomplete." % [context, index])


func _validate_duration_probe(scene: Node, duration: float, preview_time: float, expected_phase: String) -> void:
	var state: Dictionary = scene.call("debug_duration_probe", duration, preview_time) as Dictionary
	_expect(is_equal_approx(float(state.get("duration", 0.0)), duration), "Duration probe did not preserve configured duration.")
	_expect(String(state.get("phase", "")) == expected_phase, "Duration-scaled phase mismatch at %.2f; expected %s." % [preview_time, expected_phase])


func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(_read_text(path))
	if not parsed is Dictionary:
		return {}
	return parsed as Dictionary


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("[UndergroundSpawnBeaconSmoke] %s" % message)
