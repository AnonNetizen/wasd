# Doc: docs/代码/gear_mod_system.md
# Authority: docs/游戏设计文档.md §7.2 / §9.16
class_name GearModBoardPanel
extends CanvasLayer


signal placement_confirmed(instance_id: int, mod_id: String, coord: Vector2i)
signal placement_cancelled(instance_id: int, mod_id: String)
signal inspect_closed()

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const GEAR_MOD_COMPONENT_TYPES := preload(
	"res://scripts/contracts/gear_mod_component_types.gd"
)
const MODE_INSPECT: StringName = &"inspect"
const MODE_PLACEMENT: StringName = &"placement"
const BOARD_SIZE: int = 7
const INVALID_COORD := Vector2i(-1, -1)

var pauses_game: bool = false
var _mode: StringName = MODE_INSPECT
var _board_snapshot: Dictionary = {}
var _map_snapshot: Dictionary = {}
var _stats_snapshot: Dictionary = {}
var _passive: Dictionary = {}
var _pending: Dictionary = {}
var _legal_targets: Array[Vector2i] = []
var _selected: Vector2i = Vector2i(3, 3)
var _closed_requested: bool = false
var _commit_requested: bool = false

@onready var _title_label: Label = get_node("Root/Center/Panel/Margin/Layout/Header/TitleLabel") as Label
@onready var _board_page_button: Button = get_node("Root/Center/Panel/Margin/Layout/Header/BoardPageButton") as Button
@onready var _attributes_page_button: Button = get_node("Root/Center/Panel/Margin/Layout/Header/AttributesPageButton") as Button
@onready var _board_page: Control = get_node("Root/Center/Panel/Margin/Layout/BoardPage") as Control
@onready var _attributes_page: Control = get_node("Root/Center/Panel/Margin/Layout/AttributesPage") as Control
@onready var _map_grid: GearModGridView = get_node("Root/Center/Panel/Margin/Layout/BoardPage/Boards/MapColumn/MapGrid") as GearModGridView
@onready var _mod_grid: GearModGridView = get_node("Root/Center/Panel/Margin/Layout/BoardPage/Boards/ModColumn/ModGrid") as GearModGridView
@onready var _map_title_label: Label = get_node("Root/Center/Panel/Margin/Layout/BoardPage/Boards/MapColumn/MapTitle") as Label
@onready var _mod_title_label: Label = get_node("Root/Center/Panel/Margin/Layout/BoardPage/Boards/ModColumn/ModTitle") as Label
@onready var _detail_name_label: Label = get_node("Root/Center/Panel/Margin/Layout/BoardPage/Detail/NameLabel") as Label
@onready var _detail_type_label: Label = get_node("Root/Center/Panel/Margin/Layout/BoardPage/Detail/TypeLabel") as Label
@onready var _detail_desc_label: Label = get_node("Root/Center/Panel/Margin/Layout/BoardPage/Detail/DescLabel") as Label
@onready var _detail_effect_label: Label = get_node("Root/Center/Panel/Margin/Layout/BoardPage/Detail/EffectLabel") as Label
@onready var _attributes_label: RichTextLabel = get_node("Root/Center/Panel/Margin/Layout/AttributesPage/AttributesLabel") as RichTextLabel
@onready var _hint_label: Label = get_node("Root/Center/Panel/Margin/Layout/Footer/HintLabel") as Label
@onready var _confirm_button: Button = get_node("Root/Center/Panel/Margin/Layout/Footer/ConfirmButton") as Button
@onready var _cancel_button: Button = get_node("Root/Center/Panel/Margin/Layout/Footer/CancelButton") as Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InputService.begin_non_pausing_ui_capture(self)
	_map_grid.cell_selected.connect(_on_cell_selected)
	_mod_grid.cell_selected.connect(_on_cell_selected)
	_board_page_button.pressed.connect(_show_board_page)
	_attributes_page_button.pressed.connect(_show_attributes_page)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_cancel_button.pressed.connect(request_close)
	if not InputService.action_pressed.is_connected(_on_action_pressed):
		InputService.action_pressed.connect(_on_action_pressed)
	if not InputService.action_released.is_connected(_on_action_released):
		InputService.action_released.connect(_on_action_released)
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	_show_board_page()
	_refresh()


