# Doc: docs/代码/meta_progression_system.md
# Authority: docs/AI协作/工作包/F6-MetaProgression.md
class_name MetaProgressionPanel
extends CanvasLayer


signal closed_requested()

const BUTTON_HEIGHT: float = 46.0
const BUTTON_WIDTH: float = 180.0
const PANEL_HEIGHT: float = 720.0
const PANEL_WIDTH: float = 680.0
const ROW_MIN_HEIGHT: float = 112.0
const POINTER_ACTION_CLOSE: String = "close"
const POINTER_ACTION_PURCHASE: String = "purchase"

var _account_label: Label = null
var _close_button: Button = null
var _currency_label: Label = null
var _feedback_label: Label = null
var _pressed_pointer_action: String = ""
var _pressed_purchase_index: int = -1
var _purchase_buttons: Array[Button] = []
var _upgrade_ids: Array[String] = []
var _upgrade_name_keys: Array[String] = []
var _upgrade_list: VBoxContainer = null


func _input(event: InputEvent) -> void:
	if UIManager.top() != self:
		return

	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button == null or mouse_button.button_index != MOUSE_BUTTON_LEFT:
		return

	var pointer_hit: Dictionary = _pointer_hit_at_position(mouse_button.position)
	if mouse_button.pressed:
		_pressed_pointer_action = String(pointer_hit.get("action", ""))
		_pressed_purchase_index = int(pointer_hit.get("index", -1))
		if not _pressed_pointer_action.is_empty():
			get_viewport().set_input_as_handled()
		return

	var pressed_action: String = _pressed_pointer_action
	var pressed_index: int = _pressed_purchase_index
	_pressed_pointer_action = ""
	_pressed_purchase_index = -1
	if pressed_action.is_empty() or pressed_action != String(pointer_hit.get("action", "")):
		return
	if pressed_action == POINTER_ACTION_PURCHASE and pressed_index != int(pointer_hit.get("index", -1)):
		return
	get_viewport().set_input_as_handled()
	_activate_pointer_action(pressed_action, pressed_index)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var root: Control = Control.new()
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var backdrop: ColorRect = ColorRect.new()
	backdrop.process_mode = Node.PROCESS_MODE_ALWAYS
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.color = Color(0.0, 0.0, 0.0, 0.48)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.process_mode = Node.PROCESS_MODE_ALWAYS
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "MetaProgressionPanelContainer"
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
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
	title.text = tr("ui_meta_progression_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	layout.add_child(title)

	var profile_row: HBoxContainer = HBoxContainer.new()
	profile_row.process_mode = Node.PROCESS_MODE_ALWAYS
	profile_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	profile_row.add_theme_constant_override("separation", 16)
	layout.add_child(profile_row)

	_account_label = _make_profile_label("MetaAccountLabel")
	profile_row.add_child(_account_label)

	_currency_label = _make_profile_label("MetaCurrencyLabel")
	profile_row.add_child(_currency_label)

	_feedback_label = Label.new()
	_feedback_label.name = "MetaPurchaseFeedbackLabel"
	_feedback_label.process_mode = Node.PROCESS_MODE_ALWAYS
	_feedback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback_label.add_theme_font_size_override("font_size", 16)
	_feedback_label.visible = false
	layout.add_child(_feedback_label)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "MetaUpgradeScroll"
	scroll.process_mode = Node.PROCESS_MODE_ALWAYS
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)

	_upgrade_list = VBoxContainer.new()
	_upgrade_list.name = "MetaUpgradeList"
	_upgrade_list.process_mode = Node.PROCESS_MODE_ALWAYS
	_upgrade_list.mouse_filter = Control.MOUSE_FILTER_PASS
	_upgrade_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upgrade_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_upgrade_list)

	_close_button = _make_button("CloseButton", tr("ui_cancel"))
	_close_button.pressed.connect(_on_close_pressed)
	layout.add_child(_close_button)

	refresh()


func refresh() -> void:
	_refresh_profile()
	_refresh_upgrades()


func _refresh_profile() -> void:
	var profile: Dictionary = MetaProgressionSystem.profile_summary()
	var currency_name: String = tr(String(profile.get("currency_name_key", "")))
	if _account_label != null:
		_account_label.text = tr("ui_meta_account_level").format({
			"level": int(profile.get("account_level", 1)),
		})
	if _currency_label != null:
		_currency_label.text = tr("ui_meta_balance").format({
			"currency": currency_name,
			"amount": int(profile.get("currency_amount", 0)),
		})


func _refresh_upgrades() -> void:
	if _upgrade_list == null:
		return
	for child: Node in _upgrade_list.get_children():
		_upgrade_list.remove_child(child)
		child.queue_free()
	_purchase_buttons.clear()
	_upgrade_ids.clear()
	_upgrade_name_keys.clear()

	for summary: Dictionary in MetaProgressionSystem.upgrade_summaries():
		_upgrade_list.add_child(_make_upgrade_row(summary))


func _make_profile_label(label_name: String) -> Label:
	var label: Label = Label.new()
	label.name = label_name
	label.process_mode = Node.PROCESS_MODE_ALWAYS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	return label


