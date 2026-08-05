class_name TestLabUndergroundSpawnBeaconScene
extends Node2D

## 1280x760 comparison board for one high-fidelity underground enemy spawn warning.

const CONFIG_PATH: String = "res://data/underground_spawn_beacon.json"
const INDEX_SCENE_PATH: String = "res://scenes/test_lab_index.tscn"
const BEACON_SCRIPT: Script = preload("res://scripts/underground_spawn_beacon.gd")
const LUMA_SHADER: Shader = preload("res://shaders/underground_spawn_luma.gdshader")
const VIEWPORT_SIZE: Vector2 = Vector2(1280.0, 760.0)
const BACKGROUND_NAMES: PackedStringArray = ["DARK", "LOW CONTRAST MIND LAYER", "CROWDED COMBAT"]
const PHASE_NAMES: PackedStringArray = ["AUTO", "CHARGE", "ERUPTION", "BREAKOUT"]

var _config: Dictionary = {}
var _assets: Dictionary = {}
var _palette: Dictionary = {}
var _instances: Array[Node2D] = []
var _background: ColorRect = null
var _mind_clutter: Array[Sprite2D] = []
var _combat_clutter: Array[Sprite2D] = []
var _status_label: Label = null
var _preview_time: float = 0.0
var _paused: bool = false
var _checkpoint_mode: int = 0
var _background_mode: int = 2


func _ready() -> void:
	_config = _load_json(CONFIG_PATH)
	if _config.is_empty():
		return
	_assets = _load_assets(_config.get("assets", {}) as Dictionary)
	if _assets.is_empty():
		return
	_palette = _build_palette(_config.get("palette", {}) as Dictionary)
	_build_background()
	_build_header()
	_build_preview_frames()
	_build_controls()
	_apply_background()
	_apply_preview_time()


func _process(delta: float) -> void:
	if _config.is_empty() or _paused or _checkpoint_mode != 0:
		return
	var timing: Dictionary = _config.get("timing", {}) as Dictionary
	_preview_time = fposmod(_preview_time + delta, float(timing.get("cycle_end", 1.75)))
	_apply_preview_time(false)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_ESCAPE:
			get_tree().change_scene_to_file(INDEX_SCENE_PATH)
		KEY_SPACE:
			_toggle_pause()
		KEY_A:
			_set_auto()
		KEY_C:
			_cycle_checkpoint()
		KEY_B:
			_cycle_background()
		KEY_R:
			_reset_preview()
		_:
			pass


func debug_set_preview_time(value: float) -> void:
	_checkpoint_mode = 0
	_paused = true
	_preview_time = maxf(value, 0.0)
	_apply_preview_time()


func debug_set_checkpoint(checkpoint_index: int) -> void:
	_checkpoint_mode = clampi(checkpoint_index + 1, 1, 3)
	_paused = true
	_apply_checkpoint()


func debug_instance_states() -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	for instance: Node2D in _instances:
		states.append(instance.debug_state())
	return states


func debug_duration_probe(duration: float, preview_time: float) -> Dictionary:
	var probe: Node2D = BEACON_SCRIPT.new()
	probe.configure(
		_assets,
		_palette,
		_config.get("timing", {}) as Dictionary,
		_config.get("geometry", {}) as Dictionary,
		1.0,
		91_337,
		duration
	)
	probe.set_preview_time(preview_time, true)
	var state: Dictionary = probe.debug_state()
	probe.free()
	return state


func debug_config() -> Dictionary:
	return _config.duplicate(true)


func debug_asset_sizes() -> Dictionary:
	return {
		"ground_atlas": (_assets.get("ground_atlas") as Texture2D).get_size(),
		"upward_beam": (_assets.get("upward_beam") as Texture2D).get_size(),
		"particle_atlas": (_assets.get("particle_atlas") as Texture2D).get_size(),
		"ground_cells": (_assets.get("ground_cells") as Array).size(),
		"particle_cells": (_assets.get("particle_cells") as Array).size(),
	}


func debug_recursive_node_count() -> int:
	return _recursive_node_count(self)


func debug_preview_time() -> float:
	return _preview_time


func debug_is_paused() -> bool:
	return _paused


func debug_checkpoint_mode() -> int:
	return _checkpoint_mode


func debug_background_mode() -> int:
	return _background_mode


