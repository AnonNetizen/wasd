extends Node2D

const INDEX_SCENE_PATH: String = "res://scenes/test_lab_index.tscn"
const CPU_SOURCE_PATH: String = "res://assets/svg_curve/cpu_mod_source.svg"
const SHAPE_SCRIPT := preload("res://scripts/svg_curve_outline_shape.gd")
const VIEWPORT_SIZE := Vector2(1280.0, 760.0)
const CPU_BORDER_COLOR := Color(0.407843, 0.737255, 0.866667, 1.0)
const LARGE_ID: String = "large"
const DETAIL_ID: String = "detail"
const LIST_ID: String = "list"
const LARGE_BASE_POSITION := Vector2(384.0, 380.0)
const DETAIL_POSITION := Vector2(860.0, 300.0)
const LIST_POSITION := Vector2(1068.0, 300.0)
const LARGE_TARGET_SIZE: float = 360.0
const DETAIL_TARGET_SIZE: float = 112.0
const LIST_TARGET_SIZE: float = 40.0
const LARGE_BORDER_WIDTH: float = 10.0
const DETAIL_BORDER_WIDTH: float = 4.0
const LIST_BORDER_WIDTH: float = 2.0
const LARGE_STAR_SCALE: float = 0.90
const DETAIL_STAR_SCALE: float = 1.25
const LIST_STAR_SCALE: float = 1.80

var _motion_paused: bool = false
var _samples: Dictionary = {}
var _status_label: Label
var _time: float = 0.0


func _ready() -> void:
	_build_stage()
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_on_viewport_size_changed()
	_update_presentation()
	queue_redraw()


func _process(delta: float) -> void:
	if not _motion_paused:
		_time += delta
	_update_presentation()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_SPACE:
			debug_set_motion_paused(not _motion_paused)
		KEY_D:
			debug_set_large_controls_visible(not debug_sample_controls_visible(LARGE_ID))
		KEY_R:
			debug_reset()
		KEY_ESCAPE:
			_return_to_index()
		_:
			return
	get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEWPORT_SIZE), Color(0.004, 0.008, 0.022, 1.0))
	draw_rect(
		Rect2(116.0, 132.0, 536.0, 500.0),
		Color(0.018, 0.036, 0.070, 0.96),
		true
	)
	draw_rect(
		Rect2(770.0, 184.0, 190.0, 190.0),
		Color(0.020, 0.044, 0.080, 0.98),
		true
	)
	draw_rect(
		Rect2(1_010.0, 252.0, 116.0, 96.0),
		Color(0.020, 0.044, 0.080, 0.98),
		true
	)
	draw_rect(
		Rect2(116.0, 132.0, 536.0, 500.0),
		Color(0.16, 0.45, 0.62, 0.72),
		false,
		2.0
	)
	draw_rect(
		Rect2(770.0, 184.0, 190.0, 190.0),
		Color(0.16, 0.45, 0.62, 0.72),
		false,
		2.0
	)
	draw_rect(
		Rect2(1_010.0, 252.0, 116.0, 96.0),
		Color(0.16, 0.45, 0.62, 0.72),
		false,
		2.0
	)


func debug_set_preview_time(time_seconds: float) -> void:
	_time = maxf(time_seconds, 0.0)
	_motion_paused = true
	_update_presentation()


func debug_set_motion_paused(paused: bool) -> void:
	_motion_paused = paused
	_update_status()


func debug_motion_paused() -> bool:
	return _motion_paused


func debug_set_large_controls_visible(controls_visible: bool) -> void:
	var large_shape: TestLabSvgCurveOutlineShape = _sample_shape(LARGE_ID)
	if large_shape != null:
		large_shape.set_controls_visible(controls_visible)
	_update_status()


func debug_reset() -> void:
	_time = 0.0
	_motion_paused = false
	debug_set_large_controls_visible(false)
	_update_presentation()


