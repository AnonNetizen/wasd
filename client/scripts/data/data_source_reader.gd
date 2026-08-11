# Doc: docs/代码/data_loader.md
# Authority: docs/决策记录.md ADR #197
class_name DataSourceReader
extends RefCounted
## Reads base JSON and CSV sources without applying overlays or reporting errors.


class JsonReadResult:
	extends RefCounted

	var ok: bool = false
	var data: Variant = {}
	var failure_field: String = ""
	var failure_expected: String = ""


class CsvReadResult:
	extends RefCounted

	var ok: bool = false
	var rows: Array[Dictionary] = []
	var failure_field: String = ""
	var failure_expected: String = ""


static func read_json(resource_path: String) -> JsonReadResult:
	var result: JsonReadResult = JsonReadResult.new()
	var file: FileAccess = FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		result.failure_field = "file"
		result.failure_expected = "readable JSON file"
		return result

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null:
		result.failure_field = "json"
		result.failure_expected = "valid JSON"
		return result

	result.ok = true
	result.data = parsed
	return result


static func read_csv(
	resource_path: String,
	has_header: bool = true
) -> CsvReadResult:
	var result: CsvReadResult = CsvReadResult.new()
	var file: FileAccess = FileAccess.open(resource_path, FileAccess.READ)
	if file == null:
		result.failure_field = "file"
		result.failure_expected = "readable CSV file"
		return result

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
				row[String(headers[index])] = (
					values[index] if index < values.size() else ""
				)
		else:
			for index: int in range(values.size()):
				row[String.num_int64(index)] = values[index]
		rows.append(row)

	result.ok = true
	result.rows = rows
	return result


static func _is_empty_csv_row(values: PackedStringArray) -> bool:
	return (
		values.size() == 0
		or (
			values.size() == 1
			and String(values[0]).strip_edges().is_empty()
		)
	)