func _make_upgrade_row(summary: Dictionary) -> Control:
	var row: PanelContainer = PanelContainer.new()
	row.name = "MetaUpgradeRow_%s" % String(summary.get("upgrade_id", ""))
	row.process_mode = Node.PROCESS_MODE_ALWAYS
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.custom_minimum_size = Vector2(0.0, ROW_MIN_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin: MarginContainer = MarginContainer.new()
	margin.process_mode = Node.PROCESS_MODE_ALWAYS
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	row.add_child(margin)

	var row_layout: HBoxContainer = HBoxContainer.new()
	row_layout.process_mode = Node.PROCESS_MODE_ALWAYS
	row_layout.mouse_filter = Control.MOUSE_FILTER_PASS
	row_layout.add_theme_constant_override("separation", 14)
	margin.add_child(row_layout)

	var text_layout: VBoxContainer = VBoxContainer.new()
	text_layout.process_mode = Node.PROCESS_MODE_ALWAYS
	text_layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_layout.add_theme_constant_override("separation", 4)
	row_layout.add_child(text_layout)

	var name_label: Label = Label.new()
	name_label.process_mode = Node.PROCESS_MODE_ALWAYS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = tr(String(summary.get("name_key", "")))
	name_label.add_theme_font_size_override("font_size", 20)
	text_layout.add_child(name_label)

	var desc_label: Label = Label.new()
	desc_label.process_mode = Node.PROCESS_MODE_ALWAYS
	desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_label.text = tr(String(summary.get("desc_key", "")))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_font_size_override("font_size", 15)
	text_layout.add_child(desc_label)

	var level_label: Label = Label.new()
	level_label.process_mode = Node.PROCESS_MODE_ALWAYS
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_label.text = tr("ui_meta_upgrade_level").format({
		"level": int(summary.get("current_level", 0)),
		"max": int(summary.get("max_level", 0)),
	})
	level_label.add_theme_font_size_override("font_size", 14)
	text_layout.add_child(level_label)

	var purchase_button: Button = _make_button(
		"Purchase_%s" % String(summary.get("upgrade_id", "")),
		_purchase_text(summary)
	)
	purchase_button.disabled = not bool(summary.get("can_purchase", false))
	var button_index: int = _purchase_buttons.size()
	purchase_button.pressed.connect(func() -> void:
		_on_purchase_pressed(button_index)
	)
	_purchase_buttons.append(purchase_button)
	_upgrade_ids.append(String(summary.get("upgrade_id", "")))
	_upgrade_name_keys.append(String(summary.get("name_key", "")))
	row_layout.add_child(purchase_button)
	return row


func _purchase_text(summary: Dictionary) -> String:
	var reason: String = String(summary.get("reason", ""))
	if reason == "max_level":
		return tr("ui_meta_upgrade_maxed")
	if reason == "locked":
		return tr("ui_meta_upgrade_locked").format({
			"level": int(summary.get("account_level_required", 1)),
		})
	if reason == "insufficient_currency":
		return tr("ui_meta_upgrade_insufficient")
	if reason == "missing_cost":
		return tr("ui_meta_purchase_unavailable")
	var currency_name: String = tr(String(summary.get("currency_name_key", "")))
	return tr("ui_meta_upgrade_cost").format({
		"currency": currency_name,
		"cost": int(summary.get("cost", 0)),
	})


func _make_button(button_name: String, text_value: String) -> Button:
	var button: Button = Button.new()
	button.name = button_name
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.text = text_value
	button.custom_minimum_size = Vector2(BUTTON_WIDTH, BUTTON_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return button


func _on_purchase_pressed(button_index: int) -> void:
	if button_index < 0 or button_index >= _upgrade_ids.size():
		return
	var upgrade_id: String = _upgrade_ids[button_index]
	if upgrade_id.is_empty():
		return
	var name_key: String = _upgrade_name_keys[button_index] if button_index < _upgrade_name_keys.size() else ""
	var purchase_result: Dictionary = MetaProgressionSystem.purchase_upgrade(upgrade_id)
	refresh()
	_show_purchase_feedback(purchase_result, name_key)


func _on_close_pressed() -> void:
	closed_requested.emit()


func _show_purchase_feedback(purchase_result: Dictionary, name_key: String) -> void:
	if _feedback_label == null:
		return
	_feedback_label.visible = true
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


func _pointer_hit_at_position(position: Vector2) -> Dictionary:
	if _close_button != null and _button_contains_position(_close_button, position):
		return {
			"action": POINTER_ACTION_CLOSE,
			"index": -1,
		}
	for index: int in range(_purchase_buttons.size()):
		var button: Button = _purchase_buttons[index]
		if _button_contains_position(button, position):
			return {
				"action": POINTER_ACTION_PURCHASE,
				"index": index,
			}
	return {}


func _button_contains_position(button: Button, position: Vector2) -> bool:
	return (
		is_instance_valid(button)
		and button.visible
		and not button.disabled
		and button.get_global_rect().has_point(position)
	)


func _activate_pointer_action(action: String, purchase_index: int) -> void:
	if action == POINTER_ACTION_CLOSE:
		_on_close_pressed()
	elif action == POINTER_ACTION_PURCHASE:
		_on_purchase_pressed(purchase_index)
