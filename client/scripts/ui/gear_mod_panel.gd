# Doc: docs/代码/gear_mod_system.md
# Authority: docs/游戏设计文档.md §7.2 / §9.16, docs/AI协作/工作包/F11-GearModLoadout.md
class_name GearModPanel
extends CanvasLayer


signal closed_requested()

const GEAR_MOD_EMPTY_ROW_SCENE: PackedScene = preload("res://scenes/ui/gear_mod_empty_row.tscn")
const GEAR_MOD_ROW_SCENE: PackedScene = preload("res://scenes/ui/gear_mod_row.tscn")
const GEAR_MOD_RESOURCES := preload("res://scripts/contracts/gear_mod_resources.gd")
const GEAR_MOD_SLOTS := preload("res://scripts/contracts/gear_mod_slots.gd")

const BUTTON_HEIGHT: float = 44.0
const ROW_MIN_HEIGHT: float = 72.0
const FEEDBACK_FAILURE_COLOR: Color = Color(0.95, 0.55, 0.50, 1.0)
const FEEDBACK_SUCCESS_COLOR: Color = Color(0.54, 0.87, 0.60, 1.0)
const ROW_BG_EQUIPPED: Color = Color(0.10, 0.17, 0.12, 0.96)
const ROW_BG_SELECTED: Color = Color(0.13, 0.15, 0.20, 0.96)
const ROW_BG_DEFAULT: Color = Color(0.09, 0.10, 0.13, 0.96)
const ROW_BORDER_EQUIPPED: Color = Color(0.34, 0.72, 0.40, 1.0)
const ROW_BORDER_SELECTED: Color = Color(0.48, 0.57, 0.76, 1.0)
const ROW_BORDER_DEFAULT: Color = Color(0.28, 0.31, 0.38, 1.0)

var _active_slot: String = GEAR_MOD_SLOTS.WEAPON
var _capacity_label: Label = null
var _close_button: Button = null
var _details_label: Label = null
var _dismantle_button: Button = null
var _equip_button: Button = null
var _feedback_label: Label = null
var _hero_tab_button: Button = null
var _last_feedback_action: String = ""
var _last_feedback_name_key: String = ""
var _last_feedback_result: Dictionary = {}
var _mod_list: VBoxContainer = null
var _profile_slot: String = SaveManager.DEFAULT_SLOT
var _resource_label: Label = null
var _selected_instance_id: String = ""
var _summaries: Array[Dictionary] = []
var _title_label: Label = null
var _upgrade_button: Button = null
var _weapon_tab_button: Button = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_title_label = get_node_or_null("Root/Center/GearModPanelContainer/Margin/Layout/TitleLabel") as Label
	_hero_tab_button = get_node_or_null("Root/Center/GearModPanelContainer/Margin/Layout/TabRow/HeroTabButton") as Button
	_weapon_tab_button = get_node_or_null("Root/Center/GearModPanelContainer/Margin/Layout/TabRow/WeaponTabButton") as Button
	_resource_label = get_node_or_null("Root/Center/GearModPanelContainer/Margin/Layout/SummaryRow/ResourceLabel") as Label
	_capacity_label = get_node_or_null("Root/Center/GearModPanelContainer/Margin/Layout/SummaryRow/CapacityLabel") as Label
	_feedback_label = get_node_or_null("Root/Center/GearModPanelContainer/Margin/Layout/FeedbackLabel") as Label
	_mod_list = get_node_or_null("Root/Center/GearModPanelContainer/Margin/Layout/ContentRow/InventoryScroll/ModList") as VBoxContainer
	_details_label = get_node_or_null("Root/Center/GearModPanelContainer/Margin/Layout/ContentRow/DetailsPanel/Margin/DetailsLayout/DetailsLabel") as Label
	_equip_button = get_node_or_null("Root/Center/GearModPanelContainer/Margin/Layout/ContentRow/DetailsPanel/Margin/DetailsLayout/ActionRow/EquipButton") as Button
	_upgrade_button = get_node_or_null("Root/Center/GearModPanelContainer/Margin/Layout/ContentRow/DetailsPanel/Margin/DetailsLayout/ActionRow/UpgradeButton") as Button
	_dismantle_button = get_node_or_null("Root/Center/GearModPanelContainer/Margin/Layout/ContentRow/DetailsPanel/Margin/DetailsLayout/ActionRow/DismantleButton") as Button
	_close_button = get_node_or_null("Root/Center/GearModPanelContainer/Margin/Layout/CloseButton") as Button
	if _title_label == null or _hero_tab_button == null or _weapon_tab_button == null:
		push_error("[GearModPanel] missing required scene nodes")
		return
	if _resource_label == null or _capacity_label == null or _feedback_label == null or _mod_list == null:
		push_error("[GearModPanel] missing required scene nodes")
		return
	if _details_label == null or _equip_button == null or _upgrade_button == null or _dismantle_button == null or _close_button == null:
		push_error("[GearModPanel] missing required scene nodes")
		return

	_feedback_label.visible = false
	_connect_button(_hero_tab_button, _on_hero_tab_pressed)
	_connect_button(_weapon_tab_button, _on_weapon_tab_pressed)
	_connect_button(_equip_button, _on_equip_pressed)
	_connect_button(_upgrade_button, _on_upgrade_pressed)
	_connect_button(_dismantle_button, _on_dismantle_pressed)
	_connect_button(_close_button, _on_close_pressed)
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	refresh_texts()


