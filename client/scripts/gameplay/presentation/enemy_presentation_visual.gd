# Doc: docs/代码/visual_effects.md
# Authority: docs/游戏设计文档.md §9, docs/决策记录.md ADR #185
class_name EnemyPresentationVisual
extends Node2D


@export var body_path: NodePath = ^"Body"

var _body: Polygon2D = null
var _missing_body_reported: bool = false


func _ready() -> void:
	_resolve_body()


func set_presentation_state(
	tint: Color,
	alpha: float,
	visual_scale: Vector2
) -> void:
	_resolve_body()
	if _body == null:
		return
	_body.color = Color(tint.r, tint.g, tint.b, 1.0)
	modulate = Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0))
	scale = visual_scale


func _resolve_body() -> void:
	if _body != null:
		return
	_body = get_node_or_null(body_path) as Polygon2D
	if _body == null and not _missing_body_reported:
		_missing_body_reported = true
		push_error("[EnemyPresentationVisual] missing scene-authored Body")
