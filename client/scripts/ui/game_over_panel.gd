# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md
class_name GameOverPanel
extends CanvasLayer


signal quit_to_title_requested()
signal restart_requested()

const BUTTON_ACTION_QUIT_TO_TITLE: String = "quit_to_title"
const BUTTON_ACTION_RESTART: String = "restart"

var _button_actions: Array[String] = []
var _buttons: Array[Button] = []
var _pressed_button_index: int = -1
var _selection_locked: bool = false
var _settlement_label: Label = null
var _profile_label: Label = null
var _summary_label: Label = null


func _input(event: InputEvent) -> void:
	if UIManager.top() != self:
		return

	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button == null or mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return

	var button_index: int = _button_index_at_position(mouse_button.position)
	if mouse_button.pressed:
		_pressed_button_index = button_index
		if button_index >= 0:
			get_viewport().set_input_as_handled()
		return

	var pressed_button_index: int = _pressed_button_index
	_pressed_button_index = -1
	if button_index < 0 or button_index != pressed_button_index:
		return
	get_viewport().set_input_as_handled()
	_activate_button(button_index)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var title: Label = get_node_or_null("Root/Center/Panel/Margin/Layout/TitleLabel") as Label
	var restart_button: Button = get_node_or_null("Root/Center/Panel/Margin/Layout/RestartButton") as Button
	var quit_button: Button = get_node_or_null("Root/Center/Panel/Margin/Layout/QuitToTitleButton") as Button
	_summary_label = get_node_or_null("Root/Center/Panel/Margin/Layout/SummaryLabel") as Label
	_settlement_label = get_node_or_null("Root/Center/Panel/Margin/Layout/SettlementLabel") as Label
	_profile_label = get_node_or_null("Root/Center/Panel/Margin/Layout/MetaProfileLabel") as Label
	if title == null or restart_button == null or quit_button == null:
		push_error("[GameOverPanel] missing required scene nodes")
		return
	if _summary_label == null or _settlement_label == null or _profile_label == null:
		push_error("[GameOverPanel] missing required scene nodes")
		return

	title.text = tr("ui_game_over")
	restart_button.text = tr("ui_restart")
	restart_button.pressed.connect(_on_restart_pressed)
	_register_button(restart_button, BUTTON_ACTION_RESTART)

	quit_button.text = tr("ui_quit_to_title")
	quit_button.pressed.connect(_on_quit_to_title_pressed)
	_register_button(quit_button, BUTTON_ACTION_QUIT_TO_TITLE)
	restart_button.call_deferred("grab_focus")


func configure(kills: int, run_time: float, settlement: Dictionary = {}) -> void:
	if _summary_label == null:
		return
	_summary_label.text = tr("ui_run_summary").format({
		"kills": kills,
		"time": int(run_time),
	})
	_configure_settlement(settlement)


func _register_button(button: Button, action: String) -> void:
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	_buttons.append(button)
	_button_actions.append(action)


func _configure_settlement(settlement: Dictionary) -> void:
	if _settlement_label == null or _profile_label == null:
		return
	if settlement.is_empty():
		_settlement_label.visible = false
		_profile_label.visible = false
		return
	_settlement_label.visible = true
	_profile_label.visible = true

	var currency_name: String = tr(String(settlement.get("currency_name_key", "")))
	_settlement_label.text = tr("ui_meta_settlement").format({
		"currency": currency_name,
		"amount": int(settlement.get("currency_amount", 0)),
		"xp": int(settlement.get("account_xp", 0)),
	})

	var profile: Dictionary = settlement.get("profile", {}) as Dictionary
	var currencies: Dictionary = profile.get("currencies", {}) as Dictionary
	var currency_id: String = String(settlement.get("currency_id", ""))
	var balance_text: String = tr("ui_meta_balance").format({
		"currency": currency_name,
		"amount": int(currencies.get(currency_id, 0)),
	})
	var level_text: String = tr("ui_meta_account_level").format({
		"level": int(profile.get("account_level", 1)),
	})
	_profile_label.text = "%s · %s" % [level_text, balance_text]


func _on_restart_pressed() -> void:
	_activate_button(_button_actions.find(BUTTON_ACTION_RESTART))


func _on_quit_to_title_pressed() -> void:
	_activate_button(_button_actions.find(BUTTON_ACTION_QUIT_TO_TITLE))


func _button_index_at_position(position: Vector2) -> int:
	for index: int in range(_buttons.size()):
		var button: Button = _buttons[index]
		if not is_instance_valid(button) or not button.visible or button.disabled:
			continue
		if button.get_global_rect().has_point(position):
			return index
	return -1


func _activate_button(index: int) -> void:
	if _selection_locked:
		return
	if index < 0 or index >= _buttons.size():
		return
	var action: String = _button_actions[index]
	_selection_locked = true
	if action == BUTTON_ACTION_RESTART:
		restart_requested.emit()
	elif action == BUTTON_ACTION_QUIT_TO_TITLE:
		quit_to_title_requested.emit()
