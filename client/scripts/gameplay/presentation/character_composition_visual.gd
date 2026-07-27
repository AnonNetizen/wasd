# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/游戏设计文档.md
class_name CharacterCompositionVisual
extends Node2D


var _accent_color: Color = Color.WHITE
var _body: Polygon2D = null
var _eye: Polygon2D = null
var _facing_arrow: Polygon2D = null
var _facing_line: Line2D = null
var _outline: Polygon2D = null
var _primary_color: Color = Color.WHITE


func _ready() -> void:
	_body = get_node_or_null("Body") as Polygon2D
	_outline = get_node_or_null("Outline") as Polygon2D
	_facing_line = get_node_or_null("Direction/FacingLine") as Line2D
	_facing_arrow = get_node_or_null("Direction/FacingArrow") as Polygon2D
	_eye = get_node_or_null("Direction/Eye") as Polygon2D
	if (
		_body == null
		or _outline == null
		or _facing_line == null
		or _facing_arrow == null
		or _eye == null
	):
		push_error("[CharacterCompositionVisual] missing inherited player visual nodes")
		return
	_primary_color = _body.color
	_accent_color = _facing_arrow.color
	_apply_palette()


func configure_palette(palette: Dictionary) -> void:
	var primary_value: Variant = palette.get("primary", _primary_color)
	var accent_value: Variant = palette.get("accent", _accent_color)
	set_composition_palette(
		_color_from_variant(primary_value, _primary_color),
		_color_from_variant(accent_value, _accent_color)
	)


func set_composition_palette(primary_color: Color, accent_color: Color) -> void:
	_primary_color = primary_color
	_accent_color = accent_color
	_apply_palette()


func primary_color() -> Color:
	return _primary_color


func accent_color() -> Color:
	return _accent_color


func _apply_palette() -> void:
	if _body == null:
		return
	_body.color = _primary_color
	_outline.color = _primary_color.darkened(0.78)
	_facing_line.default_color = _accent_color
	_facing_arrow.color = _accent_color
	_eye.color = _accent_color.lightened(0.18)


func _color_from_variant(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value as Color
	if value is String:
		var encoded: String = String(value)
		if Color.html_is_valid(encoded):
			return Color.from_string(encoded, fallback)
	return fallback
