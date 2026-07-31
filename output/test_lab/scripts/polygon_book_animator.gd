class_name PolygonBookAnimator
extends RefCounted

const ADAPTER_ID: String = "book_page_turn"
const BOOK_SHADER := preload(
	"res://shaders/polygon_book_page_turn.gdshader"
)

var _asset: PolygonAsset2D
var _page_turn_progress: float = 0.0


func bind(asset: PolygonAsset2D) -> Error:
	if asset == null:
		return ERR_INVALID_PARAMETER
	var asset_data := asset.get_asset_data()
	var custom_animation_value: Variant = asset_data.get(
		"custom_animation",
		{}
	)
	if not custom_animation_value is Dictionary:
		return ERR_INVALID_DATA
	var custom_animation: Dictionary = custom_animation_value
	if String(custom_animation.get("adapter", "")) != ADAPTER_ID:
		return ERR_UNAVAILABLE
	var palette_value: Variant = asset_data.get("palette", {})
	if not palette_value is Dictionary:
		return ERR_INVALID_DATA
	var palette: Dictionary = palette_value
	var light_role := String(custom_animation.get(
		"light_palette_role",
		""
	))
	var shadow_role := String(custom_animation.get(
		"shadow_palette_role",
		""
	))
	if (
		light_role.is_empty()
		or shadow_role.is_empty()
		or not palette.has(light_role)
		or not palette.has(shadow_role)
	):
		return ERR_INVALID_DATA
	_asset = asset
	_asset.set_effect_shader(BOOK_SHADER)
	_asset.set_effect_parameter(
		"page_fold_light",
		Color(String(palette[light_role]))
	)
	_asset.set_effect_parameter(
		"page_fold_shadow",
		Color(String(palette[shadow_role]))
	)
	set_page_turn_progress(0.0)
	return OK


func set_page_turn_progress(progress: float) -> void:
	_page_turn_progress = clampf(progress, 0.0, 1.0)
	if _asset != null:
		_asset.set_effect_parameter(
			"page_turn_progress",
			_page_turn_progress
		)


func reset() -> void:
	set_page_turn_progress(0.0)


func get_page_turn_progress() -> float:
	return _page_turn_progress