func debug_sample_ids() -> PackedStringArray:
	return PackedStringArray([LARGE_ID, DETAIL_ID, LIST_ID])


func debug_sample_subpath_count(sample_id: String) -> int:
	var shape: TestLabSvgCurveOutlineShape = _sample_shape(sample_id)
	return shape.subpath_count() if shape != null else 0


func debug_sample_path_node_count(sample_id: String) -> int:
	var shape: TestLabSvgCurveOutlineShape = _sample_shape(sample_id)
	return shape.path_node_count() if shape != null else 0


func debug_sample_border_line_count(sample_id: String) -> int:
	var shape: TestLabSvgCurveOutlineShape = _sample_shape(sample_id)
	return shape.border_line_count() if shape != null else 0


func debug_sample_controls_overlay_count(sample_id: String) -> int:
	var shape: TestLabSvgCurveOutlineShape = _sample_shape(sample_id)
	return shape.controls_overlay_count() if shape != null else 0


func debug_sample_controls_visible(sample_id: String) -> bool:
	var shape: TestLabSvgCurveOutlineShape = _sample_shape(sample_id)
	return shape != null and shape.controls_visible()


func debug_sample_curve_segment_count(sample_id: String) -> int:
	var shape: TestLabSvgCurveOutlineShape = _sample_shape(sample_id)
	return shape.curve_segment_count() if shape != null else 0


func debug_sample_curve_point_count(sample_id: String) -> int:
	var shape: TestLabSvgCurveOutlineShape = _sample_shape(sample_id)
	return shape.curve_point_count() if shape != null else 0


func debug_sample_triangle_count(sample_id: String) -> int:
	var shape: TestLabSvgCurveOutlineShape = _sample_shape(sample_id)
	return shape.triangle_count() if shape != null else 0


func debug_sample_fill_area_ratio(sample_id: String) -> float:
	var shape: TestLabSvgCurveOutlineShape = _sample_shape(sample_id)
	return shape.fill_area_ratio() if shape != null else 0.0


func debug_sample_all_curves_closed(sample_id: String) -> bool:
	var shape: TestLabSvgCurveOutlineShape = _sample_shape(sample_id)
	return shape != null and shape.all_curves_closed()


func debug_sample_screen_size(sample_id: String) -> Vector2:
	var shape: TestLabSvgCurveOutlineShape = _sample_shape(sample_id)
	if shape == null:
		return Vector2.ZERO
	return shape.source_bounds().size * shape.scale.abs()


func debug_sample_border_width(sample_id: String) -> float:
	var shape: TestLabSvgCurveOutlineShape = _sample_shape(sample_id)
	return shape.border_width() * absf(shape.scale.x) if shape != null else 0.0


func debug_sample_star_scale(sample_id: String) -> float:
	var material: ShaderMaterial = debug_sample_perspective_material(sample_id)
	return float(material.get_shader_parameter("star_scale")) if material != null else 0.0


func debug_sample_perspective_material(sample_id: String) -> ShaderMaterial:
	var shape: TestLabSvgCurveOutlineShape = _sample_shape(sample_id)
	return shape.perspective_material() if shape != null else null


func debug_sample_border_color(sample_id: String) -> Color:
	var shape: TestLabSvgCurveOutlineShape = _sample_shape(sample_id)
	return shape.border_color() if shape != null else Color.TRANSPARENT


func debug_sample_border_uses_shader(sample_id: String) -> bool:
	var shape: TestLabSvgCurveOutlineShape = _sample_shape(sample_id)
	return shape != null and shape.border_uses_shader()


func debug_sample_position(sample_id: String) -> Vector2:
	var shape: TestLabSvgCurveOutlineShape = _sample_shape(sample_id)
	return shape.position if shape != null else Vector2.ZERO


func debug_sample_fill_screen_samples(sample_id: String) -> PackedVector2Array:
	var shape: TestLabSvgCurveOutlineShape = _sample_shape(sample_id)
	return _to_screen_samples(shape, shape.fill_sample_points() if shape != null else PackedVector2Array())


