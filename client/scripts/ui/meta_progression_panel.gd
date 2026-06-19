# Doc: docs/代码/meta_progression_system.md
# Authority: docs/AI协作/工作包/F6-MetaProgression.md
class_name MetaProgressionPanel
extends CanvasLayer


signal closed_requested()

const BUTTON_HEIGHT: float = 46.0
const BUTTON_WIDTH: float = 180.0
const ROW_MIN_HEIGHT: float = 130.0
const POINTER_ACTION_CLOSE: String = "close"
const POINTER_ACTION_PURCHASE: String = "purchase"
const FEEDBACK_FAILURE_COLOR: Color = Color(0.95, 0.55, 0.50, 1.0)
const FEEDBACK_SUCCESS_COLOR: Color = Color(0.54, 0.87, 0.60, 1.0)
const ROW_BG_INSUFFICIENT: Color = Color(0.18, 0.15, 0.09, 0.96)
const ROW_BG_LOCKED: Color = Color(0.11, 0.12, 0.15, 0.96)
const ROW_BG_MAXED: Color = Color(0.10, 0.14, 0.18, 0.96)
const ROW_BG_PURCHASABLE: Color = Color(0.10, 0.17, 0.12, 0.96)
const ROW_BG_UNAVAILABLE: Color = Color(0.17, 0.10, 0.10, 0.96)
const ROW_BORDER_INSUFFICIENT: Color = Color(0.78, 0.56, 0.22, 1.0)
const ROW_BORDER_LOCKED: Color = Color(0.34, 0.38, 0.46, 1.0)
const ROW_BORDER_MAXED: Color = Color(0.37, 0.60, 0.78, 1.0)
const ROW_BORDER_PURCHASABLE: Color = Color(0.34, 0.72, 0.40, 1.0)
const ROW_BORDER_UNAVAILABLE: Color = Color(0.74, 0.36, 0.34, 1.0)
const STATUS_COLOR_INSUFFICIENT: Color = Color(0.95, 0.74, 0.38, 1.0)
const STATUS_COLOR_LOCKED: Color = Color(0.72, 0.76, 0.84, 1.0)
const STATUS_COLOR_MAXED: Color = Color(0.68, 0.84, 0.96, 1.0)
const STATUS_COLOR_PURCHASABLE: Color = Color(0.64, 0.91, 0.66, 1.0)
const STATUS_COLOR_UNAVAILABLE: Color = Color(0.96, 0.58, 0.54, 1.0)

var _account_label: Label = null
var _close_button: Button = null
var _currency_label: Label = null
var _feedback_label: Label = null
var _last_feedback_name_key: String = ""
var _last_feedback_result: Dictionary = {}
var _pressed_pointer_action: String = ""
var _pressed_purchase_index: int = -1
var _purchase_buttons: Array[Button] = []
var _title_label: Label = null
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

	_title_label = get_node_or_null("Root/Center/MetaProgressionPanelContainer/Margin/Layout/TitleLabel") as Label
	_account_label = get_node_or_null("Root/Center/MetaProgressionPanelContainer/Margin/Layout/ProfileRow/MetaAccountLabel") as Label
	_currency_label = get_node_or_null("Root/Center/MetaProgressionPanelContainer/Margin/Layout/ProfileRow/MetaCurrencyLabel") as Label
	_feedback_label = get_node_or_null("Root/Center/MetaProgressionPanelContainer/Margin/Layout/MetaPurchaseFeedbackLabel") as Label
	_upgrade_list = get_node_or_null("Root/Center/MetaProgressionPanelContainer/Margin/Layout/MetaUpgradeScroll/MetaUpgradeList") as VBoxContainer
	_close_button = get_node_or_null("Root/Center/MetaProgressionPanelContainer/Margin/Layout/CloseButton") as Button
	if _title_label == null or _account_label == null or _currency_label == null:
		push_error("[MetaProgressionPanel] missing required scene nodes")
		return
	if _feedback_label == null or _upgrade_list == null or _close_button == null:
		push_error("[MetaProgressionPanel] missing required scene nodes")
		return

	_feedback_label.visible = false
	_close_button.process_mode = Node.PROCESS_MODE_ALWAYS
	_close_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_close_button.pressed.connect(_on_close_pressed)
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)

	refresh_texts()


func _exit_tree() -> void:
	if Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.disconnect(_on_locale_changed)


func refresh() -> void:
	_refresh_profile()
	_refresh_upgrades()


func refresh_texts() -> void:
	if _title_label != null:
		_title_label.text = tr("ui_meta_progression_title")
	if _close_button != null:
		_close_button.text = tr("ui_cancel")
	refresh()
	if _feedback_label != null and _feedback_label.visible and not _last_feedback_result.is_empty():
		_refresh_purchase_feedback()


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