func _exit_tree() -> void:
	if Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.disconnect(_on_locale_changed)


func configure(profile_slot: String = SaveManager.DEFAULT_SLOT) -> void:
	_profile_slot = profile_slot
	if is_inside_tree():
		refresh()


func refresh() -> void:
	_refresh_summary()
	_refresh_mod_list()
	_refresh_details()


func request_close() -> void:
	_on_close_pressed()


func refresh_texts() -> void:
	if _title_label != null:
		_title_label.text = tr("ui_gear_mod_title")
	if _hero_tab_button != null:
		_hero_tab_button.text = tr("ui_gear_mod_tab_hero")
	if _weapon_tab_button != null:
		_weapon_tab_button.text = tr("ui_gear_mod_tab_weapon")
	if _close_button != null:
		_close_button.text = tr("ui_cancel")
	refresh()
	if _feedback_label != null and _feedback_label.visible and not _last_feedback_result.is_empty():
		_refresh_feedback()


func _refresh_summary() -> void:
	var profile: Dictionary = GearModSystem.profile_summary(_profile_slot)
	var resources: Dictionary = profile.get("resources", {}) as Dictionary
	var resource_parts: Array[String] = []
	for resource_id: String in GEAR_MOD_RESOURCES.VALUES:
		resource_parts.append(tr("ui_gear_mod_resource_summary").format({
			"resource": tr("%s_name" % resource_id),
			"amount": int(resources.get(resource_id, 0)),
		}))
	if _resource_label != null:
		_resource_label.text = " · ".join(resource_parts)

	var loadouts: Dictionary = profile.get("loadouts", {}) as Dictionary
	var loadout: Dictionary = loadouts.get(_active_slot, {}) as Dictionary
	if _capacity_label != null:
		_capacity_label.text = tr("ui_gear_mod_capacity").format({
			"used": int(loadout.get("used_drain", 0)),
			"capacity": int(loadout.get("capacity", 0)),
		})

	if _hero_tab_button != null:
		_hero_tab_button.button_pressed = _active_slot == GEAR_MOD_SLOTS.HERO
	if _weapon_tab_button != null:
		_weapon_tab_button.button_pressed = _active_slot == GEAR_MOD_SLOTS.WEAPON


func _refresh_mod_list() -> void:
	if _mod_list == null:
		return
	for child: Node in _mod_list.get_children():
		_mod_list.remove_child(child)
		child.queue_free()
	_summaries.clear()

	for summary: Dictionary in GearModSystem.mod_summaries(_active_slot, _profile_slot):
		if String(summary.get("slot", "")) != _active_slot:
			continue
		_summaries.append(summary)
		var row: Control = _make_mod_row(summary)
		if row != null:
			_mod_list.add_child(row)

	if _summaries.is_empty():
		_selected_instance_id = ""
		var empty_label: Label = GEAR_MOD_EMPTY_ROW_SCENE.instantiate() as Label
		if empty_label == null:
			push_error("[GearModPanel] failed to instantiate empty row template")
			return
		empty_label.name = "GearModEmptyLabel"
		empty_label.text = tr("ui_gear_mod_empty")
		_mod_list.add_child(empty_label)
		return

	if _find_summary(_selected_instance_id).is_empty():
		_selected_instance_id = String(_summaries[0].get("instance_id", ""))


func _make_mod_row(summary: Dictionary) -> Control:
	var instance_id: String = String(summary.get("instance_id", ""))
	var row: Button = GEAR_MOD_ROW_SCENE.instantiate() as Button
	if row == null:
		push_error("[GearModPanel] failed to instantiate mod row template")
		return null
	row.name = "GearModRow_%s" % instance_id
	row.custom_minimum_size = Vector2(0.0, ROW_MIN_HEIGHT)
	row.text = _row_text(summary)
	row.tooltip_text = tr(String(summary.get("desc_key", "")))
	row.add_theme_stylebox_override("normal", _make_row_stylebox(summary))
	row.add_theme_stylebox_override("hover", _make_row_stylebox(summary))
	row.add_theme_stylebox_override("pressed", _make_row_stylebox(summary))
	row.pressed.connect(func() -> void:
		_on_mod_row_pressed(instance_id)
	)
	return row