func debug_sample_border_screen_samples(sample_id: String) -> PackedVector2Array:
	var shape: TestLabSvgCurveOutlineShape = _sample_shape(sample_id)
	return _to_screen_samples(
		shape,
		shape.border_sample_points() if shape != null else PackedVector2Array()
	)


func debug_descendant_count() -> int:
	return _count_descendants(self)


func _build_stage() -> void:
	_create_sample(
		LARGE_ID,
		LARGE_BASE_POSITION,
		LARGE_TARGET_SIZE,
		LARGE_BORDER_WIDTH,
		LARGE_STAR_SCALE
	)
	_create_sample(
		DETAIL_ID,
		DETAIL_POSITION,
		DETAIL_TARGET_SIZE,
		DETAIL_BORDER_WIDTH,
		DETAIL_STAR_SCALE
	)
	_create_sample(
		LIST_ID,
		LIST_POSITION,
		LIST_TARGET_SIZE,
		LIST_BORDER_WIDTH,
		LIST_STAR_SCALE
	)

	var overlay := CanvasLayer.new()
	overlay.name = "Overlay"
	add_child(overlay)
	_add_header(overlay)
	_add_labels(overlay)


func _create_sample(
	sample_id: String,
	position_value: Vector2,
	target_size: float,
	border_width: float,
	star_scale: float
) -> void:
	var shape := SHAPE_SCRIPT.new() as TestLabSvgCurveOutlineShape
	shape.name = "%sCpuModIcon" % sample_id.capitalize()
	shape.configure(CPU_SOURCE_PATH, CPU_BORDER_COLOR, star_scale)
	shape.position = position_value
	add_child(shape)
	var bounds: Rect2 = shape.source_bounds()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		push_error("CPU SVG sample failed to produce valid bounds: %s" % sample_id)
		return
	var scale_value: float = target_size / maxf(bounds.size.x, bounds.size.y)
	shape.scale = Vector2.ONE * scale_value
	shape.set_border_width(border_width / scale_value)
	shape.set_controls_visible(false)
	_samples[sample_id] = shape


func _add_header(overlay: CanvasLayer) -> void:
	var header := ColorRect.new()
	header.name = "Header"
	header.color = Color(0.006, 0.014, 0.038, 0.96)
	header.position = Vector2.ZERO
	header.size = Vector2(VIEWPORT_SIZE.x, 104.0)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(header)

	var title := Label.new()
	title.name = "Title"
	title.text = "CPU Gear Mod 透视图标 / CPU MOD ICON"
	title.position = Vector2(30.0, 16.0)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.68, 0.90, 1.0, 1.0))
	header.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "单一 SVG CPU 轮廓 · 固定空间星窗 · 360 / 112 / 40 px 三档可读性"
	subtitle.position = Vector2(32.0, 60.0)
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.52, 0.72, 0.84, 1.0))
	header.add_child(subtitle)

	var exit_button := Button.new()
	exit_button.name = "ExitButton"
	exit_button.text = "返回实验索引 [Esc]"
	exit_button.position = Vector2(1_060.0, 28.0)
	exit_button.size = Vector2(190.0, 48.0)
	exit_button.pressed.connect(_return_to_index)
	header.add_child(exit_button)


