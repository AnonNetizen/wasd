class_name TestLabTearCoreMaterialSwitcher
extends "res://scripts/tear_core_bullet_focus_test.gd"

## Seven-material comparison scene for the selected tear-core projectile silhouette.

const DEFAULT_MATERIAL_INDEX: int = SAMPLE_SCRIPT.MaterialStyle.CRYSTAL_GLASS
const MATERIAL_LABELS: Array[String] = [
	"0  胶质基准 / GEL",
	"1  水晶玻璃 / CRYSTAL GLASS",
	"2  金属珐琅 / ENAMEL METAL",
	"3  哑光陶瓷 / MATTE CERAMIC",
	"4  能量电浆 / PLASMA ENERGY",
	"5  墨液烟雾 / INK SMOKE",
	"6  矿石晶核 / MINERAL CORE",
]
const MATERIAL_NAMES: Array[String] = [
	"胶质基准 / GEL",
	"水晶玻璃 / CRYSTAL GLASS",
	"金属珐琅 / ENAMEL METAL",
	"哑光陶瓷 / MATTE CERAMIC",
	"能量电浆 / PLASMA ENERGY",
	"墨液烟雾 / INK SMOKE",
	"矿石晶核 / MINERAL CORE",
]
const MATERIAL_DESCRIPTIONS: Array[String] = [
	"软质胶壳 · 深色内馅 · 湿润高光",
	"半透明硬边 · 三块内部切面 · 折射碎光",
	"暗色金属边 · 不透明珐琅面 · 移动镜面亮带",
	"厚实平涂 · 宽柔釉面高光 · 细裂纹",
	"暗色约束边 · 明亮内核 · 判定圆内能量层",
	"清晰硬外轮廓 · 缓慢流动墨团 · 圆润烟墨尾",
	"粗糙分面 · 内部裂隙 · 少量硬质闪点",
]

var _material_picker: OptionButton
var _selected_material: int = DEFAULT_MATERIAL_INDEX


func _ready() -> void:
	super._ready()
	_build_material_picker()
	_apply_material_style(DEFAULT_MATERIAL_INDEX)


func debug_material_item_count() -> int:
	return _material_picker.item_count


func debug_material_labels() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for index in range(_material_picker.item_count):
		result.append(_material_picker.get_item_text(index))
	return result


func debug_selected_material() -> int:
	return _selected_material


func debug_apply_material_style(style: int) -> void:
	_material_picker.select(style)
	_apply_material_style(style)


func debug_all_materials_synced() -> bool:
	for sample: Node2D in _samples:
		if int(sample.call("material_style")) != _selected_material:
			return false
	return true


func debug_material_signatures_unique() -> bool:
	var signatures: Dictionary = {}
	for style in range(SAMPLE_SCRIPT.MATERIAL_STYLE_COUNT):
		_focus_samples[0].call("set_material_style", style)
		var signature: String = str(_focus_samples[0].call("material_signature"))
		if signatures.has(signature):
			_apply_material_style(_selected_material)
			return false
		signatures[signature] = true
	_apply_material_style(_selected_material)
	return signatures.size() == SAMPLE_SCRIPT.MATERIAL_STYLE_COUNT


func debug_focus_geometry_signature() -> String:
	if _focus_samples.is_empty():
		return ""
	return str(_focus_samples[0].call("geometry_signature"))


func debug_total_node_count() -> int:
	return _count_nodes(self)


func _build_material_picker() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.name = "MaterialPickerLayer"
	add_child(ui_layer)

	_material_picker = OptionButton.new()
	_material_picker.name = "MaterialPicker"
	_material_picker.position = Vector2(690.0, 14.0)
	_material_picker.size = Vector2(322.0, 42.0)
	_material_picker.tooltip_text = "切换泪核材质；红白弹体共享几何，仅材质表现不同。"
	_material_picker.add_theme_font_size_override("font_size", 16)
	_material_picker.add_theme_color_override("font_color", COLOR_TEXT)
	_material_picker.add_theme_color_override("font_hover_color", COLOR_ACCENT)
	_material_picker.add_theme_color_override("font_pressed_color", COLOR_ACCENT)
	for index in range(MATERIAL_LABELS.size()):
		_material_picker.add_item(MATERIAL_LABELS[index], index)
	_material_picker.select(DEFAULT_MATERIAL_INDEX)
	_material_picker.item_selected.connect(_on_material_selected)
	ui_layer.add_child(_material_picker)


