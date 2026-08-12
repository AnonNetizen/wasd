# Doc: docs/代码/gameplay_runtime.md
# Authority: docs/游戏设计文档.md §5, docs/决策记录.md ADR #199 / #201
class_name TeleportChoicePanel
extends CanvasLayer


signal destination_selected(station_id: String)
signal cancelled()
signal pause_requested()

const ACTIONS := preload("res://scripts/contracts/actions.gd")
const DESTINATION_BUTTON_SCENE: PackedScene = preload(
	"res://scenes/ui/teleport_destination_button.tscn"
)
const INPUT_PARTICIPANT_ID: String = "player_0"

@export var modal: bool = true
@export var pauses_game: bool = false
@export_range(0.0, 1.0, 0.05) var music_duck: float = 0.0

var _buttons: Array[Button] = []
var _destinations: Array[Dictionary] = []
var _input_locked: bool = false
var _message_key: String = "ui_teleport_choice_desc"
var _source_station_id: String = ""
var _stations: Array[Dictionary] = []

@onready var _cancel_button: Button = get_node_or_null(
	"Root/Center/TeleportChoicePanelFrame/Margin/Layout/CancelButton"
) as Button
@onready var _destination_box: VBoxContainer = get_node_or_null(
	"Root/Center/TeleportChoicePanelFrame/Margin/Layout/DestinationBox"
) as VBoxContainer
@onready var _description_label: Label = get_node_or_null(
	"Root/Center/TeleportChoicePanelFrame/Margin/Layout/DescriptionLabel"
) as Label
@onready var _minimap: Control = get_node_or_null(
	"Root/Center/TeleportChoicePanelFrame/Margin/Layout/Minimap"
) as Control
@onready var _title_label: Label = get_node_or_null(
	"Root/Center/TeleportChoicePanelFrame/Margin/Layout/TitleLabel"
) as Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InputService.begin_non_pausing_ui_capture(
		self,
		[StringName(ACTIONS.PAUSE)]
	)
	if (
		_cancel_button == null
		or _destination_box == null
		or _description_label == null
		or _minimap == null
		or _title_label == null
	):
		push_error("[TeleportChoicePanel] missing required scene nodes")
		return
	_cancel_button.pressed.connect(request_close)
	if not InputService.action_pressed.is_connected(_on_input_action_pressed):
		InputService.action_pressed.connect(_on_input_action_pressed)
	if not Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.connect(_on_locale_changed)
	refresh_texts()


func _exit_tree() -> void:
	InputService.end_non_pausing_ui_capture(self)
	if InputService.action_pressed.is_connected(_on_input_action_pressed):
		InputService.action_pressed.disconnect(_on_input_action_pressed)
	if Localization.locale_changed.is_connected(_on_locale_changed):
		Localization.locale_changed.disconnect(_on_locale_changed)


func configure(source_station_id: String, stations: Array[Dictionary]) -> bool:
	_source_station_id = source_station_id
	_stations = _validated_stations(stations)
	_destinations.clear()
	var source_found: bool = false
	for station: Dictionary in _stations:
		var station_id: String = String(station.get("station_id", ""))
		var is_current: bool = bool(station.get("is_current", false))
		if station_id == _source_station_id and is_current:
			source_found = true
		if station_id != _source_station_id and not is_current:
			_destinations.append(station.duplicate(true))
	_destinations.sort_custom(_sort_by_station_number)
	if _minimap != null:
		_minimap.call("configure", _source_station_id, _stations)
	_refresh_buttons()
	return source_found and not _destinations.is_empty()


func set_input_locked(locked: bool) -> void:
	_input_locked = locked
	for button: Button in _buttons:
		button.disabled = locked
	if _cancel_button != null:
		_cancel_button.disabled = locked


func show_feedback(message_key: String) -> void:
	_message_key = (
		message_key
		if not message_key.is_empty()
		else "ui_teleport_choice_desc"
	)
	if _description_label != null:
		_description_label.text = tr(_message_key)


func request_close() -> void:
	if _input_locked:
		return
	_input_locked = true
	cancelled.emit()


func grab_default_focus() -> void:
	for button: Button in _buttons:
		if not button.disabled and button.visible:
			button.grab_focus()
			return
	if _cancel_button != null and not _cancel_button.disabled:
		_cancel_button.grab_focus()