func debug_background_visibility() -> Dictionary:
	var visible_mind: int = 0
	var visible_combat: int = 0
	for sprite: Sprite2D in _mind_clutter:
		if sprite.visible:
			visible_mind += 1
	for sprite: Sprite2D in _combat_clutter:
		if sprite.visible:
			visible_combat += 1
	return {"mind": visible_mind, "combat": visible_combat}


func debug_cycle_background() -> void:
	_cycle_background()


func debug_reset_preview() -> void:
	_reset_preview()


func _build_background() -> void:
	_background = ColorRect.new()
	_background.name = "Background"
	_background.position = Vector2.ZERO
	_background.size = VIEWPORT_SIZE
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	var ground_cells: Array = _assets.get("ground_cells") as Array
	var particle_cells: Array = _assets.get("particle_cells") as Array
	var mind_positions: Array[Vector2] = [Vector2(130.0, 200.0), Vector2(1080.0, 180.0), Vector2(740.0, 650.0)]
	for index: int in range(mind_positions.size()):
		var sprite := _create_background_sprite(ground_cells[4 + index] as Texture2D, mind_positions[index], 360.0 + float(index) * 70.0, 0.16)
		_mind_clutter.append(sprite)

	var combat_positions: Array[Vector2] = [
		Vector2(78.0, 162.0), Vector2(198.0, 680.0), Vector2(405.0, 148.0), Vector2(525.0, 655.0),
		Vector2(650.0, 178.0), Vector2(804.0, 665.0), Vector2(955.0, 160.0), Vector2(1192.0, 204.0),
		Vector2(1100.0, 660.0), Vector2(52.0, 540.0), Vector2(870.0, 420.0), Vector2(1218.0, 520.0),
	]
	for index: int in range(combat_positions.size()):
		var size: float = 42.0 + float(index % 4) * 11.0
		var sprite := _create_background_sprite(particle_cells[(index * 3 + 2) % particle_cells.size()] as Texture2D, combat_positions[index], size, 0.42)
		sprite.rotation = float(index % 3 - 1) * 0.32
		_combat_clutter.append(sprite)


func _build_header() -> void:
	_create_label(self, "UNDERGROUND SPAWN BEACON · ENEMY ARRIVAL WARNING", Vector2(28.0, 16.0), Vector2(880.0, 32.0), 24, Color("fff5f8"))
	_create_label(self, "Fixed ground anchor · bottom-up beam reveal · upward-only debris · 1.50 s arrival", Vector2(30.0, 50.0), Vector2(920.0, 22.0), 14, Color("a88895"))
	_status_label = _create_label(self, "", Vector2(30.0, 77.0), Vector2(1190.0, 22.0), 13, Color("ed2f72"))


func _build_preview_frames() -> void:
	var detail_frame := _create_frame("DetailFrame", Vector2(22.0, 108.0), Vector2(526.0, 584.0), "3× DETAIL · DIRECTION + TEXTURE")
	_add_beacon(detail_frame, Vector2(263.0, 493.0), 3.0, 7_031, "DetailBeacon")

	var gameplay_frame := _create_frame("GameplayFrame", Vector2(568.0, 108.0), Vector2(330.0, 584.0), "1× GAMEPLAY SCALE")
	_add_beacon(gameplay_frame, Vector2(165.0, 404.0), 1.0, 7_107, "GameplayBeacon")
	_create_label(gameplay_frame, "48 px encounter footprint", Vector2(56.0, 466.0), Vector2(220.0, 22.0), 12, Color("9b7c88"), HORIZONTAL_ALIGNMENT_CENTER)

	var crowded_frame := _create_frame("CrowdedFrame", Vector2(918.0, 108.0), Vector2(340.0, 584.0), "3 NEIGHBORING SPAWNS")
	var origins: Array[Vector2] = [Vector2(108.0, 390.0), Vector2(170.0, 420.0), Vector2(232.0, 390.0)]
	for index: int in range(origins.size()):
		_add_beacon(crowded_frame, origins[index], 1.0, 7_201 + index * 31, "CrowdedBeacon%d" % index)
	_create_label(crowded_frame, "Overlapping combat-readability sample", Vector2(38.0, 466.0), Vector2(270.0, 22.0), 12, Color("9b7c88"), HORIZONTAL_ALIGNMENT_CENTER)