func _make_upgrade_row(summary: Dictionary) -> Control:
	var row: PanelContainer = PanelContainer.new()
	row.name = "MetaUpgradeRow_%s" % String(summary.get("upgrade_id", ""))
	row.process_mode = Node.PROCESS_MODE_ALWAYS
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.custom_minimum_size = Vector2(0.0, ROW_MIN_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_stylebox_override("panel", _make_row_stylebox(summary))

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

	var status_label: Label = Label.new()
	status_label.name = "MetaUpgradeStatus_%s" % String(summary.get("upgrade_id", ""))
	status_label.process_mode = Node.PROCESS_MODE_ALWAYS
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.text = _upgrade_status_text(summary)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", _upgrade_status_color(summary))
	text_layout.add_child(status_label)

	var purchase_button: Button = _make_button(
		"Purchase_%s" % String(summary.get("upgrade_id", "")),
		_purchase_text(summary)
	)
	purchase_button.disabled = not bool(summary.get("can_purchase", false))
	purchase_button.tooltip_text = _upgrade_status_text(summary)
	var button_index: int = _purchase_buttons.size()
	purchase_button.pressed.connect(func() -> void:
		_on_purchase_pressed(button_index)
	)
	_purchase_buttons.append(purchase_button)
	_upgrade_ids.append(String(summary.get("upgrade_id", "")))
	_upgrade_name_keys.append(String(summary.get("name_key", "")))
	row_layout.add_child(purchase_button)
	return row


func _make_row_stylebox(summary: Dictionary) -> StyleBoxFlat:
	var stylebox: StyleBoxFlat = StyleBoxFlat.new()
	stylebox.bg_color = _upgrade_row_background_color(summary)
	stylebox.border_color = _upgrade_row_border_color(summary)
	stylebox.set_border_width_all(1)
	stylebox.set_corner_radius_all(6)
	return stylebox


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


func _upgrade_status_text(summary: Dictionary) -> String:
	var reason: String = String(summary.get("reason", ""))
	var balance_text: String = _balance_text(summary)
	if reason == "max_level":
		return _join_status_parts([
			tr("ui_meta_upgrade_maxed"),
			balance_text,
		])
	if reason == "locked":
		return _join_status_parts([
			tr("ui_meta_upgrade_locked").format({
				"level": int(summary.get("account_level_required", 1)),
			}),
			balance_text,
		])
	if reason == "insufficient_currency":
		return _join_status_parts([
			balance_text,
			_cost_text(summary),
			tr("ui_meta_upgrade_insufficient"),
		])
	if reason == "missing_cost":
		return _join_status_parts([
			tr("ui_meta_purchase_unavailable"),
			balance_text,
		])
	return _join_status_parts([
		balance_text,
		_cost_text(summary),
	])


func _balance_text(summary: Dictionary) -> String:
	var currency_name: String = tr(String(summary.get("currency_name_key", "")))
	return tr("ui_meta_balance").format({
		"currency": currency_name,
		"amount": int(summary.get("balance", 0)),
	})


func _cost_text(summary: Dictionary) -> String:
	var currency_name: String = tr(String(summary.get("currency_name_key", "")))
	return tr("ui_meta_upgrade_cost").format({
		"currency": currency_name,
		"cost": int(summary.get("cost", 0)),
	})


func _join_status_parts(parts: Array[String]) -> String:
	var cleaned_parts: Array[String] = []
	for part: String in parts:
		if not part.is_empty():
			cleaned_parts.append(part)
	return " | ".join(cleaned_parts)


func _upgrade_row_background_color(summary: Dictionary) -> Color:
	if bool(summary.get("can_purchase", false)):
		return ROW_BG_PURCHASABLE
	var reason: String = String(summary.get("reason", ""))
	if reason == "max_level":
		return ROW_BG_MAXED
	if reason == "locked":
		return ROW_BG_LOCKED
	if reason == "insufficient_currency":
		return ROW_BG_INSUFFICIENT
	return ROW_BG_UNAVAILABLE


func _upgrade_row_border_color(summary: Dictionary) -> Color:
	if bool(summary.get("can_purchase", false)):
		return ROW_BORDER_PURCHASABLE
	var reason: String = String(summary.get("reason", ""))
	if reason == "max_level":
		return ROW_BORDER_MAXED
	if reason == "locked":
		return ROW_BORDER_LOCKED
	if reason == "insufficient_currency":
		return ROW_BORDER_INSUFFICIENT
	return ROW_BORDER_UNAVAILABLE


func _upgrade_status_color(summary: Dictionary) -> Color:
	if bool(summary.get("can_purchase", false)):
		return STATUS_COLOR_PURCHASABLE
	var reason: String = String(summary.get("reason", ""))
	if reason == "max_level":
		return STATUS_COLOR_MAXED
	if reason == "locked":
		return STATUS_COLOR_LOCKED
	if reason == "insufficient_currency":
		return STATUS_COLOR_INSUFFICIENT
	return STATUS_COLOR_UNAVAILABLE


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
	_last_feedback_result = purchase_result.duplicate(true)
	_last_feedback_name_key = name_key
	_refresh_purchase_feedback()


func _refresh_purchase_feedback() -> void:
	if _feedback_label == null:
		return
	_feedback_label.visible = true
	if bool(_last_feedback_result.get("ok", false)):
		_feedback_label.add_theme_color_override("font_color", FEEDBACK_SUCCESS_COLOR)
		_feedback_label.text = tr("ui_meta_purchase_success").format({
			"name": tr(_last_feedback_name_key),
			"level": int(_last_feedback_result.get("level", 0)),
		})
		return
	_feedback_label.add_theme_color_override("font_color", FEEDBACK_FAILURE_COLOR)
	_feedback_label.text = tr("ui_meta_purchase_failed").format({
		"reason": _purchase_failure_text(_last_feedback_result),
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


func _on_locale_changed(_locale: String) -> void:
	refresh_texts()
