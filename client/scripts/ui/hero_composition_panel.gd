# Doc: docs/代码/formal_client_boot.md
# Authority: docs/游戏设计文档.md
class_name HeroCompositionPanel
extends CanvasLayer


signal cancel_requested()
signal composition_confirmed(main_hero_id: String, sub_hero_id: String)

const SKILL_DESCRIPTION_FORMATTER := preload(
	"res://scripts/data/skill_description_formatter.gd"
)

var _cancel_button: Button = null
var _confirm_button: Button = null
var _hero_rows: Array[Dictionary] = []
var _hint_label: Label = null
var _main_detail_label: Label = null
var _main_heading_label: Label = null
var _main_selector: OptionButton = null
var _sub_detail_label: Label = null
var _sub_heading_label: Label = null
var _sub_selector: OptionButton = null
var _swap_button: Button = null
var _title_label: Label = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_title_label = get_node_or_null("Root/Center/Panel/Margin/Layout/TitleLabel") as Label
	_main_selector = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/MainHeroSelector"
	) as OptionButton
	_sub_selector = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/SubHeroSelector"
	) as OptionButton
	_main_heading_label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Cards/MainCard/Margin/Layout/HeadingLabel"
	) as Label
	_main_detail_label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Cards/MainCard/Margin/Layout/DetailLabel"
	) as Label
	_sub_heading_label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Cards/SubCard/Margin/Layout/HeadingLabel"
	) as Label
	_sub_detail_label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Cards/SubCard/Margin/Layout/DetailLabel"
	) as Label
	_hint_label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/HintLabel"
	) as Label
	_confirm_button = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Actions/ConfirmButton"
	) as Button
	_cancel_button = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Actions/CancelButton"
	) as Button
	_swap_button = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Actions/SwapButton"
	) as Button
	if (
		_title_label == null
		or _main_selector == null
		or _sub_selector == null
		or _main_heading_label == null
		or _main_detail_label == null
		or _sub_heading_label == null
		or _sub_detail_label == null
		or _hint_label == null
		or _confirm_button == null
		or _cancel_button == null
		or _swap_button == null
	):
		push_error("[HeroCompositionPanel] missing required scene nodes")
		return
	_main_selector.item_selected.connect(_on_selection_changed)
	_sub_selector.item_selected.connect(_on_selection_changed)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	_swap_button.pressed.connect(_on_swap_pressed)
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	_refresh_texts()
	_rebuild_selectors("", "")


func _exit_tree() -> void:
	if Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.disconnect(_on_locale_changed)


func configure(
	hero_rows: Array[Dictionary],
	last_main_hero_id: String,
	last_sub_hero_id: String
) -> void:
	_hero_rows = []
	for row: Dictionary in hero_rows:
		if not bool(row.get("default_unlocked", true)):
			continue
		var hero_id: String = String(row.get("id", ""))
		if hero_id.is_empty():
			continue
		_hero_rows.append(row.duplicate(true))
	if _main_selector == null or _sub_selector == null:
		return
	_rebuild_selectors(last_main_hero_id, last_sub_hero_id)


func selected_main_hero_id() -> String:
	return _selected_hero_id(_main_selector)


func selected_sub_hero_id() -> String:
	return _selected_hero_id(_sub_selector)


func grab_default_focus() -> void:
	if _main_selector != null:
		UIManager.grab_focus_for_navigation(_main_selector)


func request_close() -> void:
	cancel_requested.emit()


func _rebuild_selectors(last_main_hero_id: String, last_sub_hero_id: String) -> void:
	if _main_selector == null or _sub_selector == null:
		return
	_main_selector.clear()
	_sub_selector.clear()
	for row: Dictionary in _hero_rows:
		var hero_id: String = String(row.get("id", ""))
		var display_name: String = tr(String(row.get("name_key", hero_id)))
		_main_selector.add_item(display_name)
		_main_selector.set_item_metadata(_main_selector.item_count - 1, hero_id)
		_sub_selector.add_item(display_name)
		_sub_selector.set_item_metadata(_sub_selector.item_count - 1, hero_id)
	if _hero_rows.is_empty():
		_refresh_selection_state()
		return
	var main_index: int = _find_hero_index(last_main_hero_id)
	if main_index < 0:
		main_index = 0
	var sub_index: int = _find_hero_index(last_sub_hero_id)
	if sub_index < 0:
		sub_index = 1 if _hero_rows.size() > 1 else 0
	_main_selector.select(main_index)
	_sub_selector.select(sub_index)
	_refresh_selection_state()