func _exit_tree() -> void:
	InputService.end_non_pausing_ui_capture(self)
	if InputService.action_pressed.is_connected(_on_action_pressed):
		InputService.action_pressed.disconnect(_on_action_pressed)
	if InputService.action_released.is_connected(_on_action_released):
		InputService.action_released.disconnect(_on_action_released)
	if Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.disconnect(_on_locale_changed)


func configure_inspect(
		board_snapshot: Dictionary,
		map_snapshot: Dictionary,
		stats_snapshot: Dictionary,
		passive: Dictionary
	) -> void:
	_mode = MODE_INSPECT
	_board_snapshot = board_snapshot.duplicate(true)
	_map_snapshot = map_snapshot.duplicate(true)
	_stats_snapshot = stats_snapshot.duplicate(true)
	_passive = passive.duplicate(true)
	_pending.clear()
	_legal_targets.clear()
	_selected = _current_map_coord()
	if not _coord_is_valid(_selected):
		_selected = _board_center()
	_refresh()


func configure_placement(
		board_snapshot: Dictionary,
		map_snapshot: Dictionary,
		stats_snapshot: Dictionary,
		passive: Dictionary,
		pending: Dictionary
	) -> void:
	_mode = MODE_PLACEMENT
	_board_snapshot = board_snapshot.duplicate(true)
	_map_snapshot = map_snapshot.duplicate(true)
	_stats_snapshot = stats_snapshot.duplicate(true)
	_passive = passive.duplicate(true)
	_pending = pending.duplicate(true)
	_legal_targets = _coord_array(_pending.get("legal_targets", []))
	var preferred: Vector2i = _coord_from_variant(
		_pending.get("default_target", _current_map_coord())
	)
	_selected = _nearest_legal_coord(preferred)
	_refresh()


func request_close() -> void:
	if _closed_requested:
		return
	_closed_requested = true
	if _mode == MODE_PLACEMENT:
		placement_cancelled.emit(
			int(_pending.get("instance_id", 0)),
			String(_pending.get("mod_id", ""))
		)
	else:
		inspect_closed.emit()
	UIManager.pop_expected(self)


func close_after_commit() -> void:
	if _closed_requested:
		return
	_closed_requested = true
	UIManager.pop_expected(self)


func grab_default_focus() -> void:
	if _mode == MODE_PLACEMENT and not _confirm_button.disabled:
		_confirm_button.grab_focus()
	else:
		_board_page_button.grab_focus()


func selected_coord() -> Vector2i:
	return _selected


func placement_mode() -> bool:
	return _mode == MODE_PLACEMENT


func _on_action_pressed(action_id: StringName, participant_id: String) -> void:
	if participant_id != InputService.DEFAULT_PARTICIPANT_ID or _closed_requested:
		return
	var delta := Vector2i.ZERO
	match String(action_id):
		ACTIONS.UI_UP:
			delta = Vector2i.UP
		ACTIONS.UI_DOWN:
			delta = Vector2i.DOWN
		ACTIONS.UI_LEFT:
			delta = Vector2i.LEFT
		ACTIONS.UI_RIGHT:
			delta = Vector2i.RIGHT
		ACTIONS.UI_CONFIRM:
			if _mode == MODE_PLACEMENT and _board_page.visible:
				_on_confirm_pressed()
			return
	if delta != Vector2i.ZERO and _board_page.visible:
		_set_selected(_selected + delta)


func _on_action_released(action_id: StringName, participant_id: String) -> void:
	if participant_id != InputService.DEFAULT_PARTICIPANT_ID:
		return
	if _mode == MODE_INSPECT and String(action_id) == ACTIONS.SHOW_STATS_PANEL:
		request_close()


func _on_cell_selected(coord: Vector2i) -> void:
	_set_selected(coord)


func _set_selected(coord: Vector2i) -> void:
	_selected = Vector2i(
		clampi(coord.x, 0, BOARD_SIZE - 1),
		clampi(coord.y, 0, BOARD_SIZE - 1)
	)
	_map_grid.set_selected(_selected)
	_mod_grid.set_selected(_selected)
	_refresh_detail()
	_refresh_footer()


func _show_board_page() -> void:
	_board_page.show()
	_attributes_page.hide()
	_board_page_button.button_pressed = true
	_attributes_page_button.button_pressed = false
	_refresh_footer()


func _show_attributes_page() -> void:
	_board_page.hide()
	_attributes_page.show()
	_board_page_button.button_pressed = false
	_attributes_page_button.button_pressed = true
	_refresh_footer()


