# Doc: docs/代码/ui_effects.md
class_name UIButtonFeedback
extends UIEffectPlayer


const HOVER_TINT: Color = Color(1.08, 1.08, 1.08, 1.0)
const PRESSED_TINT: Color = Color(0.84, 0.88, 0.94, 1.0)
const FEEDBACK_DURATION: float = 0.08
const BOUND_META: StringName = &"ui_button_feedback_bound"

var _button_tweens: Dictionary = {}
var _root: Node = null


func bind(root: Node) -> void:
	if _root != null and is_instance_valid(_root):
		var previous_callable: Callable = Callable(self, "_on_descendant_added")
		if _root.child_entered_tree.is_connected(previous_callable):
			_root.child_entered_tree.disconnect(previous_callable)
	_root = root
	_bind_descendants(root)
	if _root != null and not _root.child_entered_tree.is_connected(_on_descendant_added):
		_root.child_entered_tree.connect(_on_descendant_added)


func refresh_bindings() -> void:
	if _root != null and is_instance_valid(_root):
		_bind_descendants(_root)


func _bind_descendants(node: Node) -> void:
	if node is BaseButton:
		_bind_button(node as BaseButton)
	for child: Node in node.get_children():
		_bind_descendants(child)


func _bind_button(button: BaseButton) -> void:
	if button.has_meta(BOUND_META):
		return
	button.set_meta(BOUND_META, true)
	button.mouse_entered.connect(_on_button_highlighted.bind(button))
	button.mouse_exited.connect(_on_button_released.bind(button))
	button.focus_entered.connect(_on_button_highlighted.bind(button))
	button.focus_exited.connect(_on_button_released.bind(button))
	button.button_down.connect(_on_button_pressed.bind(button))
	button.button_up.connect(_on_button_highlighted.bind(button))


func _on_button_highlighted(button: BaseButton) -> void:
	_tint_button(button, HOVER_TINT)


func _on_button_pressed(button: BaseButton) -> void:
	_tint_button(button, PRESSED_TINT)


func _on_button_released(button: BaseButton) -> void:
	_tint_button(button, Color.WHITE)


func _tint_button(button: BaseButton, tint: Color) -> void:
	if button == null or not is_instance_valid(button):
		return
	var instance_id: int = button.get_instance_id()
	var previous: Tween = _button_tweens.get(instance_id) as Tween
	if previous != null and previous.is_valid():
		previous.kill()
	var duration: float = adjusted_duration(FEEDBACK_DURATION)
	if duration <= 0.0:
		button.self_modulate = tint
		return
	var tween: Tween = create_effect_tween()
	_button_tweens[instance_id] = tween
	tween.tween_property(
		button,
		"self_modulate",
		tint,
		duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.finished.connect(_on_button_tween_finished.bind(instance_id), CONNECT_ONE_SHOT)


func _on_button_tween_finished(instance_id: int) -> void:
	_button_tweens.erase(instance_id)


func _on_descendant_added(_node: Node) -> void:
	call_deferred("refresh_bindings")
