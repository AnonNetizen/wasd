# Doc: docs/代码/debug_test_arena.md
# Authority: docs/决策记录.md ADR #159 / #160
class_name DebugTestArenaSetup
extends CanvasLayer


signal closed_requested()
signal start_requested(config: Dictionary)

const CONFIG_SCRIPT := preload(
	"res://scripts/debug/debug_test_arena_config.gd"
)
const MOD_ROW_SCENE := preload(
	"res://scenes/debug/debug_test_arena_mod_row.tscn"
)

var _active_items_label: Label = null
var _character_option: OptionButton = null
var _config_manager: RefCounted = null
var _consumables_label: Label = null
var _content: Dictionary = {}
var _feedback_label: Label = null
var _gear_mod_capacity_label: Label = null
var _gear_mod_rows: Array[DebugTestArenaModRow] = []
var _mod_list: VBoxContainer = null
var _relics_label: Label = null
var _seed_spin: SpinBox = null
var _skill_option: OptionButton = null
var _start_button: Button = null
var _title_label: Label = null
var _weapon_option: OptionButton = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_title_label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/TitleLabel"
	) as Label
	_seed_spin = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Selectors/SeedSpin"
	) as SpinBox
	_character_option = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Selectors/CharacterOption"
	) as OptionButton
	_weapon_option = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Selectors/WeaponOption"
	) as OptionButton
	_skill_option = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Selectors/SkillOption"
	) as OptionButton
	_mod_list = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/ModSection/ModScroll/ModList"
	) as VBoxContainer
	_gear_mod_capacity_label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/ModSection/CapacityLabel"
	) as Label
	_relics_label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/UnavailableSection/RelicsLabel"
	) as Label
	_active_items_label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/UnavailableSection/ActiveItemsLabel"
	) as Label
	_consumables_label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/UnavailableSection/ConsumablesLabel"
	) as Label
	_feedback_label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/FeedbackLabel"
	) as Label
	_start_button = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Buttons/StartButton"
	) as Button
	var close_button: Button = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Buttons/CloseButton"
	) as Button
	if (
		_title_label == null
		or _seed_spin == null
		or _character_option == null
		or _weapon_option == null
		or _skill_option == null
		or _mod_list == null
		or _gear_mod_capacity_label == null
		or _relics_label == null
		or _active_items_label == null
		or _consumables_label == null
		or _feedback_label == null
		or _start_button == null
		or close_button == null
	):
		push_error("[DebugTestArenaSetup] missing required scene nodes")
		return
	_config_manager = CONFIG_SCRIPT.new()
	_content = _config_manager.call("available_content") as Dictionary
	_start_button.pressed.connect(_on_start_pressed)
	close_button.pressed.connect(request_close)
	_character_option.item_selected.connect(_on_selection_changed)
	_weapon_option.item_selected.connect(_on_selection_changed)
	_skill_option.item_selected.connect(_on_selection_changed)
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	configure(_config_manager.call("load_config") as Dictionary)


func _exit_tree() -> void:
	if Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.disconnect(_on_locale_changed)


func configure(config: Dictionary) -> void:
	if _config_manager == null:
		return
	var normalized: Dictionary = _config_manager.call(
		"normalize_config",
		config
	) as Dictionary
	_populate_option(
		_character_option,
		_typed_dictionary_array(_content.get("characters", [])),
		String(normalized.get("character_id", ""))
	)
	_populate_option(
		_weapon_option,
		_typed_dictionary_array(_content.get("weapons", [])),
		String(normalized.get("weapon_id", ""))
	)
	_populate_option(
		_skill_option,
		_typed_dictionary_array(_content.get("skills", [])),
		String(normalized.get("primary_skill_id", ""))
	)
	_seed_spin.value = float(int(normalized.get("seed", 1)))
	_rebuild_mod_rows(
		_typed_dictionary_array(normalized.get("gear_mods", []))
	)
	_refresh_unavailable_content()
	refresh_texts()
	_refresh_preview()