func _on_confirm_pressed() -> void:
	if (
		_mode != MODE_PLACEMENT
		or _commit_requested
		or _closed_requested
		or not _legal_targets.has(_selected)
	):
		return
	_commit_requested = true
	_confirm_button.disabled = true
	placement_confirmed.emit(
		int(_pending.get("instance_id", 0)),
		String(_pending.get("mod_id", "")),
		_selected
	)


func _refresh() -> void:
	if not is_node_ready():
		return
	_refresh_static_text()
	_map_grid.configure_map(_map_snapshot, _selected)
	_mod_grid.configure_board(_board_snapshot, _selected, _legal_targets)
	_refresh_detail()
	_refresh_attributes()
	_refresh_footer()


func _refresh_static_text() -> void:
	_title_label.text = tr(
		"ui_gear_mod_board_place_title"
		if _mode == MODE_PLACEMENT
		else "ui_gear_mod_board_title"
	)
	_board_page_button.text = tr("ui_gear_mod_board_page")
	_attributes_page_button.text = tr("ui_gear_mod_attributes_page")
	_map_title_label.text = tr("ui_gear_mod_board_map_title")
	_mod_title_label.text = tr("ui_gear_mod_board_mod_title")
	_confirm_button.text = tr("ui_confirm")
	_cancel_button.text = tr("ui_cancel")


func _refresh_detail() -> void:
	var definition: Dictionary = _definition_at_selected_coord()
	var is_core: bool = _selected == _board_center()
	_detail_name_label.text = tr("ui_gear_mod_board_empty")
	_detail_type_label.text = tr("ui_gear_mod_board_coord").format({
		"x": _selected.x,
		"y": _selected.y,
	})
	_detail_desc_label.text = ""
	_detail_effect_label.text = ""
	if is_core:
		var passive_name_key: String = String(_passive.get("name_key", ""))
		var passive_desc_key: String = String(_passive.get("desc_key", ""))
		_detail_name_label.text = (
			tr(passive_name_key)
			if not passive_name_key.is_empty()
			else tr("ui_gear_mod_board_core")
		)
		_detail_type_label.text = "%s · %s" % [
			tr("ui_gear_mod_board_core_type"),
			tr("ui_gear_mod_board_coord").format({"x": _selected.x, "y": _selected.y}),
		]
		_detail_desc_label.text = tr(passive_desc_key) if not passive_desc_key.is_empty() else ""
		_detail_effect_label.text = tr("ui_gear_mod_board_core_chain_hint")
		return
	if definition.is_empty():
		if _legal_targets.has(_selected) and _mode == MODE_PLACEMENT:
			definition = GearModSystem.mod_definition(String(_pending.get("mod_id", "")))
		else:
			return
	var name_key: String = String(definition.get("name_key", ""))
	var desc_key: String = String(definition.get("desc_key", ""))
	var type_names: PackedStringArray = []
	for component_type: String in _component_types(definition):
		type_names.append(tr("ui_gear_mod_component_%s" % component_type))
	_detail_name_label.text = tr(name_key) if not name_key.is_empty() else String(definition.get("id", ""))
	_detail_type_label.text = "%s · %s" % [
		" + ".join(type_names),
		tr("ui_gear_mod_board_coord").format({"x": _selected.x, "y": _selected.y}),
	]
	_detail_desc_label.text = tr(desc_key) if not desc_key.is_empty() else ""
	_detail_effect_label.text = _definition_effect_text(definition)


func _refresh_attributes() -> void:
	var keys: Array[String] = []
	for raw_key: Variant in _stats_snapshot.keys():
		keys.append(String(raw_key))
	keys.sort()
	var lines: PackedStringArray = []
	for key: String in keys:
		var label_key: String = "ui_stats_%s" % key
		var label: String = tr(label_key)
		if label == label_key:
			label = key.capitalize()
		lines.append("[b]%s[/b]  %s" % [label, String(_stats_snapshot.get(key, "—"))])
	_attributes_label.text = "\n".join(lines)


