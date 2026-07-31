extends Control

const ASSET_PATH: String = "res://data/polygon_assets/apple.polygon.json"
const AUTO_CYCLE_DURATION: float = 8.6
const AUTO_DISSOLVE_END: float = 6.8
const AUTO_DISSOLVE_START: float = 5.6
const AUTO_GENERATE_END: float = 0.8
const AUTO_HOLD_END: float = 7.2
const AUTO_RESTORE_END: float = 8.0
const INDEX_SCENE_PATH: String = "res://scenes/test_lab_index.tscn"
const MOVEMENT_CENTER := Vector2(348.0, 260.0)
const MOVEMENT_RADIUS := Vector2(58.0, 34.0)
const DEMO_MOVEMENT_DURATION: float = (
	AUTO_DISSOLVE_START
	- AUTO_GENERATE_END
)
const DEMO_ANGULAR_SPEED: float = (
	TAU
	/ DEMO_MOVEMENT_DURATION
)
const DEMO_FULL_DEFORMATION_SPEED: float = (
	MOVEMENT_RADIUS.x * DEMO_ANGULAR_SPEED
	/ 0.85
)
const POLYGON_ASSET_SCRIPT := preload("res://scripts/polygon_asset_2d.gd")
const SOURCE_PATH: String = "res://assets/polygon_art/apple_source.png"

var _polygon_asset: PolygonAsset2D
var _source_preview: TextureRect
var _stats_label: Label
var _demo_status_label: Label
var _dissolve_tween: Tween
var _generation_tween: Tween
var _elapsed_time: float = 0.0
var _dissolve_target: float = 1.0
var _auto_demo_enabled: bool = true
var _auto_cycle_time: float = 0.0


func _ready() -> void:
	_build_interface()
	var load_error: Error = _polygon_asset.load_asset(ASSET_PATH)
	if load_error != OK:
		_stats_label.text = "Polygon asset load failed: %s" % error_string(load_error)
		_auto_demo_enabled = false
		return
	var custom_animation: Dictionary = _polygon_asset.get_asset_data().get(
		"custom_animation",
		{}
	)
	if not custom_animation.is_empty():
		_stats_label.text = "Apple validation expects no semantic adapter."
		_auto_demo_enabled = false
		return
	_set_auto_demo_enabled(true)
	_refresh_stats()


func _process(delta: float) -> void:
	_elapsed_time += delta
	if _polygon_asset != null:
		_polygon_asset.set_animation_time(_elapsed_time)
	if _auto_demo_enabled:
		_auto_cycle_time = fposmod(
			_auto_cycle_time + delta,
			AUTO_CYCLE_DURATION
		)
		_apply_auto_demo_state()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_C:
				_toggle_dissolve()
			KEY_G:
				_play_generation()
			KEY_A:
				_set_auto_demo_enabled(not _auto_demo_enabled)
			KEY_M:
				_polygon_asset.set_debug_mesh_visible(
					not bool(
						_polygon_asset.get_runtime_stats()[
							"debug_mesh_visible"
						]
					)
				)
				_refresh_stats()
			KEY_O:
				_source_preview.visible = not _source_preview.visible
			KEY_R:
				reset_demo()
			KEY_ESCAPE:
				get_tree().change_scene_to_file(INDEX_SCENE_PATH)


func reset_demo() -> void:
	_stop_manual_tweens()
	_elapsed_time = 0.0
	_dissolve_target = 1.0
	_polygon_asset.reset_visual()
	_polygon_asset.set_debug_mesh_visible(false)
	_source_preview.visible = true
	_set_auto_demo_enabled(true)
	_refresh_stats()


func prepare_capture(
	generation_progress: float,
	dissolve_progress: float,
	movement_direction: Vector2,
	movement_amount: float
) -> void:
	_auto_demo_enabled = false
	set_process(false)
	_polygon_asset.set_process(false)
	_elapsed_time = 1.75
	_polygon_asset.set_animation_time(_elapsed_time)
	_polygon_asset.position = MOVEMENT_CENTER
	_polygon_asset.set_movement_state(
		movement_direction,
		movement_amount
	)
	_polygon_asset.set_generation_progress(generation_progress)
	_polygon_asset.set_dissolve_progress(dissolve_progress)
	if _demo_status_label != null:
		_demo_status_label.text = "CAPTURE · GENERIC APPLE"
		_demo_status_label.add_theme_color_override(
			"font_color",
			Color("#69d5d0")
		)
	_polygon_asset.set_debug_mesh_visible(false)
	_refresh_stats()


func get_polygon_asset() -> Node2D:
	return _polygon_asset


func get_auto_demo_state() -> Dictionary:
	return {
		"enabled": _auto_demo_enabled,
		"cycle_time": _auto_cycle_time,
		"cycle_duration": AUTO_CYCLE_DURATION,
		"phase": _auto_demo_phase(),
	}


