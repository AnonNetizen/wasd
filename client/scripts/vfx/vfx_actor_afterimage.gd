# Doc: docs/代码/visual_effects.md
@tool
class_name VfxActorAfterimage
extends "res://scripts/vfx/vfx_instance.gd"
## Detached actor silhouette sampled at play time, then faded independently of actor pooling.


var _visual: Node2D = null
var _body: Polygon2D = null
var _outline: Polygon2D = null


func _ready() -> void:
	super()
	_resolve_nodes()


func configure(request: VfxPlayRequest) -> void:
	super(request)
	_resolve_nodes()
	if request == null or request.owner == null or not is_instance_valid(request.owner):
		return
	var source_visual: Node2D = request.owner.get_node_or_null("Visual") as Node2D
	var source_body: Polygon2D = request.owner.get_node_or_null("Visual/Body") as Polygon2D
	var source_outline: Polygon2D = request.owner.get_node_or_null("Visual/Outline") as Polygon2D
	if source_visual != null and _visual != null:
		_visual.scale = source_visual.scale
		_visual.rotation = source_visual.rotation
	if source_body != null and _body != null:
		_body.polygon = source_body.polygon
		_body.position = source_body.position
		_body.rotation = source_body.rotation
		_body.scale = source_body.scale
		_body.color = source_body.color
	if source_outline != null and _outline != null:
		_outline.polygon = source_outline.polygon
		_outline.position = source_outline.position
		_outline.rotation = source_outline.rotation
		_outline.scale = source_outline.scale
		_outline.color = source_outline.color


func _pool_reset() -> void:
	super()
	_resolve_nodes()
	if _visual != null:
		_visual.scale = Vector2.ONE
		_visual.rotation = 0.0


func _resolve_nodes() -> void:
	if _visual == null:
		_visual = get_node_or_null("Visual") as Node2D
	if _body == null:
		_body = get_node_or_null("Visual/Body") as Polygon2D
	if _outline == null:
		_outline = get_node_or_null("Visual/Outline") as Polygon2D
