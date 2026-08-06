# Doc: docs/代码/content_unlock_system.md
# Authority: docs/游戏设计文档.md
class_name CodexPanel
extends CanvasLayer


signal closed_requested()

const SKILL_DESCRIPTION_FORMATTER := preload(
	"res://scripts/data/skill_description_formatter.gd"
)
const CONTENT_UNLOCK_RULE_MODES := preload(
	"res://scripts/contracts/content_unlock_rule_modes.gd"
)
const CONTENT_UNLOCK_TYPES := preload(
	"res://scripts/contracts/content_unlock_types.gd"
)
const TYPE_CHARACTER: String = CONTENT_UNLOCK_TYPES.CHARACTER
const TYPE_GEAR_MOD: String = CONTENT_UNLOCK_TYPES.GEAR_MOD
const TYPE_ENEMY: String = CONTENT_UNLOCK_TYPES.ENEMY
const ENTRY_TYPES: Array[String] = [
	TYPE_CHARACTER,
	TYPE_GEAR_MOD,
	TYPE_ENEMY,
]
const LOCKED_NAME: String = "???"

var _category_buttons: Dictionary = {}
var _close_button: Button = null
var _content_source: Node = null
var _description_label: Label = null
var _detail_name_label: Label = null
var _detail_status_label: Label = null
var _entries: Array[Dictionary] = []
var _entry_list: ItemList = null
var _extra_label: Label = null
var _icon_placeholder: ColorRect = null
var _icon_texture: TextureRect = null
var _pending_preview_label: Label = null
var _selected_type: String = TYPE_CHARACTER
var _stats_label: Label = null
var _title_label: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind_nodes()
	if not _has_required_nodes():
		push_error("[CodexPanel] missing required scene nodes")
		return
	_category_buttons[TYPE_CHARACTER] = get_node(
		"Root/Center/Panel/Margin/Layout/CategoryRow/CharacterButton"
	) as Button
	_category_buttons[TYPE_GEAR_MOD] = get_node(
		"Root/Center/Panel/Margin/Layout/CategoryRow/GearModButton"
	) as Button
	_category_buttons[TYPE_ENEMY] = get_node(
		"Root/Center/Panel/Margin/Layout/CategoryRow/EnemyButton"
	) as Button
	for entry_type: String in ENTRY_TYPES:
		var button: Button = _category_buttons[entry_type] as Button
		button.pressed.connect(_on_category_pressed.bind(entry_type))
	_entry_list.item_selected.connect(_on_entry_selected)
	_close_button.pressed.connect(_on_close_pressed)
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	refresh_content()
	call_deferred("grab_default_focus")


func _exit_tree() -> void:
	if Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.disconnect(_on_locale_changed)


func configure_content_source(content_source: Node) -> void:
	_content_source = content_source
	if is_inside_tree() and _entry_list != null:
		refresh_content()


func refresh_content() -> void:
	_refresh_static_texts()
	_refresh_pending_preview()
	_rebuild_entries()


func select_category(entry_type: String) -> void:
	if not ENTRY_TYPES.has(entry_type):
		return
	_selected_type = entry_type
	_rebuild_entries()


func selected_type() -> String:
	return _selected_type


func displayed_entry_count() -> int:
	return _entries.size()


func select_entry(index: int) -> void:
	if _entry_list == null or index < 0 or index >= _entries.size():
		return
	_entry_list.select(index)
	_refresh_detail(index)


func grab_default_focus() -> void:
	var button: Button = _category_buttons.get(_selected_type) as Button
	if button != null:
		UIManager.grab_focus_for_navigation(button)


func request_close() -> void:
	closed_requested.emit()