func debug_set_auto_demo_time(seconds: float) -> void:
	_stop_manual_tweens()
	_auto_demo_enabled = true
	var target_time := fposmod(
		maxf(seconds, 0.0),
		AUTO_CYCLE_DURATION
	)
	_polygon_asset.reset_visual()
	_auto_cycle_time = 0.0
	while _auto_cycle_time < target_time:
		var step_delta := minf(
			1.0 / 60.0,
			target_time - _auto_cycle_time
		)
		_auto_cycle_time += step_delta
		_apply_auto_demo_state()
		_polygon_asset.advance_movement_deformation(step_delta)


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

	var title := _make_label(
		"Title",
		"GENERIC POLYGON PIPELINE · APPLE VALIDATION",
		Vector2(34.0, 18.0),
		Vector2(800.0, 38.0),
		26,
		Color("#f0ddad")
	)
	add_child(title)

	var subtitle := _make_label(
		"Subtitle",
		"Damped soft-body response · velocity target · no idle breathing",
		Vector2(36.0, 58.0),
		Vector2(850.0, 28.0),
		15,
		Color("#918ca8")
	)
	add_child(subtitle)

	_demo_status_label = _make_label(
		"DemoStatus",
		"AUTO DEMO · GENERATION",
		Vector2(920.0, 22.0),
		Vector2(326.0, 56.0),
		14,
		Color("#69d5d0")
	)
	_demo_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_demo_status_label)

	var source_panel := _make_panel(
		"SourcePanel",
		Vector2(28.0, 120.0),
		Vector2(506.0, 492.0)
	)
	add_child(source_panel)
	source_panel.add_child(_make_label(
		"SourceHeading",
		"SOURCE PNG · SHAPE + COLOR INPUT",
		Vector2(18.0, 14.0),
		Vector2(450.0, 30.0),
		15,
		Color("#f1873f")
	))
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
	runtime_panel.add_child(_make_label(
		"RuntimeHeading",
		"RUNTIME · GENERIC ARRAYMESH",
		Vector2(18.0, 14.0),
		Vector2(500.0, 30.0),
		15,
		Color("#69d5d0")
	))
	_polygon_asset = POLYGON_ASSET_SCRIPT.new()
	_polygon_asset.name = "PolygonAsset"
	_polygon_asset.position = MOVEMENT_CENTER
	_polygon_asset.scale = Vector2.ONE * 1.75
	runtime_panel.add_child(_polygon_asset)

	var footer := _make_panel(
		"Footer",
		Vector2(28.0, 630.0),
		Vector2(1224.0, 104.0)
	)
	add_child(footer)
	footer.add_child(_make_label(
		"Controls",
		"A auto · G generate · C dissolve / restore · M mesh · O source · R reset · Esc index",
		Vector2(18.0, 13.0),
		Vector2(1180.0, 26.0),
		14,
		Color("#d9d3c7")
	))
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


func _play_generation() -> void:
	_set_auto_demo_enabled(false)
	if _generation_tween != null:
		_generation_tween.kill()
	_polygon_asset.set_dissolve_progress(0.0)
	_polygon_asset.set_generation_progress(0.0)
	_generation_tween = create_tween()
	_generation_tween.set_trans(Tween.TRANS_CUBIC)
	_generation_tween.set_ease(Tween.EASE_OUT)
	_generation_tween.tween_method(
		_polygon_asset.set_generation_progress,
		0.0,
		1.0,
		1.0
	)


func _toggle_dissolve() -> void:
	_set_auto_demo_enabled(false)
	if _dissolve_tween != null:
		_dissolve_tween.kill()
	var current_progress := float(
		_polygon_asset.get_runtime_stats()["dissolve_progress"]
	)
	_dissolve_tween = create_tween()
	_dissolve_tween.set_trans(Tween.TRANS_CUBIC)
	_dissolve_tween.set_ease(Tween.EASE_IN_OUT)
	_dissolve_tween.tween_method(
		_polygon_asset.set_dissolve_progress,
		current_progress,
		_dissolve_target,
		1.0
	)
	_dissolve_target = 0.0 if _dissolve_target > 0.5 else 1.0


func _set_auto_demo_enabled(enabled: bool) -> void:
	_stop_manual_tweens()
	_auto_demo_enabled = enabled
	_auto_cycle_time = 0.0
	if _polygon_asset == null:
		return
	if enabled:
		_apply_auto_demo_state()
		return
	_polygon_asset.set_generation_progress(1.0)
	_polygon_asset.set_dissolve_progress(0.0)
	_polygon_asset.position = MOVEMENT_CENTER
	_polygon_asset.set_movement_state(Vector2.ZERO, 0.0)
	if _demo_status_label != null:
		_demo_status_label.text = "MANUAL · A TO RESUME AUTO"
		_demo_status_label.add_theme_color_override(
			"font_color",
			Color("#918ca8")
		)


func _stop_manual_tweens() -> void:
	if _dissolve_tween != null:
		_dissolve_tween.kill()
		_dissolve_tween = null
	if _generation_tween != null:
		_generation_tween.kill()
		_generation_tween = null


