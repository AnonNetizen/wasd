class_name TestLabOrganicVfxPipelineSelection
extends Node2D

## Four-way selection wall for non-geometric organic VFX production pipelines.

const CONFIG_PATH: String = "res://data/organic_vfx_pipeline_selection.json"
const INDEX_SCENE_PATH: String = "res://scenes/test_lab_index.tscn"
const CANDIDATE_SCRIPT: Script = preload("res://scripts/organic_vfx_candidate.gd")
const VIEWPORT_SIZE: Vector2 = Vector2(1280.0, 760.0)
const CARD_SIZE: Vector2 = Vector2(600.0, 274.0)
const CARD_POSITIONS: Array[Vector2] = [
	Vector2(24.0, 104.0),
	Vector2(656.0, 104.0),
	Vector2(24.0, 392.0),
	Vector2(656.0, 392.0),
]
const BACKGROUND_NAMES: PackedStringArray = ["DARK", "MIND LAYER", "COMBAT CLUTTER"]
const CHECKPOINT_NAMES: PackedStringArray = ["AUTO", "CHARGE", "CONTACT", "AFTERMATH"]

var _config: Dictionary = {}
var _assets: Dictionary = {}
var _cards: Array[Panel] = []
var _card_positions: Array[Vector2] = []
var _candidates: Array[Node2D] = []
var _diagnostic_panels: Array[Panel] = []
var _background: ColorRect = null
var _background_flow: TextureRect = null
var _background_clutter: Array[Sprite2D] = []
var _status_label: Label = null
var _preview_time: float = 0.0
var _paused: bool = false
var _checkpoint_mode: int = 0
var _background_mode: int = 1
var _angry_dominant: bool = false
var _diagnostics_visible: bool = false
var _focused_candidate: int = -1


func _ready() -> void:
	_config = _load_json(CONFIG_PATH)
	if _config.is_empty():
		return
	_assets = _load_assets(_config.get("assets", {}) as Dictionary)
	if _assets.is_empty():
		return
	_build_background()
	_build_header()
	_build_cards()
	_build_controls()
	_apply_background()
	_apply_preview_time()
	_update_status()


func _process(delta: float) -> void:
	if _config.is_empty() or _checkpoint_mode != 0 or _paused:
		return
	var timing: Dictionary = _config.get("timing", {}) as Dictionary
	var cycle_end: float = float(timing.get("cycle_end", 1.44))
	_preview_time = fposmod(_preview_time + delta, cycle_end)
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
			_set_auto_mode()
		KEY_C:
			_cycle_checkpoint()
		KEY_P:
			_toggle_palette()
		KEY_B:
			_cycle_background()
		KEY_D:
			_toggle_diagnostics()
		KEY_R:
			_reset_preview()
		KEY_0:
			_focus_candidate(-1)
		KEY_1, KEY_2, KEY_3, KEY_4:
			_focus_candidate(int(key_event.keycode - KEY_1))
		_:
			pass


func debug_set_preview_time(value: float) -> void:
	_checkpoint_mode = 0
	_paused = true
	_preview_time = maxf(value, 0.0)
	_apply_preview_time()
	_update_status()


func debug_set_checkpoint(checkpoint_index: int) -> void:
	_checkpoint_mode = clampi(checkpoint_index + 1, 1, 3)
	_paused = true
	_apply_checkpoint_time()
	_update_status()


func debug_candidate_states() -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	for candidate: Node2D in _candidates:
		states.append(candidate.debug_state())
	return states


func debug_config() -> Dictionary:
	return _config.duplicate(true)


func debug_asset_sizes() -> Dictionary:
	return {
		"flipbook": (_assets.get("flipbook") as Texture2D).get_size(),
		"particles": (_assets.get("particles") as Texture2D).get_size(),
		"flow_mask": (_assets.get("flow_mask") as Texture2D).get_size(),
		"particle_cells": (_assets.get("particle_cells") as Array).size(),
	}


func debug_recursive_node_count() -> int:
	return _recursive_node_count(self)


func debug_toggle_palette() -> void:
	_toggle_palette()


func debug_cycle_background() -> void:
	_cycle_background()


func debug_background_mode() -> int:
	return _background_mode


func debug_focus_candidate(index: int) -> void:
	_focus_candidate(index)


func debug_focused_candidate() -> int:
	return _focused_candidate


func debug_preview_time() -> float:
	return _preview_time


func debug_is_paused() -> bool:
	return _paused


func debug_checkpoint_mode() -> int:
	return _checkpoint_mode


func debug_reset_preview() -> void:
	_reset_preview()