func _find_hero_index(hero_id: String) -> int:
	for index: int in range(_hero_rows.size()):
		if String(_hero_rows[index].get("id", "")) == hero_id:
			return index
	return -1


func _selected_hero_id(selector: OptionButton) -> String:
	if selector == null or selector.selected < 0:
		return ""
	return String(selector.get_item_metadata(selector.selected))


func _selected_hero_row(selector: OptionButton) -> Dictionary:
	var hero_id: String = _selected_hero_id(selector)
	for row: Dictionary in _hero_rows:
		if String(row.get("id", "")) == hero_id:
			return row
	return {}


func _refresh_texts() -> void:
	if _title_label != null:
		_title_label.text = tr("ui_hero_composition_title")
	if _main_heading_label != null:
		_main_heading_label.text = tr("ui_hero_composition_main")
	if _sub_heading_label != null:
		_sub_heading_label.text = tr("ui_hero_composition_sub")
	if _confirm_button != null:
		_confirm_button.text = tr("ui_confirm")
	if _cancel_button != null:
		_cancel_button.text = tr("ui_cancel")
	if _swap_button != null:
		_swap_button.text = tr("ui_hero_composition_swap")
	_refresh_selector_item_texts(_main_selector)
	_refresh_selector_item_texts(_sub_selector)
	_refresh_selection_state()


func _refresh_selector_item_texts(selector: OptionButton) -> void:
	if selector == null:
		return
	for index: int in range(selector.item_count):
		var hero_id: String = String(selector.get_item_metadata(index))
		for row: Dictionary in _hero_rows:
			if String(row.get("id", "")) == hero_id:
				selector.set_item_text(index, tr(String(row.get("name_key", hero_id))))
				break


func _refresh_selection_state() -> void:
	var main_id: String = selected_main_hero_id()
	var sub_id: String = selected_sub_hero_id()
	_refresh_duplicate_option_states(main_id, sub_id)
	if _confirm_button != null:
		_confirm_button.disabled = main_id.is_empty() or sub_id.is_empty() or main_id == sub_id
	var main_row: Dictionary = _selected_hero_row(_main_selector)
	var sub_row: Dictionary = _selected_hero_row(_sub_selector)
	var ability_stats: Dictionary = (
		main_row.get("base_stats", {}) as Dictionary
	)
	if _main_detail_label != null:
		_main_detail_label.text = _hero_detail(
			main_row,
			true,
			ability_stats
		)
	if _sub_detail_label != null:
		_sub_detail_label.text = _hero_detail(
			sub_row,
			false,
			ability_stats
		)
	if _hint_label != null:
		_hint_label.text = tr("ui_hero_composition_duplicate_hint")


func _refresh_duplicate_option_states(
	main_id: String,
	sub_id: String
) -> void:
	for index: int in range(_main_selector.item_count):
		_main_selector.set_item_disabled(
			index,
			String(_main_selector.get_item_metadata(index)) == sub_id
		)
	for index: int in range(_sub_selector.item_count):
		_sub_selector.set_item_disabled(
			index,
			String(_sub_selector.get_item_metadata(index)) == main_id
		)


