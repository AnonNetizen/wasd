# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/决策记录.md ADR #99
class_name Player3DVisual
extends Node2D


const BASE_COLOR: Color = Color(0.34, 0.72, 1.0)
const HURT_COLOR: Color = Color(1.0, 0.34, 0.30)
const MARKER_COLOR: Color = Color(0.95, 0.96, 0.92)
const MARKER_OFFSET_X: float = 0.38
const MODEL_YAW_DEGREES: float = 14.0
const PACK_COLOR: Color = Color(0.11, 0.12, 0.15)
const SHADOW_COLOR: Color = Color(0.03, 0.025, 0.02, 0.34)
const SHADOW_RADIUS_X: float = 13.0
const SHADOW_RADIUS_Y: float = 4.0
const SHADOW_SEGMENTS: int = 20
const SPRITE_OFFSET: Vector2 = Vector2(0.0, -11.0)
const VIEWPORT_SIZE: Vector2i = Vector2i(72, 96)

var _base_material: StandardMaterial3D
var _facing_sign: float = 1.0
var _hit_flash_active: bool = false
var _hurt_material: StandardMaterial3D

@onready var _body: MeshInstance3D = get_node_or_null("VisualViewport/World3DRoot/ModelRoot/Body") as MeshInstance3D
@onready var _camera: Camera3D = get_node_or_null("VisualViewport/World3DRoot/Camera3D") as Camera3D
@onready var _facing_marker: MeshInstance3D = get_node_or_null("VisualViewport/World3DRoot/ModelRoot/FacingMarker") as MeshInstance3D
@onready var _model_root: Node3D = get_node_or_null("VisualViewport/World3DRoot/ModelRoot") as Node3D
@onready var _pack: MeshInstance3D = get_node_or_null("VisualViewport/World3DRoot/ModelRoot/Pack") as MeshInstance3D
@onready var _sprite: Sprite2D = get_node_or_null("VisualSprite") as Sprite2D
@onready var _viewport: SubViewport = get_node_or_null("VisualViewport") as SubViewport


func _ready() -> void:
	_configure_viewport()
	_configure_materials()
	_apply_visual_state()
	queue_redraw()


func set_facing_sign(facing_sign: float) -> void:
	var next_sign: float = 1.0 if facing_sign >= 0.0 else -1.0
	if is_equal_approx(_facing_sign, next_sign):
		return
	_facing_sign = next_sign
	_apply_visual_state()


func set_hit_flash_active(active: bool) -> void:
	if _hit_flash_active == active:
		return
	_hit_flash_active = active
	_apply_visual_state()


func _draw() -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in range(SHADOW_SEGMENTS):
		var angle: float = TAU * float(index) / float(SHADOW_SEGMENTS)
		points.append(Vector2(cos(angle) * SHADOW_RADIUS_X, sin(angle) * SHADOW_RADIUS_Y))
	draw_colored_polygon(points, SHADOW_COLOR)


func _configure_viewport() -> void:
	if _viewport == null or _sprite == null or _camera == null:
		push_error("[Player3DVisual] missing viewport, sprite, or camera node")
		return
	_viewport.size = VIEWPORT_SIZE
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sprite.centered = true
	_sprite.position = SPRITE_OFFSET
	_sprite.texture = _viewport.get_texture()
	_camera.current = true
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 2.2


func _configure_materials() -> void:
	_base_material = _make_material(BASE_COLOR)
	_hurt_material = _make_material(HURT_COLOR)
	if _facing_marker != null:
		_facing_marker.material_override = _make_material(MARKER_COLOR)
	if _pack != null:
		_pack.material_override = _make_material(PACK_COLOR)


func _apply_visual_state() -> void:
	if _model_root != null:
		_model_root.rotation_degrees.y = -MODEL_YAW_DEGREES * _facing_sign
	if _facing_marker != null:
		_facing_marker.position.x = MARKER_OFFSET_X * _facing_sign
	if _body != null:
		_body.material_override = _hurt_material if _hit_flash_active else _base_material


func _make_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.86
	return material