func _build_controls() -> void:
	var controls: Array[Dictionary] = [
		{"text": "AUTO [A]", "callback": _set_auto},
		{"text": "PHASE [C]", "callback": _cycle_checkpoint},
		{"text": "PAUSE [SPACE]", "callback": _toggle_pause},
		{"text": "BACKGROUND [B]", "callback": _cycle_background},
		{"text": "RESET [R]", "callback": _reset_preview},
		{"text": "INDEX [ESC]", "callback": _return_to_index},
	]
	var width: float = 188.0
	for index: int in range(controls.size()):
		var definition: Dictionary = controls[index]
		var button := Button.new()
		button.name = "ControlButton%d" % index
		button.text = String(definition["text"])
		button.position = Vector2(26.0 + float(index) * (width + 17.0), 710.0)
		button.size = Vector2(width, 34.0)
		button.focus_mode = Control.FOCUS_NONE
		var callback: Callable = definition["callback"]
		button.pressed.connect(callback)
		add_child(button)


func _add_beacon(parent: Node, origin: Vector2, display_scale: float, seed: int, node_name: String) -> void:
	var beacon: Node2D = BEACON_SCRIPT.new()
	beacon.name = node_name
	beacon.position = origin
	beacon.configure(
		_assets,
		_palette,
		_config.get("timing", {}) as Dictionary,
		_config.get("geometry", {}) as Dictionary,
		display_scale,
		seed,
		float((_config.get("timing", {}) as Dictionary).get("breakout_end", 1.5))
	)
	parent.add_child(beacon)
	_instances.append(beacon)