func _row_text(summary: Dictionary) -> String:
	var parts: Array[String] = [
		tr(String(summary.get("name_key", ""))),
		tr("ui_gear_mod_rank").format({
			"rank": int(summary.get("rank", 0)),
			"max": int(summary.get("max_rank", 0)),
		}),
		tr("ui_gear_mod_drain").format({
			"drain": int(summary.get("drain", 0)),
		}),
	]
	if bool(summary.get("equipped", false)):
		parts.append(tr("ui_gear_mod_equipped"))
	return " · ".join(parts)


func _make_row_stylebox(summary: Dictionary) -> StyleBoxFlat:
	var stylebox: StyleBoxFlat = StyleBoxFlat.new()
	if bool(summary.get("equipped", false)):
		stylebox.bg_color = ROW_BG_EQUIPPED
		stylebox.border_color = ROW_BORDER_EQUIPPED
	elif String(summary.get("instance_id", "")) == _selected_instance_id:
		stylebox.bg_color = ROW_BG_SELECTED
		stylebox.border_color = ROW_BORDER_SELECTED
	else:
		stylebox.bg_color = ROW_BG_DEFAULT
		stylebox.border_color = ROW_BORDER_DEFAULT
	stylebox.set_border_width_all(1)
	stylebox.set_corner_radius_all(6)
	return stylebox


func _refresh_details() -> void:
	var summary: Dictionary = _find_summary(_selected_instance_id)
	var has_selection: bool = not summary.is_empty()
	if _details_label != null:
		_details_label.text = _details_text(summary) if has_selection else tr("ui_gear_mod_no_selection")
	if _equip_button != null:
		_equip_button.text = tr("ui_gear_mod_unequip") if bool(summary.get("equipped", false)) else tr("ui_gear_mod_equip")
		_equip_button.disabled = not has_selection
	if _upgrade_button != null:
		_upgrade_button.text = _upgrade_button_text(summary)
		_upgrade_button.disabled = not has_selection or int(summary.get("rank", 0)) >= int(summary.get("max_rank", 0))
	if _dismantle_button != null:
		_dismantle_button.text = _dismantle_button_text(summary)
		_dismantle_button.disabled = not has_selection or bool(summary.get("equipped", false))


func _details_text(summary: Dictionary) -> String:
	if summary.is_empty():
		return tr("ui_gear_mod_no_selection")
	var lines: Array[String] = [
		tr(String(summary.get("name_key", ""))),
		tr(String(summary.get("desc_key", ""))),
		tr("ui_gear_mod_rank").format({
			"rank": int(summary.get("rank", 0)),
			"max": int(summary.get("max_rank", 0)),
		}),
		tr("ui_gear_mod_drain").format({
			"drain": int(summary.get("drain", 0)),
		}),
	]
	var modifiers: Array = summary.get("modifiers", []) as Array
	for modifier: Variant in modifiers:
		if modifier is Dictionary:
			lines.append(_modifier_text(modifier as Dictionary))
	return "\n".join(lines)


func _modifier_text(modifier: Dictionary) -> String:
	var modifier_type: String = String(modifier.get("type", ""))
	return tr("ui_gear_mod_effect_line").format({
		"stat": _stat_text(String(modifier.get("stat", ""))),
		"type": tr("ui_gear_mod_modifier_type_%s" % modifier_type),
		"value": _modifier_value_text(modifier_type, float(modifier.get("value", 0.0))),
	})


func _stat_text(stat_id: String) -> String:
	var key: String = "ui_stats_%s" % stat_id
	var translated: String = tr(key)
	return stat_id if translated == key else translated


func _modifier_value_text(modifier_type: String, value: float) -> String:
	if modifier_type == "mult":
		return "+%d%%" % int(round((value - 1.0) * 100.0))
	if value >= 0.0:
		return "+%.2f" % value
	return "%.2f" % value


func _upgrade_button_text(summary: Dictionary) -> String:
	if summary.is_empty():
		return tr("ui_gear_mod_upgrade")
	if int(summary.get("rank", 0)) >= int(summary.get("max_rank", 0)):
		return tr("ui_gear_mod_max_rank")
	var cost: Dictionary = summary.get("upgrade_cost", {}) as Dictionary
	if cost.is_empty():
		return tr("ui_gear_mod_upgrade")
	return tr("ui_gear_mod_upgrade_cost").format({
		"resource": tr("%s_name" % String(cost.get("resource_id", ""))),
		"cost": int(cost.get("cost", 0)),
	})