func _refresh_footer() -> void:
	_confirm_button.visible = _mode == MODE_PLACEMENT and _board_page.visible
	_cancel_button.visible = _mode == MODE_PLACEMENT
	_confirm_button.disabled = (
		_commit_requested
		or not _legal_targets.has(_selected)
	)
	if _mode == MODE_PLACEMENT:
		_hint_label.text = (
			tr("ui_gear_mod_board_place_legal")
			if _legal_targets.has(_selected)
			else tr("ui_gear_mod_board_place_illegal")
		)
	else:
		_hint_label.text = tr("ui_gear_mod_board_hold_hint")


func _definition_at_selected_coord() -> Dictionary:
	for raw_placement: Variant in _board_snapshot.get("placements", []):
		if raw_placement is not Dictionary:
			continue
		var placement: Dictionary = raw_placement as Dictionary
		if _coord_from_variant(placement) == _selected:
			return GearModSystem.mod_definition(String(placement.get("mod_id", "")))
	return {}


func _definition_effect_text(definition: Dictionary) -> String:
	var lines: PackedStringArray = []
	for raw_component: Variant in definition.get("components", []):
		if raw_component is not Dictionary:
			continue
		var component: Dictionary = raw_component as Dictionary
		var component_type: String = String(component.get("type", ""))
		if component_type == GEAR_MOD_COMPONENT_TYPES.MODIFIER:
			for raw_modifier: Variant in component.get("modifiers", []):
				if raw_modifier is not Dictionary:
					continue
				var modifier: Dictionary = raw_modifier as Dictionary
				var stat: String = String(modifier.get("stat", ""))
				var modifier_type: String = String(modifier.get("type", ""))
				var value: float = float(modifier.get("value", 0.0))
				var value_text: String = (
					"×%.2f" % value
					if modifier_type == "mult"
					else "%+.2f" % value
				)
				lines.append(
					"%s  %s" % [tr("ui_stats_%s" % stat), value_text]
				)
		elif component_type == GEAR_MOD_COMPONENT_TYPES.PROGRAM:
			lines.append(tr("ui_gear_mod_board_behavior_active"))
		elif component_type == GEAR_MOD_COMPONENT_TYPES.BOARD_RULE:
			lines.append(tr("ui_gear_mod_board_occupy_only"))
	return "\n".join(lines)


func _component_types(definition: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw_component: Variant in definition.get("components", []):
		if raw_component is not Dictionary:
			continue
		var component_type: String = String(
			(raw_component as Dictionary).get("type", "")
		)
		if (
			GEAR_MOD_COMPONENT_TYPES.VALUES.has(component_type)
			and not result.has(component_type)
		):
			result.append(component_type)
	return result


func _nearest_legal_coord(origin: Vector2i) -> Vector2i:
	if _legal_targets.is_empty():
		return _board_center()
	var best: Vector2i = _legal_targets[0]
	var best_distance: int = _manhattan_distance(origin, best)
	for coord: Vector2i in _legal_targets:
		var distance: int = _manhattan_distance(origin, coord)
		if distance < best_distance or (
			distance == best_distance
			and (coord.y < best.y or (coord.y == best.y and coord.x < best.x))
		):
			best = coord
			best_distance = distance
	return best


func _current_map_coord() -> Vector2i:
	return _coord_from_variant(
		_map_snapshot.get("current_slot", _map_snapshot.get("current_module", {}))
	)


func _board_center() -> Vector2i:
	var center: Vector2i = _coord_from_variant(_board_snapshot.get("center", {}))
	return center if _coord_is_valid(center) else Vector2i(3, 3)


func _coord_array(value: Variant) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if value is not Array:
		return result
	for raw_coord: Variant in value as Array:
		var coord: Vector2i = _coord_from_variant(raw_coord)
		if _coord_is_valid(coord) and not result.has(coord):
			result.append(coord)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return result


func _coord_from_variant(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value as Vector2i
	if value is Vector2:
		var vector: Vector2 = value as Vector2
		return Vector2i(int(vector.x), int(vector.y))
	if value is Dictionary:
		var data: Dictionary = value as Dictionary
		return Vector2i(int(data.get("x", -1)), int(data.get("y", -1)))
	if value is Array:
		var parts: Array = value as Array
		if parts.size() == 2:
			return Vector2i(int(parts[0]), int(parts[1]))
	return INVALID_COORD


func _coord_is_valid(coord: Vector2i) -> bool:
	return coord.x >= 0 and coord.x < BOARD_SIZE and coord.y >= 0 and coord.y < BOARD_SIZE


func _manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _on_locale_changed(_locale_code: String) -> void:
	_refresh()
