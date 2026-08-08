# Doc: docs/代码/debug_test_arena.md
# Authority: docs/决策记录.md ADR #159
class_name DebugTestArenaModRow
extends HBoxContainer


signal selection_changed()

var _definition: Dictionary = {}
var _enabled_check: CheckButton = null
var _name_label: Label = null
var _x_spin: SpinBox = null
var _y_spin: SpinBox = null


func _ready() -> void:
	_enabled_check = get_node_or_null("EnabledCheck") as CheckButton
	_name_label = get_node_or_null("NameLabel") as Label
	_x_spin = get_node_or_null("XSpin") as SpinBox
	_y_spin = get_node_or_null("YSpin") as SpinBox
	if (
		_enabled_check == null
		or _name_label == null
		or _x_spin == null
		or _y_spin == null
	):
		push_error("[DebugTestArenaModRow] missing required scene nodes")
		return
	_enabled_check.toggled.connect(_on_enabled_toggled)
	_x_spin.value_changed.connect(_on_coord_changed)
	_y_spin.value_changed.connect(_on_coord_changed)


func configure(definition: Dictionary, selection: Dictionary = {}) -> void:
	_definition = definition.duplicate(true)
	if _name_label == null:
		return
	_name_label.text = tr(String(_definition.get("name_key", "")))
	_enabled_check.set_pressed_no_signal(bool(selection.get("enabled", false)))
	_x_spin.set_value_no_signal(float(int(selection.get("x", 3))))
	_y_spin.set_value_no_signal(float(int(selection.get("y", 3))))
	_refresh_coord_controls()


func refresh_texts() -> void:
	if _name_label == null:
		return
	_name_label.text = tr(String(_definition.get("name_key", "")))


func selection() -> Dictionary:
	if _enabled_check == null or not _enabled_check.button_pressed:
		return {}
	return {
		"mod_id": String(_definition.get("id", "")),
		"x": int(_x_spin.value),
		"y": int(_y_spin.value),
	}



func _on_enabled_toggled(_enabled: bool) -> void:
	_refresh_coord_controls()
	selection_changed.emit()


func _on_coord_changed(_value: float) -> void:
	selection_changed.emit()


func _refresh_coord_controls() -> void:
	if _enabled_check == null or _x_spin == null or _y_spin == null:
		return
	_x_spin.editable = _enabled_check.button_pressed
	_y_spin.editable = _enabled_check.button_pressed