func _dismantle_button_text(summary: Dictionary) -> String:
	if summary.is_empty():
		return tr("ui_gear_mod_dismantle")
	var dismantle: Dictionary = summary.get("dismantle", {}) as Dictionary
	if dismantle.is_empty():
		return tr("ui_gear_mod_dismantle")
	return tr("ui_gear_mod_dismantle_value").format({
		"resource": tr("%s_name" % String(dismantle.get("resource_id", ""))),
		"amount": int(dismantle.get("amount", 0)),
	})


func _find_summary(instance_id: String) -> Dictionary:
	for summary: Dictionary in _summaries:
		if String(summary.get("instance_id", "")) == instance_id:
			return summary
	return {}


func _connect_button(button: Button, target: Callable) -> void:
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.custom_minimum_size.y = BUTTON_HEIGHT
	button.pressed.connect(target)


func _on_hero_tab_pressed() -> void:
	_active_slot = GEAR_MOD_SLOTS.HERO
	_selected_instance_id = ""
	refresh()


func _on_weapon_tab_pressed() -> void:
	_active_slot = GEAR_MOD_SLOTS.WEAPON
	_selected_instance_id = ""
	refresh()


func _on_mod_row_pressed(instance_id: String) -> void:
	_selected_instance_id = instance_id
	refresh()


func _on_equip_pressed() -> void:
	var summary: Dictionary = _find_summary(_selected_instance_id)
	if summary.is_empty():
		return
	var result: Dictionary = {}
	if bool(summary.get("equipped", false)):
		result = GearModSystem.unequip_mod(_active_slot, _selected_instance_id, _profile_slot)
		_show_feedback(result, "unequip", String(summary.get("name_key", "")))
	else:
		result = GearModSystem.equip_mod(_active_slot, _selected_instance_id, _profile_slot)
		_show_feedback(result, "equip", String(summary.get("name_key", "")))
	refresh()


func _on_upgrade_pressed() -> void:
	var summary: Dictionary = _find_summary(_selected_instance_id)
	if summary.is_empty():
		return
	var result: Dictionary = GearModSystem.upgrade_mod(_selected_instance_id, _profile_slot)
	_show_feedback(result, "upgrade", String(summary.get("name_key", "")))
	refresh()


func _on_dismantle_pressed() -> void:
	var summary: Dictionary = _find_summary(_selected_instance_id)
	if summary.is_empty():
		return
	var result: Dictionary = GearModSystem.dismantle_mod(_selected_instance_id, _profile_slot)
	_show_feedback(result, "dismantle", String(summary.get("name_key", "")))
	if bool(result.get("ok", false)):
		_selected_instance_id = ""
	refresh()


func _on_close_pressed() -> void:
	closed_requested.emit()


func _show_feedback(result: Dictionary, action: String, name_key: String) -> void:
	_last_feedback_result = result.duplicate(true)
	_last_feedback_action = action
	_last_feedback_name_key = name_key
	_refresh_feedback()


func _refresh_feedback() -> void:
	if _feedback_label == null:
		return
	_feedback_label.visible = true
	if bool(_last_feedback_result.get("ok", false)):
		_feedback_label.add_theme_color_override("font_color", FEEDBACK_SUCCESS_COLOR)
		_feedback_label.text = _success_feedback_text()
		return
	_feedback_label.add_theme_color_override("font_color", FEEDBACK_FAILURE_COLOR)
	_feedback_label.text = tr("ui_gear_mod_feedback_failed").format({
		"reason": _failure_reason_text(String(_last_feedback_result.get("reason", ""))),
	})


func _success_feedback_text() -> String:
	if _last_feedback_action == "upgrade":
		return tr("ui_gear_mod_feedback_upgrade_success").format({
			"name": tr(_last_feedback_name_key),
			"rank": int(_last_feedback_result.get("rank", 0)),
		})
	return tr("ui_gear_mod_feedback_success").format({
		"action": tr("ui_gear_mod_action_%s" % _last_feedback_action),
		"name": tr(_last_feedback_name_key),
	})


func _failure_reason_text(reason: String) -> String:
	var key: String = "ui_gear_mod_reason_%s" % reason
	var translated: String = tr(key)
	return tr("ui_gear_mod_reason_unknown") if translated == key else translated


func _on_locale_changed(_locale: String) -> void:
	refresh_texts()