func request_close() -> void:
	closed_requested.emit()


func grab_default_focus() -> void:
	UIManager.grab_focus_for_navigation(_start_button)


func refresh_texts() -> void:
	if _title_label == null:
		return
	_title_label.text = tr("ui_debug_test_arena_setup_title")
	var seed_label: Label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Selectors/SeedLabel"
	) as Label
	var character_label: Label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Selectors/CharacterLabel"
	) as Label
	var weapon_label: Label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Selectors/WeaponLabel"
	) as Label
	var skill_label: Label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Selectors/SkillLabel"
	) as Label
	var mods_label: Label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/ModSection/ModsLabel"
	) as Label
	var unavailable_label: Label = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/UnavailableSection/UnavailableLabel"
	) as Label
	var close_button: Button = get_node_or_null(
		"Root/Center/Panel/Margin/Layout/Buttons/CloseButton"
	) as Button
	if seed_label != null:
		seed_label.text = tr("ui_debug_test_arena_seed")
	if character_label != null:
		character_label.text = tr("ui_debug_test_arena_character")
	if weapon_label != null:
		weapon_label.text = tr("ui_debug_test_arena_weapon")
	if skill_label != null:
		skill_label.text = tr("ui_debug_test_arena_primary_skill")
	if mods_label != null:
		mods_label.text = tr("ui_debug_test_arena_gear_mods")
	if unavailable_label != null:
		unavailable_label.text = tr(
			"ui_debug_test_arena_unavailable_title"
		)
	if _start_button != null:
		_start_button.text = tr("ui_debug_test_arena_enter")
	if close_button != null:
		close_button.text = tr("ui_debug_test_arena_exit")
	_refresh_option_texts(
		_character_option,
		_typed_dictionary_array(_content.get("characters", []))
	)
	_refresh_option_texts(
		_weapon_option,
		_typed_dictionary_array(_content.get("weapons", []))
	)
	_refresh_option_texts(
		_skill_option,
		_typed_dictionary_array(_content.get("skills", []))
	)
	for row: DebugTestArenaModRow in _gear_mod_rows:
		row.refresh_texts()
	_refresh_unavailable_content()
	_refresh_preview()


func debug_summary() -> Dictionary:
	return {
		"character_options": _character_option.item_count,
		"weapon_options": _weapon_option.item_count,
		"skill_options": _skill_option.item_count,
		"gear_mod_rows": _gear_mod_rows.size(),
		"relics_disabled": not _relics_label.text.is_empty(),
		"active_items_disabled": not _active_items_label.text.is_empty(),
		"consumables_disabled": not _consumables_label.text.is_empty(),
		"config": _build_config(),
	}


func _populate_option(
	option: OptionButton,
	items: Array[Dictionary],
	selected_id: String
) -> void:
	option.clear()
	for item: Dictionary in items:
		var item_id: String = String(item.get("id", ""))
		option.add_item(tr(String(item.get("name_key", item_id))))
		option.set_item_metadata(option.item_count - 1, item_id)
		if item_id == selected_id:
			option.select(option.item_count - 1)


func _refresh_option_texts(
	option: OptionButton,
	items: Array[Dictionary]
) -> void:
	for index: int in range(mini(option.item_count, items.size())):
		option.set_item_text(
			index,
			tr(String(items[index].get("name_key", "")))
		)


func _rebuild_mod_rows(selected_mods: Array[Dictionary]) -> void:
	for row: DebugTestArenaModRow in _gear_mod_rows:
		row.queue_free()
	_gear_mod_rows.clear()
	for definition: Dictionary in _typed_dictionary_array(
		_content.get("gear_mods", [])
	):
		var row: DebugTestArenaModRow = (
			MOD_ROW_SCENE.instantiate() as DebugTestArenaModRow
		)
		if row == null:
			continue
		_mod_list.add_child(row)
		_gear_mod_rows.append(row)
		var selected_rank: int = -1
		for selected: Dictionary in selected_mods:
			if (
				String(selected.get("mod_id", ""))
				== String(definition.get("id", ""))
			):
				selected_rank = int(selected.get("rank", 0))
				break
		row.configure(definition, selected_rank)
		row.selection_changed.connect(_refresh_preview)