func _bind_nodes() -> void:
	_title_label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Header/TitleLabel"
	) as Label
	_pending_preview_label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Header/PendingPreviewLabel"
	) as Label
	_entry_list = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Content/EntryListPanel/Margin/EntryList"
	) as ItemList
	_detail_name_label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Content/DetailPanel/Scroll/Margin/DetailLayout/DetailNameLabel"
	) as Label
	_detail_status_label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Content/DetailPanel/Scroll/Margin/DetailLayout/DetailStatusLabel"
	) as Label
	_description_label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Content/DetailPanel/Scroll/Margin/DetailLayout/DescriptionLabel"
	) as Label
	_stats_label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Content/DetailPanel/Scroll/Margin/DetailLayout/StatsLabel"
	) as Label
	_extra_label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Content/DetailPanel/Scroll/Margin/DetailLayout/ExtraLabel"
	) as Label
	_icon_texture = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Content/DetailPanel/Scroll/Margin/DetailLayout/IconFrame/IconTexture"
	) as TextureRect
	_icon_placeholder = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Content/DetailPanel/Scroll/Margin/DetailLayout/IconFrame/IconPlaceholder"
	) as ColorRect
	_close_button = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/CloseButton"
	) as Button


func _has_required_nodes() -> bool:
	return (
		_title_label != null
		and _pending_preview_label != null
		and _entry_list != null
		and _detail_name_label != null
		and _detail_status_label != null
		and _description_label != null
		and _stats_label != null
		and _extra_label != null
		and _icon_texture != null
		and _icon_placeholder != null
		and _close_button != null
		and get_node_or_null(
			"Root/Center/Panel/Margin/Layout/CategoryRow/CharacterButton"
		) is Button
		and get_node_or_null(
			"Root/Center/Panel/Margin/Layout/CategoryRow/GearModButton"
		) is Button
		and get_node_or_null(
			"Root/Center/Panel/Margin/Layout/CategoryRow/EnemyButton"
		) is Button
	)


func _refresh_static_texts() -> void:
	if _title_label != null:
		_title_label.text = tr("ui_codex_title")
	if _close_button != null:
		_close_button.text = tr("ui_codex_close")
	var locale_keys: Dictionary = {
		TYPE_CHARACTER: "ui_codex_category_character",
		TYPE_GEAR_MOD: "ui_codex_category_gear_mod",
		TYPE_ENEMY: "ui_codex_category_enemy",
	}
	for entry_type: String in ENTRY_TYPES:
		var button: Button = _category_buttons.get(entry_type) as Button
		if button != null:
			button.text = tr(String(locale_keys.get(entry_type, "")))


func _refresh_pending_preview() -> void:
	if _pending_preview_label == null:
		return
	var content_source: Node = _resolved_content_source()
	_pending_preview_label.visible = false
	_pending_preview_label.text = ""
	if content_source == null or not content_source.has_method("pending_run_preview"):
		return
	var preview: Variant = content_source.call("pending_run_preview")
	var count: int = _pending_preview_count(preview)
	if count <= 0:
		return
	_pending_preview_label.text = tr("ui_codex_pending_preview").format({
		"count": count,
	})
	_pending_preview_label.visible = true


func _pending_preview_count(preview: Variant) -> int:
	if preview is Array:
		return (preview as Array).size()
	if not preview is Dictionary:
		return 0
	var count: int = 0
	for entry_type: String in ENTRY_TYPES:
		var entries_value: Variant = (preview as Dictionary).get(entry_type, [])
		if entries_value is Array:
			count += (entries_value as Array).size()
	return count


func _rebuild_entries() -> void:
	if _entry_list == null:
		return
	var previous_id: String = _selected_entry_id()
	_entries = _entries_for_type(_selected_type)
	_entry_list.clear()
	var selected_index: int = -1
	for index: int in range(_entries.size()):
		var entry: Dictionary = _entries[index]
		var entry_id: String = String(entry.get("id", ""))
		var status: Dictionary = _requirement_status(_selected_type, entry_id)
		var display_name: String = LOCKED_NAME
		if _is_unlocked(entry, status):
			display_name = _localized_entry_value(entry, "name_key")
		_entry_list.add_item(display_name)
		_entry_list.set_item_metadata(index, entry_id)
		if entry_id == previous_id:
			selected_index = index
	if selected_index < 0 and not _entries.is_empty():
		selected_index = 0
	if selected_index >= 0:
		_entry_list.select(selected_index)
		_refresh_detail(selected_index)
	else:
		_clear_detail()
	_refresh_category_states()


func _refresh_category_states() -> void:
	for entry_type: String in ENTRY_TYPES:
		var button: Button = _category_buttons.get(entry_type) as Button
		if button != null:
			button.set_pressed_no_signal(entry_type == _selected_type)