func _create_frame(node_name: String, position_value: Vector2, size_value: Vector2, title: String) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.position = position_value
	panel.size = size_value
	panel.clip_contents = true
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.018, 0.028, 0.56)
	style.border_color = Color(0.48, 0.08, 0.19, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	_create_label(panel, title, Vector2(14.0, 12.0), Vector2(size_value.x - 28.0, 24.0), 13, Color("eeb7c8"), HORIZONTAL_ALIGNMENT_CENTER)
	return panel


func _create_background_sprite(texture: Texture2D, position_value: Vector2, size_value: float, opacity: float) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = position_value
	var material := ShaderMaterial.new()
	material.shader = LUMA_SHADER
	material.set_shader_parameter("deep_color", _deep_color_from_palette().darkened(0.26))
	material.set_shader_parameter("primary_color", _deep_color_from_palette())
	material.set_shader_parameter("hot_color", _danger_color_from_palette())
	material.set_shader_parameter("opacity", opacity)
	sprite.material = material
	var texture_size: Vector2 = texture.get_size()
	sprite.scale = Vector2.ONE * size_value / maxf(texture_size.x, 1.0)
	add_child(sprite)
	return sprite


func _load_assets(asset_config: Dictionary) -> Dictionary:
	var ground_atlas: Texture2D = _load_runtime_texture(String(asset_config.get("ground_atlas", "")))
	var upward_beam: Texture2D = _load_runtime_texture(String(asset_config.get("upward_beam", "")))
	var particle_atlas: Texture2D = _load_runtime_texture(String(asset_config.get("particle_atlas", "")))
	if ground_atlas == null or upward_beam == null or particle_atlas == null:
		return {}
	var columns: int = int(asset_config.get("atlas_columns", 4))
	var rows: int = int(asset_config.get("atlas_rows", 4))
	var ground_cells: Array[Texture2D] = _slice_texture(ground_atlas, columns, rows)
	var particle_cells: Array[Texture2D] = _slice_texture(particle_atlas, columns, rows)
	if ground_cells.size() != 16 or particle_cells.size() != 16:
		push_error("Underground spawn beacon atlases must produce 16 cells each.")
		return {}
	return {
		"ground_atlas": ground_atlas,
		"upward_beam": upward_beam,
		"particle_atlas": particle_atlas,
		"ground_cells": ground_cells,
		"particle_cells": particle_cells,
	}


func _load_runtime_texture(texture_path: String) -> Texture2D:
	if texture_path.is_empty():
		return null
	var resolved_path: String = ProjectSettings.globalize_path(texture_path) if texture_path.begins_with("res://") else texture_path
	var image := Image.new()
	var error: Error = image.load(resolved_path)
	if error != OK:
		push_error("Failed to load underground spawn beacon source: %s (%s)" % [texture_path, error])
		return null
	return ImageTexture.create_from_image(image)


func _slice_texture(texture: Texture2D, columns: int, rows: int) -> Array[Texture2D]:
	var cells: Array[Texture2D] = []
	var source: Image = texture.get_image()
	var width: int = source.get_width()
	var height: int = source.get_height()
	for row: int in range(rows):
		var y0: int = roundi(float(row * height) / float(rows))
		var y1: int = roundi(float((row + 1) * height) / float(rows))
		for column: int in range(columns):
			var x0: int = roundi(float(column * width) / float(columns))
			var x1: int = roundi(float((column + 1) * width) / float(columns))
			var region: Image = source.get_region(Rect2i(x0, y0, x1 - x0, y1 - y0))
			cells.append(ImageTexture.create_from_image(region))
	return cells


func _build_palette(palette_config: Dictionary) -> Dictionary:
	return {
		"deep": Color.html(String(palette_config.get("deep", "#5A0B20"))),
		"danger": Color.html(String(palette_config.get("danger", "#ED2F72"))),
		"hot": Color.html(String(palette_config.get("hot", "#FFFFFF"))),
	}


func _apply_preview_time(force_seek: bool = true) -> void:
	for instance: Node2D in _instances:
		instance.set_preview_time(_preview_time, force_seek)
	_update_status()


func _apply_checkpoint() -> void:
	var checkpoints: Dictionary = (_config.get("timing", {}) as Dictionary).get("checkpoints", {}) as Dictionary
	var keys: PackedStringArray = ["charge", "eruption", "breakout"]
	_preview_time = float(checkpoints.get(keys[_checkpoint_mode - 1], 0.3))
	_apply_preview_time()


func _set_auto() -> void:
	_checkpoint_mode = 0
	_paused = false
	_update_status()


func _cycle_checkpoint() -> void:
	_checkpoint_mode = (_checkpoint_mode + 1) % 4
	if _checkpoint_mode == 0:
		_paused = false
	else:
		_paused = true
		_apply_checkpoint()
	_update_status()


func _toggle_pause() -> void:
	_paused = not _paused
	_update_status()


func _reset_preview() -> void:
	_preview_time = 0.0
	_checkpoint_mode = 0
	_paused = false
	for instance: Node2D in _instances:
		instance.reset_preview()
	_apply_preview_time()


func _cycle_background() -> void:
	_background_mode = (_background_mode + 1) % BACKGROUND_NAMES.size()
	_apply_background()
	_update_status()


func _apply_background() -> void:
	match _background_mode:
		0:
			_background.color = Color("09060b")
		1:
			_background.color = Color("111018")
		_:
			_background.color = Color("170d14")
	for sprite: Sprite2D in _mind_clutter:
		sprite.visible = _background_mode == 1
	for sprite: Sprite2D in _combat_clutter:
		sprite.visible = _background_mode == 2


func _update_status() -> void:
	if _status_label == null or _instances.is_empty():
		return
	var state: Dictionary = _instances[0].debug_state()
	_status_label.text = "PHASE %s · T %.2f / 1.50 · BEAM %.0f px UP · BG %s · %s" % [
		state.get("phase", "REST"),
		_preview_time,
		float(state.get("beam_visible_height", 0.0)),
		BACKGROUND_NAMES[_background_mode],
		"PAUSED" if _paused else "PLAYING",
	]


func _return_to_index() -> void:
	get_tree().change_scene_to_file(INDEX_SCENE_PATH)


func _deep_color_from_palette() -> Color:
	return _palette.get("deep", Color("5a0b20")) as Color


func _danger_color_from_palette() -> Color:
	return _palette.get("danger", Color("ed2f72")) as Color


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open underground spawn beacon config: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Underground spawn beacon config must contain a JSON object.")
		return {}
	return parsed as Dictionary


func _create_label(
	parent: Node,
	text_value: String,
	position_value: Vector2,
	size_value: Vector2,
	font_size: int,
	color: Color,
	alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = position_value
	label.size = size_value
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _recursive_node_count(node: Node) -> int:
	var count: int = 1
	for child: Node in node.get_children():
		count += _recursive_node_count(child)
	return count