func _build_background() -> void:
	_background = ColorRect.new()
	_background.name = "Background"
	_background.position = Vector2.ZERO
	_background.size = VIEWPORT_SIZE
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)

	_background_flow = TextureRect.new()
	_background_flow.name = "BackgroundFlowTexture"
	_background_flow.position = Vector2.ZERO
	_background_flow.size = VIEWPORT_SIZE
	_background_flow.texture = _assets.get("flow_mask") as Texture2D
	_background_flow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background_flow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background_flow)

	var cells: Array = _assets.get("particle_cells") as Array
	var positions: Array[Vector2] = [
		Vector2(84.0, 132.0), Vector2(1188.0, 164.0), Vector2(620.0, 92.0),
		Vector2(112.0, 650.0), Vector2(1194.0, 628.0), Vector2(640.0, 684.0),
		Vector2(348.0, 236.0), Vector2(918.0, 512.0),
	]
	for index: int in range(positions.size()):
		var sprite := Sprite2D.new()
		sprite.name = "CombatClutter%02d" % index
		sprite.texture = cells[(index * 2 + 1) % cells.size()] as Texture2D
		sprite.position = positions[index]
		sprite.scale = Vector2.ONE * (0.18 + float(index % 3) * 0.03)
		sprite.rotation = float(index) * 0.61
		sprite.modulate = Color(0.93, 0.18, 0.45, 0.08)
		sprite.visible = false
		_background_clutter.append(sprite)
		add_child(sprite)


func _build_header() -> void:
	_create_label(
		self,
		"ORGANIC MIND VFX · NON-GEOMETRIC PIPELINE SELECTION",
		Vector2(32.0, 15.0),
		Vector2(900.0, 34.0),
		24,
		Color("eaf7ff")
	)
	_create_label(
		self,
		"Same palette · same 48 px core · same CHARGE / CONTACT / AFTERMATH timing",
		Vector2(34.0, 49.0),
		Vector2(850.0, 24.0),
		14,
		Color("8296ad")
	)
	_status_label = _create_label(
		self,
		"",
		Vector2(34.0, 75.0),
		Vector2(1180.0, 24.0),
		13,
		Color("68bcdd")
	)


func _build_cards() -> void:
	var candidate_data: Array = _config.get("candidates", []) as Array
	var palette: Dictionary = {
		"calm": Color.html(String((_config.get("palette", {}) as Dictionary).get("calm", "#68bcdd"))),
		"angry": Color.html(String((_config.get("palette", {}) as Dictionary).get("angry", "#ed2f72"))),
		"hot": Color.html(String((_config.get("palette", {}) as Dictionary).get("hot", "#ffffff"))),
	}
	var core_radius: float = float(_config.get("core_radius", 48.0))
	var decorative_radius: float = float(_config.get("max_decorative_radius", 72.0))
	var timing: Dictionary = _config.get("timing", {}) as Dictionary
	for index: int in range(candidate_data.size()):
		var definition: Dictionary = candidate_data[index] as Dictionary
		var card := Panel.new()
		card.name = "CandidateCard%d" % index
		card.position = CARD_POSITIONS[index]
		card.size = CARD_SIZE
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.add_theme_stylebox_override("panel", _card_style(index, false))
		_cards.append(card)
		_card_positions.append(card.position)
		add_child(card)

		_create_label(card, String(definition.get("label", "?")), Vector2(16.0, 10.0), Vector2(560.0, 26.0), 17, Color("eaf7ff"))
		_create_label(card, String(definition.get("method", "")), Vector2(16.0, 37.0), Vector2(560.0, 20.0), 12, Color("93a5b9"))
		_create_label(
			card,
			"COST %s · MEMORY %s" % [definition.get("production_cost", "?"), definition.get("memory_pressure", "?")],
			Vector2(16.0, 60.0), Vector2(560.0, 18.0), 11, Color("ed2f72")
		)
		_create_label(
			card,
			"RECOLOR %s · REUSE %s" % [definition.get("recolor_capability", "?"), definition.get("reuse_capability", "?")],
			Vector2(16.0, 80.0), Vector2(560.0, 18.0), 11, Color("68bcdd")
		)

		var pipeline_id: String = String(definition.get("id", ""))
		var detail_frame := Control.new()
		detail_frame.name = "DetailViewport"
		detail_frame.position = Vector2(16.0, 99.0)
		detail_frame.size = Vector2(340.0, 145.0)
		detail_frame.clip_contents = true
		detail_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(detail_frame)
		var detail: Node2D = CANDIDATE_SCRIPT.new()
		detail.name = "DetailPreview"
		detail.position = Vector2(170.0, 73.0)
		detail.configure(pipeline_id, _assets, palette, timing, 2.5, 1_337 + index * 17, core_radius, decorative_radius)
		detail_frame.add_child(detail)
		_candidates.append(detail)

		var actual_frame := Control.new()
		actual_frame.name = "GameplayViewport"
		actual_frame.position = Vector2(364.0, 99.0)
		actual_frame.size = Vector2(220.0, 145.0)
		actual_frame.clip_contents = true
		actual_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(actual_frame)
		var actual: Node2D = CANDIDATE_SCRIPT.new()
		actual.name = "GameplayScalePreview"
		actual.position = Vector2(110.0, 73.0)
		actual.configure(pipeline_id, _assets, palette, timing, 1.0, 2_021 + index * 29, core_radius, decorative_radius)
		actual_frame.add_child(actual)
		_candidates.append(actual)

		_create_label(card, "2.5× DETAIL", Vector2(142.0, 247.0), Vector2(110.0, 18.0), 10, Color("7d8da1"), HORIZONTAL_ALIGNMENT_CENTER)
		_create_label(card, "1× GAME", Vector2(429.0, 247.0), Vector2(92.0, 18.0), 10, Color("7d8da1"), HORIZONTAL_ALIGNMENT_CENTER)

		var diagnostic := Panel.new()
		diagnostic.name = "GameplayCoreDiagnostic"
		diagnostic.position = Vector2(110.0 - core_radius, 73.0 - core_radius)
		diagnostic.size = Vector2.ONE * core_radius * 2.0
		diagnostic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		diagnostic.add_theme_stylebox_override("panel", _diagnostic_style(core_radius))
		diagnostic.visible = _diagnostics_visible
		actual_frame.add_child(diagnostic)
		actual_frame.move_child(diagnostic, actual_frame.get_child_count() - 1)
		_diagnostic_panels.append(diagnostic)

		var focus_button := Button.new()
		focus_button.name = "FocusButton"
		focus_button.position = Vector2.ZERO
		focus_button.size = CARD_SIZE
		focus_button.flat = true
		focus_button.text = ""
		focus_button.focus_mode = Control.FOCUS_NONE
		focus_button.pressed.connect(_focus_candidate.bind(index))
		card.add_child(focus_button)


