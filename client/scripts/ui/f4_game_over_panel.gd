# Doc: docs/代码/f4_min_playable_loop.md
# Authority: docs/AI协作/工作包/F4-MinPlayableLoop.md
class_name F4GameOverPanel
extends CanvasLayer


signal quit_to_title_requested()
signal meta_progression_requested()
signal purchase_upgrade_requested(upgrade_id: String)
signal restart_requested()

const BUTTON_HEIGHT: float = 52.0
const BUTTON_WIDTH: float = 260.0
const BUTTON_ACTION_PURCHASE: String = "purchase"
const BUTTON_ACTION_QUIT_TO_TITLE: String = "quit_to_title"
const BUTTON_ACTION_RESTART: String = "restart"
const BUTTON_ACTION_META_PROGRESSION: String = "meta_progression"
const PANEL_WIDTH: float = 520.0

var _button_actions: Array[String] = []
var _buttons: Array[Button] = []
var _feedback_label: Label = null
var _pressed_button_index: int = -1
var _purchase_button: Button = null
var _purchase_upgrade_id: String = ""
var _purchase_name_key: String = ""
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

	var root: Control = Control.new()
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var backdrop: ColorRect = ColorRect.new()
	backdrop.process_mode = Node.PROCESS_MODE_ALWAYS
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.color = Color(0.0, 0.0, 0.0, 0.42)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.process_mode = Node.PROCESS_MODE_ALWAYS
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	center.add_child(panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.process_mode = Node.PROCESS_MODE_ALWAYS
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var layout: VBoxContainer = VBoxContainer.new()
	layout.process_mode = Node.PROCESS_MODE_ALWAYS
	layout.mouse_filter = Control.MOUSE_FILTER_PASS
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)

	var title: Label = Label.new()
	title.process_mode = Node.PROCESS_MODE_ALWAYS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = tr("ui_game_over")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	layout.add_child(title)

	_summary_label = Label.new()
	_summary_label.process_mode = Node.PROCESS_MODE_ALWAYS
	_summary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_label.add_theme_font_size_override("font_size", 20)
	layout.add_child(_summary_label)

	_settlement_label = Label.new()
	_settlement_label.name = "SettlementLabel"
	_settlement_label.process_mode = Node.PROCESS_MODE_ALWAYS
	_settlement_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settlement_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settlement_label.add_theme_font_size_override("font_size", 18)
	layout.add_child(_settlement_label)

	_profile_label = Label.new()
	_profile_label.name = "MetaProfileLabel"
	_profile_label.process_mode = Node.PROCESS_MODE_ALWAYS
	_profile_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_profile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_profile_label.add_theme_font_size_override("font_size", 16)
	layout.add_child(_profile_label)

	_feedback_label = Label.new()
	_feedback_label.name = "MetaPurchaseFeedbackLabel"
	_feedback_label.process_mode = Node.PROCESS_MODE_ALWAYS
	_feedback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback_label.add_theme_font_size_override("font_size", 16)
	_feedback_label.visible = false
	layout.add_child(_feedback_label)

	_purchase_button = _make_button("PurchaseUpgradeButton", tr("ui_meta_purchase_unavailable"))
	_purchase_button.pressed.connect(_on_purchase_pressed)
	_register_button(_purchase_button, BUTTON_ACTION_PURCHASE)
	layout.add_child(_purchase_button)

	var meta_progression_button: Button = _make_button("MetaProgressionButton", tr("ui_meta_open_upgrades"))
	meta_progression_button.pressed.connect(_on_meta_progression_pressed)
	_register_button(meta_progression_button, BUTTON_ACTION_META_PROGRESSION)
	layout.add_child(meta_progression_button)

	var restart_button: Button = _make_button("RestartButton", tr("ui_restart"))
	restart_button.pressed.connect(_on_restart_pressed)
	_register_button(restart_button, BUTTON_ACTION_RESTART)
	layout.add_child(restart_button)

	var quit_button: Button = _make_button("QuitToTitleButton", tr("ui_quit_to_title"))
	quit_button.pressed.connect(_on_quit_to_title_pressed)
	_register_button(quit_button, BUTTON_ACTION_QUIT_TO_TITLE)
	layout.add_child(quit_button)
	restart_button.call_deferred("grab_focus")


func configure(kills: int, run_time: float, settlement: Dictionary = {}, purchase: Dictionary = {}) -> void:
	if _summary_label == null:
		return
	_summary_label.text = tr("ui_run_summary").format({
		"kills": kills,
		"time": int(run_time),
	})
	_configure_settlement(settlement)
	_configure_purchase(purchase)


func _make_button(button_name: String, text_value: String) -> Button:
	var button: Button = Button.new()
	button.name = button_name
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.text = text_value
	button.custom_minimum_size = Vector2(BUTTON_WIDTH, BUTTON_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return button


func _register_button(button: Button, action: String) -> void:
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


func _configure_purchase(purchase: Dictionary) -> void:
	if _purchase_button == null:
		return
	if purchase.is_empty():
		_purchase_upgrade_id = ""
		_purchase_name_key = ""
		_purchase_button.text = tr("ui_meta_purchase_unavailable")
		_purchase_button.disabled = true
		return
	_purchase_upgrade_id = String(purchase.get("upgrade_id", ""))
	_purchase_name_key = String(purchase.get("name_key", ""))
	_purchase_button.text = tr("ui_meta_purchase_upgrade").format({
		"name": tr(_purchase_name_key),
		"cost": int(purchase.get("cost", 0)),
	})
	_purchase_button.disabled = _purchase_upgrade_id.is_empty()


func show_purchase_feedback(purchase_result: Dictionary) -> void:
	if _feedback_label == null:
		return
	_feedback_label.visible = true
	var name_key: String = String(purchase_result.get("name_key", _purchase_name_key))
	if bool(purchase_result.get("ok", false)):
		_feedback_label.text = tr("ui_meta_purchase_success").format({
			"name": tr(name_key),
			"level": int(purchase_result.get("level", 0)),
		})
		return
	_feedback_label.text = tr("ui_meta_purchase_failed").format({
		"reason": _purchase_failure_text(purchase_result),
	})


func _purchase_failure_text(purchase_result: Dictionary) -> String:
	var reason: String = String(purchase_result.get("reason", ""))
	if reason == "max_level":
		return tr("ui_meta_upgrade_maxed")
	if reason == "insufficient_currency":
		return tr("ui_meta_upgrade_insufficient")
	return tr("ui_meta_purchase_unavailable")


func _on_purchase_pressed() -> void:
	if _purchase_upgrade_id.is_empty():
		return
	_activate_button(_button_actions.find(BUTTON_ACTION_PURCHASE))


func _on_meta_progression_pressed() -> void:
	_activate_button(_button_actions.find(BUTTON_ACTION_META_PROGRESSION))


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
	if action == BUTTON_ACTION_PURCHASE:
		purchase_upgrade_requested.emit(_purchase_upgrade_id)
		return
	if action == BUTTON_ACTION_META_PROGRESSION:
		meta_progression_requested.emit()
		return
	_selection_locked = true
	if action == BUTTON_ACTION_RESTART:
		restart_requested.emit()
	elif action == BUTTON_ACTION_QUIT_TO_TITLE:
		quit_to_title_requested.emit()
