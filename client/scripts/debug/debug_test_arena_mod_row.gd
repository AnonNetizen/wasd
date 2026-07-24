# Doc: docs/代码/debug_test_arena.md
# Authority: docs/决策记录.md ADR #159
class_name DebugTestArenaModRow
extends HBoxContainer


signal selection_changed()

var _definition: Dictionary = {}
var _enabled_check: CheckButton = null
var _name_label: Label = null
var _rank_spin: SpinBox = null


func _ready() -> void:
	_enabled_check = get_node_or_null("EnabledCheck") as CheckButton
	_name_label = get_node_or_null("NameLabel") as Label
	_rank_spin = get_node_or_null("RankSpin") as SpinBox
	if _enabled_check == null or _name_label == null or _rank_spin == null:
		push_error("[DebugTestArenaModRow] missing required scene nodes")
		return
	_enabled_check.toggled.connect(_on_enabled_toggled)
	_rank_spin.value_changed.connect(_on_rank_changed)


func configure(definition: Dictionary, selected_rank: int = -1) -> void:
	_definition = definition.duplicate(true)
	if _name_label == null:
		return
	_name_label.text = tr(String(_definition.get("name_key", "")))
	var max_rank: int = maxi(int(_definition.get("max_rank", 0)), 0)
	_rank_spin.min_value = 0.0
	_rank_spin.max_value = float(max_rank)
	_rank_spin.value = float(clampi(selected_rank, 0, max_rank))
	_enabled_check.button_pressed = selected_rank >= 0
	_rank_spin.editable = _enabled_check.button_pressed
	_rank_spin.tooltip_text = tr("ui_debug_test_arena_rank")


func refresh_texts() -> void:
	if _name_label == null:
		return
	_name_label.text = tr(String(_definition.get("name_key", "")))
	_rank_spin.tooltip_text = tr("ui_debug_test_arena_rank")


func selection() -> Dictionary:
	if _enabled_check == null or not _enabled_check.button_pressed:
		return {}
	return {
		"mod_id": String(_definition.get("id", "")),
		"rank": int(_rank_spin.value),
	}


func _on_enabled_toggled(enabled: bool) -> void:
	_rank_spin.editable = enabled
	selection_changed.emit()


func _on_rank_changed(_value: float) -> void:
	selection_changed.emit()
