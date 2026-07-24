# Doc: docs/代码/visual_effects.md
@tool
class_name VfxTargetAnimationPreset
extends Resource
## Reusable target animation values interpreted by ActorPresentationController/UIEffectPlayer.


@export var animation_name: StringName = &"flash"
@export var target_path: NodePath = NodePath("Visual/Body")
@export_range(0.0, 4.0, 0.01, "or_greater") var duration: float = 0.16
@export var tint: Color = Color.WHITE
@export var start_scale: Vector2 = Vector2.ONE
@export var end_scale: Vector2 = Vector2.ONE
@export_range(0.0, 1.0, 0.01) var end_alpha: float = 1.0
@export var restore_target_state: bool = true
