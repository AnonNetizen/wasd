extends Control

const ASSET_PATH: String = "res://data/polygon_assets/open_book.polygon.json"
const INDEX_SCENE_PATH: String = "res://scenes/test_lab_index.tscn"
const POLYGON_ASSET_SCRIPT := preload("res://scripts/polygon_asset_2d.gd")
const SOURCE_PATH: String = "res://assets/polygon_art/open_book_source.png"

var _polygon_asset: Node2D
var _source_preview: TextureRect
var _stats_label: Label
var _page_turn_tween: Tween
var _clear_tween: Tween
var _elapsed_time: float = 0.0
var _clear_target: float = 1.0


func _ready() -> void:
	_build_interface()
	var load_error: Error = _polygon_asset.load_asset(ASSET_PATH)
	if load_error != OK:
		_stats_label.text = "Polygon asset load failed: %s" % error_string(load_error)
		return
	_refresh_stats()


func _process(delta: float) -> void:
	_elapsed_time += delta
	if _polygon_asset != null:
		_polygon_asset.set_animation_time(_elapsed_time)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_play_page_turn()
			KEY_C:
				_toggle_clear()
			KEY_M:
				_polygon_asset.set_debug_mesh_visible(
					not bool(_polygon_asset.get_runtime_stats()["debug_mesh_visible"])
				)
				_refresh_stats()
			KEY_O:
				_source_preview.visible = not _source_preview.visible
			KEY_R:
				reset_demo()
			KEY_ESCAPE:
				get_tree().change_scene_to_file(INDEX_SCENE_PATH)


func reset_demo() -> void:
	if _page_turn_tween != null:
		_page_turn_tween.kill()
	if _clear_tween != null:
		_clear_tween.kill()
	_elapsed_time = 0.0
	_clear_target = 1.0
	_polygon_asset.reset_visual()
	_polygon_asset.set_debug_mesh_visible(false)
	_source_preview.visible = true
	_refresh_stats()


func prepare_capture(page_turn_progress: float, clear_progress: float = 0.0) -> void:
	set_process(false)
	_elapsed_time = 1.75
	_polygon_asset.set_animation_time(_elapsed_time)
	_polygon_asset.set_page_turn_progress(page_turn_progress)
	_polygon_asset.set_clear_progress(clear_progress)
	_polygon_asset.set_debug_mesh_visible(false)
	_refresh_stats()


func get_polygon_asset() -> Node2D:
	return _polygon_asset


func _build_interface() -> void:
	var background := ColorRect.new()
	background.name = "Background"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("#10101a")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var top_band := ColorRect.new()
	top_band.name = "TopBand"
	top_band.position = Vector2.ZERO
	top_band.size = Vector2(1280.0, 104.0)
	top_band.color = Color("#1c1a2d")
	top_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_band)

	var title := Label.new()
	title.name = "Title"
	title.position = Vector2(34.0, 18.0)
	title.size = Vector2(760.0, 38.0)
	title.text = "OPEN BOOK · POLYGON ASSET PIPELINE"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("#f0ddad"))
	add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.position = Vector2(36.0, 58.0)
	subtitle.size = Vector2(1050.0, 28.0)
	subtitle.text = "Source PNG is authoring evidence only · runtime reads Polygon JSON"
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color("#918ca8"))
	add_child(subtitle)

	var source_panel := _make_panel("SourcePanel", Vector2(28.0, 120.0), Vector2(506.0, 492.0))
	add_child(source_panel)
	var source_heading := _make_label(
		"SourceHeading",
		"SOURCE PNG · AUTHORING INPUT",
		Vector2(18.0, 14.0),
		Vector2(450.0, 30.0),
		15,
		Color("#c99a5d")
	)
	source_panel.add_child(source_heading)
	_source_preview = TextureRect.new()
	_source_preview.name = "SourcePreview"
	_source_preview.position = Vector2(24.0, 54.0)
	_source_preview.size = Vector2(458.0, 410.0)
	_source_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_source_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_source_preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_source_preview.texture = _load_source_texture()
	source_panel.add_child(_source_preview)

	var runtime_panel := _make_panel(
		"RuntimePanel",
		Vector2(554.0, 120.0),
		Vector2(698.0, 492.0)
	)
	add_child(runtime_panel)
	var runtime_heading := _make_label(
		"RuntimeHeading",
		"RUNTIME · ARRAYMESH + OUTLINE",
		Vector2(18.0, 14.0),
		Vector2(500.0, 30.0),
		15,
		Color("#69d5d0")
	)
	runtime_panel.add_child(runtime_heading)
	_polygon_asset = POLYGON_ASSET_SCRIPT.new()
	_polygon_asset.name = "PolygonAsset"
	_polygon_asset.position = Vector2(348.0, 255.0)
	_polygon_asset.scale = Vector2.ONE * 2.05
	runtime_panel.add_child(_polygon_asset)

	var footer := _make_panel("Footer", Vector2(28.0, 630.0), Vector2(1224.0, 104.0))
	add_child(footer)
	var controls := _make_label(
		"Controls",
		"Space  page turn   ·   C  clear / restore   ·   M  mesh   ·   O  source   ·   R  reset   ·   Esc  index",
		Vector2(18.0, 13.0),
		Vector2(1180.0, 26.0),
		14,
		Color("#d9d3c7")
	)
	footer.add_child(controls)
	_stats_label = _make_label(
		"Stats",
		"Loading Polygon asset…",
		Vector2(18.0, 48.0),
		Vector2(1180.0, 42.0),
		13,
		Color("#918ca8")
	)
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(_stats_label)