func _on_material_selected(index: int) -> void:
	_apply_material_style(index)


func _apply_material_style(style: int) -> void:
	_selected_material = clampi(style, 0, SAMPLE_SCRIPT.MATERIAL_STYLE_COUNT - 1)
	for sample: Node2D in _samples:
		sample.call("set_material_style", _selected_material)
	queue_redraw()


func _draw_header() -> void:
	var font: Font = ThemeDB.fallback_font
	draw_string(
		font,
		Vector2(28.0, 38.0),
		"泪核材质切换 / TEAR CORE MATERIAL SWITCHER",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		24,
		COLOR_ACCENT
	)
	draw_string(
		font,
		Vector2(28.0, 70.0),
		"轮廓与圆形判定锁定 · 下拉菜单同步切换红白特写及实战样本",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		15,
		COLOR_TEXT_DIM
	)
	var state_text: String = "命中放大" if _focus_impact_mode else "弹体放大"
	if _paused:
		state_text += " · 已暂停"
	draw_string(
		font,
		Vector2(1042.0, 39.0),
		state_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		16,
		COLOR_ACCENT
	)


func _draw_focus_panel(rect: Rect2, title: String, enemy: bool) -> void:
	var font: Font = ThemeDB.fallback_font
	var team_color: Color = COLOR_ENEMY if enemy else COLOR_PLAYER
	draw_rect(rect, COLOR_PANEL, true)
	draw_rect(rect, COLOR_PANEL_BORDER, false, 1.5)
	draw_string(
		font,
		rect.position + Vector2(18.0, 30.0),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		18,
		team_color
	)
	draw_string(
		font,
		rect.position + Vector2(18.0, 58.0),
		MATERIAL_NAMES[_selected_material],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		15,
		COLOR_ACCENT
	)
	draw_string(
		font,
		rect.position + Vector2(18.0, 82.0),
		MATERIAL_DESCRIPTIONS[_selected_material],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		13,
		COLOR_TEXT_DIM
	)
	var swatch_colors: Array[Color]
	if enemy:
		swatch_colors = [Color("2b080b"), Color("e62935"), Color("ff5a55"), Color("ffd6cf")]
	else:
		swatch_colors = [Color("111722"), Color("dceaf2"), Color("9cb7c5"), Color("ffffff")]
	var swatch_labels := PackedStringArray(["轮廓", "主体", "内部", "高光"])
	for index in range(swatch_colors.size()):
		var swatch_position: Vector2 = rect.position + Vector2(18.0 + float(index) * 132.0, 365.0)
		draw_rect(Rect2(swatch_position, Vector2(28.0, 16.0)), swatch_colors[index], true)
		draw_rect(
			Rect2(swatch_position, Vector2(28.0, 16.0)),
			Color(1.0, 1.0, 1.0, 0.24),
			false,
			1.0
		)
		draw_string(
			font,
			swatch_position + Vector2(36.0, 14.0),
			swatch_labels[index],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			12,
			COLOR_TEXT_DIM
		)


func _draw_footer() -> void:
	var font: Font = ThemeDB.fallback_font
	var background_names := PackedStringArray(["纯暗", "低对比网格", "低饱和意识层"])
	var controls: String = (
		"[下拉] 材质  [Space] 暂停  [R] 重置  [H] 弹体/命中  [D] 判定圆  [T] 拖尾  [B] 背景：%s  [Esc] 返回"
		% background_names[_background_mode]
	)
	draw_string(font, Vector2(28.0, 730.0), controls, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, COLOR_TEXT_DIM)
	draw_string(font, Vector2(1090.0, 730.0), "待人工选型", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, COLOR_ACCENT)


func _count_nodes(node: Node) -> int:
	var total: int = 1
	for child: Node in node.get_children():
		total += _count_nodes(child)
	return total
