# Doc: docs/代码/data_loader.md
# Authority: docs/游戏设计文档.md §9.3, docs/词表与契约.md
extends Node
class_name DataLoaderAutoload


signal data_reloaded()

const CONTRACTS_PATH: String = "res://data/_contracts.json"
const DATA_ROOT: String = "res://data/"

var _contracts: Dictionary = {}


func _ready() -> void:
	reload_contracts()


func reload_contracts() -> void:
	var payload: Variant = load_json(CONTRACTS_PATH)
	if not payload is Dictionary:
		_fail(CONTRACTS_PATH, "root", "Dictionary")
		return

	var payload_dict: Dictionary = payload as Dictionary
	if not payload_dict.has("contracts") or not payload_dict["contracts"] is Dictionary:
		_fail(CONTRACTS_PATH, "contracts", "Dictionary")
		return

	_contracts = payload_dict["contracts"] as Dictionary
	data_reloaded.emit()


func contracts() -> Dictionary:
	return _contracts.duplicate(true)


func contract_values(contract_id: String) -> Array:
	if not _contracts.has(contract_id):
		_fail(CONTRACTS_PATH, "contracts.%s" % contract_id, "registered contract id")
		return []

	var values: Variant = _contracts[contract_id]
	if not values is Array:
		_fail(CONTRACTS_PATH, "contracts.%s" % contract_id, "Array")
		return []

	return values as Array


func has_contract_value(contract_id: String, value: String) -> bool:
	return contract_values(contract_id).has(value)


func load_json(resource_path: String) -> Variant:
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		_fail(resource_path, "file", "readable JSON file")
		return {}

	var text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		_fail(resource_path, "json", "valid JSON")
		return {}

	return parsed


func load_csv(resource_path: String, has_header: bool = true) -> Array[Dictionary]:
	var file := FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		_fail(resource_path, "file", "readable CSV file")
		return []

	var rows: Array[Dictionary] = []
	var headers: PackedStringArray = PackedStringArray()

	if has_header and not file.eof_reached():
		headers = file.get_csv_line()

	while not file.eof_reached():
		var values: PackedStringArray = file.get_csv_line()
		if _is_empty_csv_row(values):
			continue

		var row: Dictionary = {}
		if has_header:
			for index: int in range(headers.size()):
				row[String(headers[index])] = values[index] if index < values.size() else ""
		else:
			for index: int in range(values.size()):
				row[String.num_int64(index)] = values[index]
		rows.append(row)

	return rows


func data_path(file_name: String) -> String:
	return DATA_ROOT.path_join(file_name)


func _is_empty_csv_row(values: PackedStringArray) -> bool:
	return values.size() == 0 or (values.size() == 1 and String(values[0]).strip_edges().is_empty())


func _fail(resource_path: String, field_path: String, expected: String) -> void:
	push_error("[DataLoader] %s:%s expected %s" % [resource_path, field_path, expected])
