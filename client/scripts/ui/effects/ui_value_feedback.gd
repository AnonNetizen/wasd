# Doc: docs/代码/ui_effects.md
class_name UIValueFeedback
extends UIEffectPlayer


func play_value(target: CanvasItem, positive: bool = true) -> void:
	var tint: Color = (
		Color(1.12, 1.08, 0.76, 1.0)
		if positive
		else Color(1.14, 0.76, 0.72, 1.0)
	)
	pulse(target, tint, 0.18)
