# Doc: docs/代码/ui_effects.md
class_name UISelectionFeedback
extends UIEffectPlayer


func play_selection(target: CanvasItem) -> void:
	pulse(target, Color(1.14, 1.06, 0.76, 1.0), 0.18)