func _refresh_unavailable_content() -> void:
	_relics_label.text = _unavailable_content_text(
		"ui_debug_test_arena_relics",
		_typed_dictionary_array(_content.get("relics", []))
	)
	_active_items_label.text = _unavailable_content_text(
		"ui_debug_test_arena_active_items",
		_typed_dictionary_array(_content.get("active_items", []))
	)
	_consumables_label.text = _unavailable_content_text(
		"ui_debug_test_arena_consumables",
		_typed_dictionary_array(_content.get("consumables", []))
	)


func _unavailable_content_text(
	category_key: String,
	items: Array[Dictionary]
) -> String:
	var names: Array[String] = []
	for item: Dictionary in items:
		names.append(tr(String(item.get("name_key", ""))))
	return "%s: %s — %s" % [
		tr(category_key),
		", ".join(names),
		tr("ui_debug_test_arena_runtime_unavailable"),
	]


func _build_config() -> Dictionary:
	var gear_mods: Array[Dictionary] = []
	for row: DebugTestArenaModRow in _gear_mod_rows:
		var selection: Dictionary = row.selection()
		if not selection.is_empty():
			gear_mods.append(selection)
	return {
		"schema_version": DebugTestArenaConfig.SCHEMA_VERSION,
		"seed": maxi(int(_seed_spin.value), 1),
		"character_id": _selected_id(_character_option),
		"weapon_id": _selected_id(_weapon_option),
		"primary_skill_id": _selected_id(_skill_option),
		"gear_mods": gear_mods,
	}


func _refresh_preview() -> void:
	if _config_manager == null:
		return
	var normalized: Dictionary = _config_manager.call(
		"normalize_config",
		_build_config()
	) as Dictionary
	var preview: Dictionary = normalized.get(
		"modifier_preview",
		{}
	) as Dictionary
	var used_drain: Dictionary = preview.get("used_drain", {}) as Dictionary
	_gear_mod_capacity_label.text = tr(
		"ui_debug_test_arena_capacity"
	) % [
		int(used_drain.get("hero", 0)),
		int(normalized.get("capacity", 8)),
		int(used_drain.get("weapon", 0)),
		int(normalized.get("capacity", 8)),
	]
	var diagnostics: Array[Dictionary] = _typed_dictionary_array(
		preview.get("diagnostics", [])
	)
	_start_button.disabled = _has_blocking_preview_diagnostic(diagnostics)
	_feedback_label.text = (
		tr("ui_debug_test_arena_loadout_invalid")
		if _start_button.disabled
		else tr("ui_debug_test_arena_loadout_ready")
	)


func _has_blocking_preview_diagnostic(
	diagnostics: Array[Dictionary]
) -> bool:
	for diagnostic: Dictionary in diagnostics:
		if String(diagnostic.get("reason", "")) in [
			"capacity_exceeded",
			"duplicate_unique_mod",
			"unknown_mod",
			"unknown_loadout_slot",
		]:
			return true
	return false


func _selected_id(option: OptionButton) -> String:
	if option.selected < 0:
		return ""
	return String(option.get_item_metadata(option.selected))


func _on_start_pressed() -> void:
	var saved: Dictionary = _config_manager.call(
		"save_config",
		_build_config()
	) as Dictionary
	if not bool(saved.get("saved", false)):
		_feedback_label.text = tr(
			"ui_debug_test_arena_config_save_failed"
		)
		return
	start_requested.emit(saved)


func _on_selection_changed(_index: int) -> void:
	_refresh_preview()


func _on_locale_changed(_locale: String) -> void:
	refresh_texts()


func _typed_dictionary_array(raw_value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not raw_value is Array:
		return result
	for item: Variant in raw_value as Array:
		if item is Dictionary:
			result.append((item as Dictionary).duplicate(true))
	return result