func _apply_auto_demo_state() -> void:
	if _polygon_asset == null:
		return
	var generation_progress := 1.0
	var dissolve_progress := 0.0
	var movement_velocity := Vector2.ZERO
	_polygon_asset.position = (
		MOVEMENT_CENTER
		+ Vector2(MOVEMENT_RADIUS.x, 0.0)
	)
	if _auto_cycle_time < AUTO_GENERATE_END:
		generation_progress = _smooth_unit(
			_auto_cycle_time / AUTO_GENERATE_END
		)
	elif _auto_cycle_time < AUTO_DISSOLVE_START:
		var movement_state := _movement_state_for_time(
			_auto_cycle_time
			- AUTO_GENERATE_END
		)
		_polygon_asset.position = movement_state["position"]
		movement_velocity = movement_state["velocity"]
	elif _auto_cycle_time < AUTO_DISSOLVE_END:
		dissolve_progress = _smooth_unit(
			(_auto_cycle_time - AUTO_DISSOLVE_START)
			/ (AUTO_DISSOLVE_END - AUTO_DISSOLVE_START)
		)
	elif _auto_cycle_time < AUTO_HOLD_END:
		dissolve_progress = 1.0
	elif _auto_cycle_time < AUTO_RESTORE_END:
		dissolve_progress = 1.0 - _smooth_unit(
			(_auto_cycle_time - AUTO_HOLD_END)
			/ (AUTO_RESTORE_END - AUTO_HOLD_END)
		)
	_polygon_asset.set_movement_velocity(
		movement_velocity,
		DEMO_FULL_DEFORMATION_SPEED
	)
	_polygon_asset.set_generation_progress(generation_progress)
	_polygon_asset.set_dissolve_progress(dissolve_progress)
	if _demo_status_label != null:
		_demo_status_label.text = "AUTO DEMO · %s" % _auto_demo_phase()
		_demo_status_label.add_theme_color_override(
			"font_color",
			Color("#69d5d0")
		)


func _auto_demo_phase() -> String:
	if not _auto_demo_enabled:
		return "MANUAL"
	if _auto_cycle_time < AUTO_GENERATE_END:
		return "GENERATION"
	if _auto_cycle_time < AUTO_DISSOLVE_START:
		return _movement_phase_name(
			_auto_cycle_time
			- AUTO_GENERATE_END
		)
	if _auto_cycle_time < AUTO_DISSOLVE_END:
		return "DISSOLVE"
	if _auto_cycle_time < AUTO_HOLD_END:
		return "DISSOLVED"
	if _auto_cycle_time < AUTO_RESTORE_END:
		return "RESTORE"
	return "RESET"


func _movement_state_for_time(seconds: float) -> Dictionary:
	var movement_duration := (
		AUTO_DISSOLVE_START
		- AUTO_GENERATE_END
	)
	var normalized := clampf(
		seconds / movement_duration,
		0.0,
		1.0
	)
	var angle := normalized * TAU
	var position := (
		MOVEMENT_CENTER
		+ Vector2(
			cos(angle) * MOVEMENT_RADIUS.x,
			sin(angle) * MOVEMENT_RADIUS.y
		)
	)
	var velocity := Vector2(
		-sin(angle) * MOVEMENT_RADIUS.x * DEMO_ANGULAR_SPEED,
		cos(angle) * MOVEMENT_RADIUS.y * DEMO_ANGULAR_SPEED
	)
	return {
		"position": position,
		"velocity": velocity,
	}


func _movement_phase_name(seconds: float) -> String:
	var state := _movement_state_for_time(seconds)
	var velocity: Vector2 = state["velocity"]
	if absf(velocity.x) > absf(velocity.y):
		return (
			"MOVE RIGHT"
			if velocity.x > 0.0
			else "MOVE LEFT"
		)
	return (
		"MOVE DOWN"
		if velocity.y > 0.0
		else "MOVE UP"
	)


func _smooth_unit(value: float) -> float:
	var clamped := clampf(value, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)


func _refresh_stats() -> void:
	var data: Dictionary = _polygon_asset.get_asset_data()
	if data.is_empty():
		return
	var stats: Dictionary = data.get("stats", {})
	var runtime_stats: Dictionary = _polygon_asset.get_runtime_stats()
	_stats_label.text = (
		"silhouette-only · per-asset palette · %d faces · "
		+ "%d logical vertices · %d connected component · "
		+ "%d moving faces · %d MeshInstance2D · %d draw surface · "
		+ "semantic adapter: none · source texture dependency: %s · "
		+ "mesh debug: %s"
	) % [
		int(stats.get("face_count", 0)),
		int(stats.get("logical_vertex_count", 0)),
		int(stats.get("connected_components", 0)),
		int(runtime_stats.get("primary_motion_face_count", 0)),
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


func _make_panel(
	node_name: String,
	panel_position: Vector2,
	panel_size: Vector2
) -> Panel:
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