func _selected_entry_id() -> String:
	if _entry_list == null:
		return ""
	var selected_items: PackedInt32Array = _entry_list.get_selected_items()
	if selected_items.is_empty():
		return ""
	return String(_entry_list.get_item_metadata(selected_items[0]))


func _entries_for_type(entry_type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var content_source: Node = _resolved_content_source()
	if content_source == null or not content_source.has_method("codex_entries"):
		return result
	var entries_value: Variant = content_source.call("codex_entries", entry_type)
	if not entries_value is Array:
		return result
	for raw_entry: Variant in entries_value as Array:
		if raw_entry is Dictionary:
			result.append((raw_entry as Dictionary).duplicate(true))
	return result


func _requirement_status(entry_type: String, entry_id: String) -> Dictionary:
	var content_source: Node = _resolved_content_source()
	if (
		content_source == null
		or not content_source.has_method("requirement_status")
	):
		return {}
	var status: Variant = content_source.call(
		"requirement_status",
		entry_type,
		entry_id
	)
	return (status as Dictionary).duplicate(true) if status is Dictionary else {}


func _resolved_content_source() -> Node:
	if _content_source != null and is_instance_valid(_content_source):
		return _content_source
	return get_node_or_null("/root/ContentUnlockSystem")


func _is_unlocked(entry: Dictionary, status: Dictionary) -> bool:
	if status.has("unlocked"):
		return bool(status.get("unlocked", false))
	if status.has("is_unlocked"):
		return bool(status.get("is_unlocked", false))
	if status.has("locked"):
		return not bool(status.get("locked", true))
	return bool(entry.get("unlocked", false))


func _refresh_detail(index: int) -> void:
	_clear_detail()
	if index < 0 or index >= _entries.size():
		return
	var entry: Dictionary = _entries[index]
	var entry_id: String = String(entry.get("id", ""))
	var status: Dictionary = _requirement_status(_selected_type, entry_id)
	if not _is_unlocked(entry, status):
		_refresh_locked_detail(status)
		return
	var display_entry: Dictionary = _enriched_unlocked_entry(entry)
	_refresh_unlocked_icon(display_entry)
	_detail_name_label.text = _localized_entry_value(display_entry, "name_key")
	_description_label.text = _localized_entry_value(
		display_entry,
		"desc_key",
		""
	)
	match _selected_type:
		TYPE_CHARACTER:
			_refresh_character_detail(display_entry)
		TYPE_GEAR_MOD:
			_refresh_gear_mod_detail(display_entry)
		TYPE_ENEMY:
			_refresh_enemy_detail(display_entry)
		_:
			_stats_label.text = ""
			_extra_label.text = ""


func _clear_detail() -> void:
	if _detail_name_label != null:
		_detail_name_label.text = ""
	if _detail_status_label != null:
		_detail_status_label.text = ""
	if _description_label != null:
		_description_label.text = ""
	if _stats_label != null:
		_stats_label.text = ""
	if _extra_label != null:
		_extra_label.text = ""
	if _icon_texture != null:
		_icon_texture.texture = null
		_icon_texture.visible = false
	if _icon_placeholder != null:
		_icon_placeholder.visible = true


func _refresh_locked_detail(status: Dictionary) -> void:
	_detail_name_label.text = LOCKED_NAME
	_detail_status_label.text = "%s\n%s" % [
		tr("ui_codex_locked"),
		_requirement_text(status),
	]


func _requirement_text(status: Dictionary) -> String:
	var conditions_value: Variant = status.get("conditions", [])
	if conditions_value is Array and not (conditions_value as Array).is_empty():
		var lines: PackedStringArray = PackedStringArray()
		if (conditions_value as Array).size() > 1:
			var mode: String = String(
				status.get("mode", CONTENT_UNLOCK_RULE_MODES.ALL)
			)
			var mode_key: String = (
				"ui_codex_requirement_mode_any"
				if mode == CONTENT_UNLOCK_RULE_MODES.ANY
				else "ui_codex_requirement_mode_all"
			)
			lines.append(tr(mode_key))
		for raw_condition: Variant in conditions_value as Array:
			if not raw_condition is Dictionary:
				continue
			lines.append(_condition_text(raw_condition as Dictionary))
		if not lines.is_empty():
			return "\n".join(lines)
	var condition_key: String = ""
	for key: String in [
		"condition_key",
		"requirement_key",
		"requirement_text_key",
	]:
		condition_key = String(status.get(key, ""))
		if not condition_key.is_empty():
			break
	var format_values: Dictionary = {}
	for params_key: String in ["params", "condition_params", "format_values"]:
		var params_value: Variant = status.get(params_key, {})
		if params_value is Dictionary:
			format_values.merge(params_value as Dictionary, true)
	if status.has("current"):
		format_values["current"] = status.get("current", 0)
	if status.has("target"):
		format_values["target"] = status.get("target", 0)
	if condition_key.is_empty():
		condition_key = "ui_codex_requirement_progress"
	return tr(condition_key).format(format_values)


func _condition_text(condition: Dictionary) -> String:
	var counter_id: String = String(condition.get("counter_id", ""))
	var locale_key: String = "ui_codex_requirement_%s" % counter_id
	var template: String = tr(locale_key)
	if template == locale_key:
		template = tr("ui_codex_requirement_progress")
	var subject_name_key: String = String(
		condition.get("subject_name_key", "")
	)
	var subject: String = (
		tr(subject_name_key)
		if not subject_name_key.is_empty()
		else String(condition.get("subject_id", ""))
	)
	var current_text: String = template.format({
		"current": int(condition.get("current", 0)),
		"pending": int(condition.get("pending", 0)),
		"subject": subject,
		"target": int(condition.get("target", 0)),
	})
	var pending: int = int(condition.get("pending", 0))
	if pending > 0:
		current_text = "%s  %s" % [
			current_text,
			tr("ui_codex_pending_progress").format({"count": pending}),
		]
	return current_text


func _refresh_unlocked_icon(entry: Dictionary) -> void:
	var icon_path: String = String(entry.get("icon_path", ""))
	if icon_path.is_empty() or not ResourceLoader.exists(icon_path):
		return
	var icon_resource: Resource = load(icon_path)
	if not icon_resource is Texture2D:
		return
	_icon_texture.texture = icon_resource as Texture2D
	_icon_texture.visible = true
	_icon_placeholder.visible = false


func _enriched_unlocked_entry(entry: Dictionary) -> Dictionary:
	var entry_id: String = String(entry.get("id", ""))
	var definition: Dictionary = {}
	match _selected_type:
		TYPE_CHARACTER:
			definition = _definition_by_id(
				DataLoader.CHARACTERS_PATH,
				"characters",
				entry_id
			)
		TYPE_GEAR_MOD:
			definition = _definition_by_id(
				DataLoader.GEAR_MODS_PATH,
				"mods",
				entry_id
			)
		TYPE_ENEMY:
			definition = _enemy_definition(entry_id)
		_:
			definition = {}
	var details_value: Variant = entry.get("details", {})
	if details_value is Dictionary:
		definition.merge(details_value as Dictionary, true)
	definition.merge(entry, true)
	return definition


func _refresh_character_detail(entry: Dictionary) -> void:
	var stats: Dictionary = entry.get("base_stats", {}) as Dictionary
	var lines: PackedStringArray = [tr("ui_codex_character_stats")]
	_append_stat_line(lines, stats, "max_hp", "ui_stats_life")
	_append_stat_line(lines, stats, "max_shield", "ui_stats_shield")
	_append_stat_line(lines, stats, "max_energy", "ui_stats_energy")
	_append_stat_line(lines, stats, "move_speed", "ui_stats_move_speed")
	_append_stat_line(lines, stats, "armor", "ui_stats_armor")
	_stats_label.text = "\n".join(lines)

	var extra_lines: PackedStringArray = PackedStringArray()
	var passive: Dictionary = _definition_by_id(
		DataLoader.HERO_PASSIVES_PATH,
		"passives",
		String(entry.get("passive_id", ""))
	)
	if not passive.is_empty():
		extra_lines.append("%s: %s" % [
			tr("ui_hero_composition_passive"),
			_localized_entry_value(passive, "name_key"),
		])
		extra_lines.append(
			SKILL_DESCRIPTION_FORMATTER.format_passive(
				_localized_entry_value(passive, "desc_key", ""),
				passive
			)
		)
	var skills_value: Variant = entry.get("hero_skill_ids", [])
	if skills_value is Array:
		var skills: Array = skills_value as Array
		for index: int in range(skills.size()):
			var skill: Dictionary = _definition_by_id(
				DataLoader.SKILLS_PATH,
				"skills",
				String(skills[index])
			)
			if skill.is_empty():
				continue
			extra_lines.append("")
			extra_lines.append("%s %d: %s" % [
				tr("ui_hero_composition_skill"),
				index + 1,
				_localized_entry_value(skill, "name_key"),
			])
			extra_lines.append(
				SKILL_DESCRIPTION_FORMATTER.format_skill(
					_localized_entry_value(skill, "desc_key", ""),
					skill,
					stats
				)
			)
	_extra_label.text = "\n".join(extra_lines)


func _refresh_gear_mod_detail(entry: Dictionary) -> void:
	var slot: String = _translated_value(
		"ui_codex_slot_",
		String(entry.get("slot", ""))
	)
	var rarity: String = _translated_value(
		"ui_codex_rarity_",
		String(entry.get("rarity", ""))
	)
	var max_rank: int = maxi(int(entry.get("max_rank", 0)) + 1, 1)
	_stats_label.text = "%s\n%s\n%s" % [
		"%s: %s" % [tr("ui_codex_gear_slot"), slot],
		"%s: %s" % [tr("ui_codex_gear_rarity"), rarity],
		tr("ui_codex_gear_rank").format({
			"min_rank": 1,
			"max_rank": max_rank,
		}),
	]


func _refresh_enemy_detail(entry: Dictionary) -> void:
	var lines: PackedStringArray = [tr("ui_codex_enemy_stats")]
	_append_stat_line(lines, entry, "max_hp", "ui_stats_life")
	_append_stat_line(lines, entry, "move_speed", "ui_stats_move_speed")
	_append_stat_line(
		lines,
		entry,
		"gold_value_multiplier",
		"ui_codex_enemy_reward_value"
	)
	_stats_label.text = "\n".join(lines)


func _append_stat_line(
	lines: PackedStringArray,
	values: Dictionary,
	stat_key: String,
	locale_key: String
) -> void:
	if not values.has(stat_key):
		return
	lines.append("%s: %s" % [
		tr(locale_key),
		_format_number(float(values.get(stat_key, 0.0))),
	])


func _format_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return str(snappedf(value, 0.01))


func _localized_entry_value(
	entry: Dictionary,
	field: String,
	fallback: String = LOCKED_NAME
) -> String:
	var locale_key: String = String(entry.get(field, ""))
	return tr(locale_key) if not locale_key.is_empty() else fallback


func _translated_value(prefix: String, value: String) -> String:
	if value.is_empty():
		return LOCKED_NAME
	var locale_key: String = "%s%s" % [prefix, value]
	var translated: String = tr(locale_key)
	return translated if translated != locale_key else LOCKED_NAME


func _definition_by_id(
	path: String,
	array_key: String,
	requested_id: String
) -> Dictionary:
	if requested_id.is_empty():
		return {}
	var payload: Variant = DataLoader.load_json(path)
	if not payload is Dictionary:
		return {}
	var entries_value: Variant = (payload as Dictionary).get(array_key, [])
	if not entries_value is Array:
		return {}
	for raw_entry: Variant in entries_value as Array:
		if (
			raw_entry is Dictionary
			and String((raw_entry as Dictionary).get("id", ""))
			== requested_id
		):
			return (raw_entry as Dictionary).duplicate(true)
	return {}


func _enemy_definition(requested_id: String) -> Dictionary:
	if requested_id.is_empty():
		return {}
	for row: Dictionary in DataLoader.load_csv(DataLoader.ENEMIES_PATH):
		if String(row.get("id", "")) == requested_id:
			return row.duplicate(true)
	return {}


func _on_category_pressed(entry_type: String) -> void:
	select_category(entry_type)
	if _entry_list != null:
		UIManager.grab_focus_for_navigation(_entry_list)


func _on_entry_selected(index: int) -> void:
	_refresh_detail(index)


func _on_close_pressed() -> void:
	request_close()


func _on_locale_changed(_locale: String) -> void:
	refresh_content()