func _build_controls() -> void:
	var controls: Array[Dictionary] = [
		{"text": "AUTO [A]", "callable": _set_auto_mode},
		{"text": "PHASE [C]", "callable": _cycle_checkpoint},
		{"text": "PAUSE [SPACE]", "callable": _toggle_pause},
		{"text": "PALETTE [P]", "callable": _toggle_palette},
		{"text": "BACKGROUND [B]", "callable": _cycle_background},
		{"text": "CORE [D]", "callable": _toggle_diagnostics},
		{"text": "RESET [R]", "callable": _reset_preview},
		{"text": "GRID [0]", "callable": _focus_candidate.bind(-1)},
	]
	var button_width: float = 145.0
	for index: int in range(controls.size()):
		var definition: Dictionary = controls[index]
		var button := Button.new()
		button.name = "ControlButton%d" % index
		button.text = String(definition["text"])
		button.position = Vector2(24.0 + float(index) * (button_width + 8.0), 708.0)
		button.size = Vector2(button_width, 34.0)
		button.focus_mode = Control.FOCUS_NONE
		var callback: Callable = definition["callable"]
		button.pressed.connect(callback)
		add_child(button)


func _load_assets(asset_config: Dictionary) -> Dictionary:
	var flipbook: Texture2D = _load_runtime_texture(String(asset_config.get("flipbook", "")))
	var particles: Texture2D = _load_runtime_texture(String(asset_config.get("particles", "")))
	var flow_mask: Texture2D = _load_runtime_texture(String(asset_config.get("flow_mask", "")))
	if flipbook == null or particles == null or flow_mask == null:
		return {}
	var columns: int = int(asset_config.get("atlas_columns", 4))
	var rows: int = int(asset_config.get("atlas_rows", 4))
	var cells: Array[Texture2D] = _slice_texture(particles, columns, rows)
	if cells.size() != columns * rows:
		push_error("Organic VFX particle atlas did not produce %d cells." % (columns * rows))
		return {}
	return {
		"flipbook": flipbook,
		"particles": particles,
		"flow_mask": flow_mask,
		"particle_cells": cells,
	}


func _load_runtime_texture(texture_path: String) -> Texture2D:
	if texture_path.is_empty():
		return null
	var resolved_path: String = texture_path
	if texture_path.begins_with("res://") or texture_path.begins_with("user://"):
		resolved_path = ProjectSettings.globalize_path(texture_path)
	var image := Image.new()
	var load_error: Error = image.load(resolved_path)
	if load_error != OK:
		push_error("Failed to load organic VFX source image: %s (%s)" % [texture_path, load_error])
		return null
	return ImageTexture.create_from_image(image)


func _slice_texture(texture: Texture2D, columns: int, rows: int) -> Array[Texture2D]:
	var cells: Array[Texture2D] = []
	if columns <= 0 or rows <= 0:
		return cells
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


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open organic VFX config: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Organic VFX config must contain a JSON object: %s" % path)
		return {}
	return parsed as Dictionary