func _add_labels(overlay: CanvasLayer) -> void:
	_add_label(
		overlay,
		"LargeLabel",
		"360 px 放大样本 · 缓慢移动展示 SCREEN_UV 固定空间",
		Vector2(150.0, 594.0),
		Vector2(470.0, 30.0),
		16,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_add_label(
		overlay,
		"DetailLabel",
		"112 px\n图鉴详情",
		Vector2(790.0, 386.0),
		Vector2(150.0, 54.0),
		16,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_add_label(
		overlay,
		"ListLabel",
		"40 px\n列表图标",
		Vector2(995.0, 362.0),
		Vector2(148.0, 54.0),
		16,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_add_label(
		overlay,
		"Description",
		(
			"通用 CPU / Gear Mod 候选，不绑定现有 Mod。\n"
			+ "轮廓使用项目青色 #68BCDD；小尺寸提高星窗尺度，\n"
			+ "避免星点缩成暗块。诊断层只作用于放大样本。"
		),
		Vector2(770.0, 470.0),
		Vector2(440.0, 100.0),
		16,
		HORIZONTAL_ALIGNMENT_LEFT
	)
	_status_label = _add_label(
		overlay,
		"Status",
		"",
		Vector2(770.0, 574.0),
		Vector2(440.0, 54.0),
		15,
		HORIZONTAL_ALIGNMENT_LEFT
	)
	_add_label(
		overlay,
		"Controls",
		"Space 暂停 / 继续 · D 显示放大样本控制点 · R 复原 · Esc 返回",
		Vector2(180.0, 700.0),
		Vector2(920.0, 30.0),
		16,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _add_label(
	overlay: CanvasLayer,
	label_name: String,
	label_text: String,
	position_value: Vector2,
	size_value: Vector2,
	font_size: int,
	alignment: HorizontalAlignment
) -> Label:
	var label := Label.new()
	label.name = label_name
	label.text = label_text
	label.position = position_value
	label.size = size_value
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.69, 0.85, 0.93, 1.0))
	overlay.add_child(label)
	return label


func _update_presentation() -> void:
	var large_shape: TestLabSvgCurveOutlineShape = _sample_shape(LARGE_ID)
	if large_shape != null:
		large_shape.position = LARGE_BASE_POSITION + Vector2(
			sin(_time * 0.62) * 24.0,
			sin(_time * 0.41 + 0.6) * 8.0
		)
	for sample_id: String in debug_sample_ids():
		var shape: TestLabSvgCurveOutlineShape = _sample_shape(sample_id)
		if shape != null:
			shape.set_animation_time(_time)
	_update_status()


func _update_status() -> void:
	if _status_label == null:
		return
	_status_label.text = (
		"状态：%s · 放大控制点：%s\n"
		+ "屏幕边宽：%.0f / %.0f / %.0f px · 星窗尺度：%.2f / %.2f / %.2f"
	) % [
		"已暂停" if _motion_paused else "运行中",
		"显示" if debug_sample_controls_visible(LARGE_ID) else "隐藏",
		debug_sample_border_width(LARGE_ID),
		debug_sample_border_width(DETAIL_ID),
		debug_sample_border_width(LIST_ID),
		debug_sample_star_scale(LARGE_ID),
		debug_sample_star_scale(DETAIL_ID),
		debug_sample_star_scale(LIST_ID),
	]


func _sample_shape(sample_id: String) -> TestLabSvgCurveOutlineShape:
	return _samples.get(sample_id) as TestLabSvgCurveOutlineShape


func _to_screen_samples(
	shape: TestLabSvgCurveOutlineShape,
	local_samples: PackedVector2Array
) -> PackedVector2Array:
	var screen_samples := PackedVector2Array()
	if shape == null:
		return screen_samples
	for local_point in local_samples:
		screen_samples.append(shape.to_global(local_point))
	return screen_samples


func _count_descendants(node: Node) -> int:
	var count: int = 0
	for child in node.get_children():
		count += 1
		count += _count_descendants(child)
	return count


func _on_viewport_size_changed() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	var viewport_aspect: float = viewport_size.x / maxf(viewport_size.y, 1.0)
	for sample_id: String in debug_sample_ids():
		var shape: TestLabSvgCurveOutlineShape = _sample_shape(sample_id)
		if shape != null:
			shape.set_viewport_aspect(viewport_aspect)


func _return_to_index() -> void:
	var error: Error = get_tree().change_scene_to_file(INDEX_SCENE_PATH)
	if error != OK:
		push_error("Failed to return to Test Lab index: %s" % error)
