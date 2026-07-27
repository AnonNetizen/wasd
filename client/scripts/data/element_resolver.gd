# Doc: docs/代码/data_loader.md
# Authority: docs/词表与契约.md §9
class_name ElementResolver
extends RefCounted

const ELEMENTS_PATH: String = "res://data/elements.json"
const PAIR_SEPARATOR: String = "::"

var _neutral_element_id: String = ""
var _unmatched_result: String = ""
var _element_ids: Dictionary = {}
var _combinations: Dictionary = {}


func load_default() -> bool:
	var payload: Variant = DataLoader.load_json(ELEMENTS_PATH)
	return configure(payload)


func configure(payload: Variant) -> bool:
	_neutral_element_id = ""
	_unmatched_result = ""
	_element_ids.clear()
	_combinations.clear()
	if not payload is Dictionary:
		push_error("[ElementResolver] elements payload must be a Dictionary")
		return false
	var data: Dictionary = payload
	if data.get("schema_version") != 1:
		push_error("[ElementResolver] elements schema_version must equal 1")
		return false
	_neutral_element_id = str(data.get("neutral_element_id", ""))
	_unmatched_result = str(data.get("unmatched_result", ""))
	var elements_value: Variant = data.get("elements", [])
	if not elements_value is Array:
		push_error("[ElementResolver] elements must be an Array")
		return false
	var elements: Array = elements_value
	for entry_value: Variant in elements:
		if not entry_value is Dictionary:
			push_error("[ElementResolver] each element must be a Dictionary")
			return false
		var entry: Dictionary = entry_value
		var element_id: String = str(entry.get("id", ""))
		if element_id.is_empty() or _element_ids.has(element_id):
			push_error("[ElementResolver] element ids must be non-empty and unique")
			return false
		_element_ids[element_id] = true
	if not _element_ids.has(_neutral_element_id):
		push_error("[ElementResolver] neutral_element_id must reference a known element")
		return false
	var combinations_value: Variant = data.get("combinations", [])
	if not combinations_value is Array:
		push_error("[ElementResolver] combinations must be an Array")
		return false
	var combinations: Array = combinations_value
	for rule_value: Variant in combinations:
		if not rule_value is Dictionary:
			push_error("[ElementResolver] each combination must be a Dictionary")
			return false
		var rule: Dictionary = rule_value
		var left: String = str(rule.get("left", ""))
		var right: String = str(rule.get("right", ""))
		var result: String = str(rule.get("result", ""))
		if not _element_ids.has(left) or not _element_ids.has(right) or not _element_ids.has(result):
			push_error("[ElementResolver] combination ids must reference known elements")
			return false
		var key: String = _pair_key(left, right)
		if _combinations.has(key):
			push_error("[ElementResolver] duplicate symmetric combination")
			return false
		_combinations[key] = result
	return true


func combine(left: String, right: String) -> String:
	if not _element_ids.has(left) or not _element_ids.has(right):
		return _unmatched_result
	if left == _neutral_element_id:
		return right
	if right == _neutral_element_id:
		return left
	if left == right:
		return left
	return str(_combinations.get(_pair_key(left, right), _unmatched_result))


func has_element(element_id: String) -> bool:
	return _element_ids.has(element_id)


func _pair_key(left: String, right: String) -> String:
	if left < right:
		return left + PAIR_SEPARATOR + right
	return right + PAIR_SEPARATOR + left
