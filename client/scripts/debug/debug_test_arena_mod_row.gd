# Doc: docs/代码/debug_test_arena.md
# Authority: docs/决策记录.md ADR #159
class_name DebugTestArenaModRow
extends HBoxContainer


signal selection_changed()

var _definition: Dictionary = {}
var _enabled_check: CheckButton = null
var _name_label: Label = null


func _ready() -> void:
	_enabled_check = get_node_or_null("EnabledCheck") as CheckButton
	_name_label = get_node_or_null("NameLabel") as Label
	if _enabled_check == null or _name_label == null:
		push_error("[DebugTestArenaModRow] missing required scene nodes")
		return
	_enabled_check.toggled.connect(_on_enabled_toggled)


func configure(definition: Dictionary, selected: bool = false) -> void:
	_definition = definition.duplicate(true)
	if _name_label == null:
		return
	_name_label.text = tr(String(_definition.get("name_key", "")))
	_enabled_check.set_pressed_no_signal(selected)


func refresh_texts() -> void:
	if _name_label == null:
		return
	_name_label.text = tr(String(_definition.get("name_key", "")))


func selection() -> Dictionary:
	if _enabled_check == null or not _enabled_check.button_pressed:
		return {}
	return {
		"mod_id": String(_definition.get("id", "")),
	}


func _on_enabled_toggled(_enabled: bool) -> void:
	selection_changed.emit()