func _apply_preview_time(force_seek: bool = true) -> void:
	for candidate: Node2D in _candidates:
		candidate.set_preview_time(_preview_time, force_seek)
	_update_status()


func _apply_checkpoint_time() -> void:
	var timing: Dictionary = _config.get("timing", {}) as Dictionary
	var checkpoints: Dictionary = timing.get("checkpoints", {}) as Dictionary
	match _checkpoint_mode:
		1:
			_preview_time = float(checkpoints.get("charge", 0.34))
		2:
			_preview_time = float(checkpoints.get("contact", 0.56))
		3:
			_preview_time = float(checkpoints.get("aftermath", 0.92))
		_:
			return
	_apply_preview_time()


func _set_auto_mode() -> void:
	_checkpoint_mode = 0
	_paused = false
	_update_status()


func _cycle_checkpoint() -> void:
	_checkpoint_mode = (_checkpoint_mode + 1) % 4
	if _checkpoint_mode == 0:
		_paused = false
	else:
		_paused = true
		_apply_checkpoint_time()
	_update_status()


func _toggle_pause() -> void:
	_paused = not _paused
	_update_status()


func _toggle_palette() -> void:
	_angry_dominant = not _angry_dominant
	for candidate: Node2D in _candidates:
		candidate.set_palette(_angry_dominant)
	_update_status()


func _cycle_background() -> void:
	_background_mode = (_background_mode + 1) % BACKGROUND_NAMES.size()
	_apply_background()
	_update_status()


func _apply_background() -> void:
	match _background_mode:
		0:
			_background.color = Color("04060b")
			_background_flow.visible = false
		1:
			_background.color = Color("07101a")
			_background_flow.visible = true
			_background_flow.modulate = Color(0.26, 0.44, 0.54, 0.075)
		2:
			_background.color = Color("0b0d13")
			_background_flow.visible = true
			_background_flow.modulate = Color(0.32, 0.18, 0.28, 0.105)
		_:
			pass
	for clutter: Sprite2D in _background_clutter:
		clutter.visible = _background_mode == 2


func _toggle_diagnostics() -> void:
	_diagnostics_visible = not _diagnostics_visible
	for diagnostic: Panel in _diagnostic_panels:
		diagnostic.visible = _diagnostics_visible
	_update_status()


func _reset_preview() -> void:
	_preview_time = 0.0
	_checkpoint_mode = 0
	_paused = false
	for candidate: Node2D in _candidates:
		candidate.reset_preview()
	_apply_preview_time()


func _focus_candidate(index: int) -> void:
	if index < -1 or index >= _cards.size():
		return
	_focused_candidate = index
	for card_index: int in range(_cards.size()):
		var card: Panel = _cards[card_index]
		if index == -1:
			card.visible = true
			card.position = _card_positions[card_index]
			card.scale = Vector2.ONE
			card.add_theme_stylebox_override("panel", _card_style(card_index, false))
		else:
			card.visible = card_index == index
			if card_index == index:
				card.position = Vector2(250.0, 188.0)
				card.scale = Vector2.ONE * 1.3
				card.add_theme_stylebox_override("panel", _card_style(card_index, true))
	_update_status()


func _update_status() -> void:
	if _status_label == null:
		return
	var checkpoint: String = CHECKPOINT_NAMES[_checkpoint_mode]
	var palette_name: String = "ANGRY PRIMARY" if _angry_dominant else "CALM PRIMARY"
	var focus_name: String = "GRID" if _focused_candidate < 0 else "FOCUS %s" % String.chr(65 + _focused_candidate)
	var pause_name: String = "PAUSED" if _paused else "PLAYING"
	_status_label.text = "%s · %s · %s · %s · %s" % [
		checkpoint,
		pause_name,
		palette_name,
		BACKGROUND_NAMES[_background_mode],
		focus_name,
	]


func _create_label(
	parent: Node,
	text: String,
	position: Vector2,
	size: Vector2,
	font_size: int,
	color: Color,
	alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position
	label.size = size
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _card_style(index: int, focused: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.090, 0.94)
	var accent: Color = Color("68bcdd") if index % 2 == 0 else Color("ed2f72")
	style.border_color = accent if focused else Color(accent, 0.36)
	style.set_border_width_all(2 if focused else 1)
	style.set_corner_radius_all(14)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.48)
	style.shadow_size = 9
	return style


func _diagnostic_style(radius: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color(0.20, 1.0, 0.72, 0.72)
	style.set_border_width_all(1)
	style.set_corner_radius_all(roundi(radius))
	return style


func _recursive_node_count(node: Node) -> int:
	var count: int = 1
	for child: Node in node.get_children():
		count += _recursive_node_count(child)
	return count