func destination_ids() -> Array[String]:
	var ids: Array[String] = []
	for station: Dictionary in _destinations:
		ids.append(String(station.get("station_id", "")))
	return ids


func minimap_station_ids() -> Array[String]:
	var ids: Array[String] = []
	if _minimap == null:
		return ids
	for raw_id: Variant in _minimap.call("station_ids") as Array:
		ids.append(String(raw_id))
	return ids


func refresh_texts() -> void:
	if _title_label != null:
		_title_label.text = tr("ui_teleport_choice_title")
	if _description_label != null:
		_description_label.text = tr(_message_key)
	if _cancel_button != null:
		_cancel_button.text = tr("ui_cancel")
	_refresh_button_texts()


func _refresh_buttons() -> void:
	if _destination_box == null:
		return
	_buttons.clear()
	for child: Node in _destination_box.get_children():
		child.queue_free()
	for index: int in range(_destinations.size()):
		var button: Button = DESTINATION_BUTTON_SCENE.instantiate() as Button
		if button == null:
			push_error("[TeleportChoicePanel] failed to instantiate destination button")
			continue
		button.pressed.connect(Callable(self, "_on_destination_pressed").bind(index))
		button.focus_entered.connect(Callable(self, "_on_destination_highlighted").bind(index))
		button.mouse_entered.connect(Callable(self, "_on_destination_highlighted").bind(index))
		button.disabled = _input_locked
		_buttons.append(button)
		_destination_box.add_child(button)
	_refresh_button_texts()
	var feedback: UIButtonFeedback = get_node_or_null(
		"UIEffects/ButtonFeedback"
	) as UIButtonFeedback
	if feedback != null:
		feedback.call_deferred("refresh_bindings")


func _refresh_button_texts() -> void:
	for index: int in range(mini(_buttons.size(), _destinations.size())):
		var station: Dictionary = _destinations[index]
		_buttons[index].text = tr("ui_teleport_station_format").format({
			"number": int(station.get("station_number", index + 1)),
		})


func _on_destination_pressed(index: int) -> void:
	if _input_locked or index < 0 or index >= _destinations.size():
		return
	var station_id: String = String(_destinations[index].get("station_id", ""))
	if station_id.is_empty():
		return
	destination_selected.emit(station_id)


func _on_destination_highlighted(index: int) -> void:
	if _minimap == null or index < 0 or index >= _destinations.size():
		return
	_minimap.call(
		"set_selected_station",
		String(_destinations[index].get("station_id", ""))
	)


func _on_input_action_pressed(action_id: StringName, participant_id: String) -> void:
	if (
		_input_locked
		or participant_id != INPUT_PARTICIPANT_ID
		or action_id != StringName(ACTIONS.PAUSE)
	):
		return
	if UIManager.top() == self:
		pause_requested.emit()


func _on_locale_changed(_locale: String) -> void:
	refresh_texts()


func _validated_stations(stations: Array[Dictionary]) -> Array[Dictionary]:
	var validated: Array[Dictionary] = []
	var seen_ids: Dictionary = {}
	for station: Dictionary in stations:
		var station_id: String = String(station.get("station_id", ""))
		var station_number: int = int(station.get("station_number", 0))
		var raw_coord: Variant = station.get("module_coord", {})
		if (
			station_id.is_empty()
			or station_number <= 0
			or station_number > 3
			or seen_ids.has(station_id)
			or not raw_coord is Dictionary
		):
			continue
		var module_coord: Dictionary = raw_coord as Dictionary
		var module_x: int = int(module_coord.get("x", -1))
		var module_y: int = int(module_coord.get("y", -1))
		if module_x < 0 or module_x >= 7 or module_y < 0 or module_y >= 7:
			continue
		seen_ids[station_id] = true
		validated.append(station.duplicate(true))
	return validated


func _sort_by_station_number(left: Dictionary, right: Dictionary) -> bool:
	var left_number: int = int(left.get("station_number", 0))
	var right_number: int = int(right.get("station_number", 0))
	if left_number != right_number:
		return left_number < right_number
	return String(left.get("station_id", "")) < String(right.get("station_id", ""))