func _hero_detail(
	row: Dictionary,
	is_main: bool,
	ability_stats: Dictionary
) -> String:
	if row.is_empty():
		return "—"
	var lines: PackedStringArray = [
		tr(String(row.get("name_key", ""))),
		tr(String(row.get("desc_key", ""))),
		"",
	]
	var skills: Array = row.get("hero_skill_ids", []) as Array
	if is_main:
		var stats: Dictionary = row.get("base_stats", {}) as Dictionary
		lines.append("%s %d  ·  %s %d  ·  %s %d" % [
			tr("ui_stats_life"),
			int(stats.get("max_hp", 0)),
			tr("ui_stats_shield"),
			int(stats.get("max_shield", 0)),
			tr("ui_stats_energy"),
			int(stats.get("max_energy", 0)),
		])
		lines.append("%s %d  ·  %s %d" % [
			tr("ui_stats_move_speed"),
			int(stats.get("move_speed", 0)),
			tr("ui_stats_armor"),
			int(stats.get("armor", 0)),
		])
		lines.append("%s %d%%  ·  %s %d%%" % [
			tr("ui_stats_ability_strength"),
			int(roundf(float(stats.get("ability_strength", 1.0)) * 100.0)),
			tr("ui_stats_ability_range"),
			int(roundf(float(stats.get("ability_range", 1.0)) * 100.0)),
		])
		lines.append("%s %d%%  ·  %s %d%%" % [
			tr("ui_stats_ability_efficiency"),
			int(roundf(float(stats.get("ability_efficiency", 1.0)) * 100.0)),
			tr("ui_stats_ability_duration"),
			int(roundf(float(stats.get("ability_duration", 1.0)) * 100.0)),
		])
		var passive: Dictionary = _definition_by_id(
			DataLoader.HERO_PASSIVES_PATH,
			"passives",
			String(row.get("passive_id", ""))
		)
		lines.append("")
		lines.append("%s：%s" % [
			tr("ui_hero_composition_passive"),
			tr(String(passive.get("name_key", ""))),
		])
		lines.append(
			SKILL_DESCRIPTION_FORMATTER.format_passive(
				tr(String(passive.get("desc_key", ""))),
				passive
			)
		)
		lines.append("")
		lines.append(_skill_line(1, skills, 0, ability_stats))
		lines.append(_skill_line(2, skills, 1, ability_stats))
	else:
		lines.append(tr("ui_hero_composition_sub_note"))
		lines.append("")
		lines.append(_skill_line(3, skills, 0, ability_stats))
		lines.append(_skill_line(4, skills, 1, ability_stats))
	return "\n".join(lines)


func _skill_line(
	slot_number: int,
	skills: Array,
	index: int,
	ability_stats: Dictionary
) -> String:
	if index < 0 or index >= skills.size():
		return ""
	var skill: Dictionary = _definition_by_id(
		DataLoader.SKILLS_PATH,
		"skills",
		String(skills[index])
	)
	var heading: String = "%s %d：%s" % [
		tr("ui_hero_composition_skill"),
		slot_number,
		tr(String(skill.get("name_key", ""))),
	]
	var description: String = SKILL_DESCRIPTION_FORMATTER.format_skill(
		tr(String(skill.get("desc_key", ""))),
		skill,
		ability_stats
	)
	return "%s\n%s" % [heading, description]


func _definition_by_id(
	path: String,
	array_key: String,
	requested_id: String
) -> Dictionary:
	var payload: Variant = DataLoader.load_json(path)
	if not payload is Dictionary:
		return {}
	for raw_entry: Variant in (payload as Dictionary).get(array_key, []):
		if (
			raw_entry is Dictionary
			and String((raw_entry as Dictionary).get("id", ""))
			== requested_id
		):
			return (raw_entry as Dictionary).duplicate(true)
	return {}


func _on_selection_changed(_index: int) -> void:
	_refresh_selection_state()


func _on_confirm_pressed() -> void:
	var main_id: String = selected_main_hero_id()
	var sub_id: String = selected_sub_hero_id()
	if main_id.is_empty() or sub_id.is_empty() or main_id == sub_id:
		return
	composition_confirmed.emit(main_id, sub_id)


func _on_cancel_pressed() -> void:
	cancel_requested.emit()


func _on_swap_pressed() -> void:
	var main_index: int = _main_selector.selected
	var sub_index: int = _sub_selector.selected
	if main_index < 0 or sub_index < 0:
		return
	_main_selector.select(sub_index)
	_sub_selector.select(main_index)
	_refresh_selection_state()


func _on_locale_changed(_locale: String) -> void:
	_refresh_texts()