func _play_page_turn() -> void:
	if _page_turn_tween != null:
		_page_turn_tween.kill()
	_polygon_asset.set_page_turn_progress(0.0)
	_page_turn_tween = create_tween()
	_page_turn_tween.set_trans(Tween.TRANS_SINE)
	_page_turn_tween.set_ease(Tween.EASE_IN_OUT)
	_page_turn_tween.tween_method(
		_polygon_asset.set_page_turn_progress,
		0.0,
		1.0,
		1.2
	)


func _toggle_clear() -> void:
	if _clear_tween != null:
		_clear_tween.kill()
	var current_progress := float(_polygon_asset.get_runtime_stats()["clear_progress"])
	_clear_tween = create_tween()
	_clear_tween.set_trans(Tween.TRANS_CUBIC)
	_clear_tween.set_ease(Tween.EASE_IN_OUT)
	_clear_tween.tween_method(
		_polygon_asset.set_clear_progress,
		current_progress,
		_clear_target,
		1.0
	)
	_clear_target = 0.0 if _clear_target > 0.5 else 1.0


func _refresh_stats() -> void:
	var data: Dictionary = _polygon_asset.get_asset_data()
	if data.is_empty():
		return
	var stats: Dictionary = data.get("stats", {})
	var runtime_stats: Dictionary = _polygon_asset.get_runtime_stats()
	_stats_label.text = (
		"%d faces · %d logical vertices · %d connected component · "
		+ "%d MeshInstance2D · %d draw surface · source texture dependency: %s · mesh debug: %s"
	) % [
		int(stats.get("face_count", 0)),
		int(stats.get("logical_vertex_count", 0)),
		int(stats.get("connected_components", 0)),
		int(runtime_stats.get("mesh_instance_count", 0)),
		int(runtime_stats.get("surface_count", 0)),
		"none" if not bool(runtime_stats.get("has_texture", true)) else "unexpected",
		"on" if bool(runtime_stats.get("debug_mesh_visible", false)) else "off",
	]


func _load_source_texture() -> ImageTexture:
	var image := Image.new()
	var error := image.load(ProjectSettings.globalize_path(SOURCE_PATH))
	if error != OK:
		push_error("Failed to load source preview: %s" % error_string(error))
		return null
	return ImageTexture.create_from_image(image)


func _make_panel(node_name: String, panel_position: Vector2, panel_size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.position = panel_position
	panel.size = panel_size
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#181724")
	style.border_color = Color("#39364d")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _make_label(
	node_name: String,
	text_value: String,
	label_position: Vector2,
	label_size: Vector2,
	font_size: int,
	font_color: Color
) -> Label:
	var label := Label.new()
	label.name = node_name
	label.position = label_position
	label.size = label_size
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	return label
