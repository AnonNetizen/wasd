extends SmokeHarness


const VALIDATOR := preload(
	"res://scripts/data/declarative_schema_validator.gd"
)
const FIXTURE_PATH: String = (
	"res://tests/fixtures/schema_conformance.json"
)


func test_shared_conformance_fixtures() -> void:
	var payload: Dictionary = _load_fixture_payload()
	var cases: Array = payload.get("cases", []) as Array
	assert_true(cases.size() >= 40, "fixture set stays representative")
	for raw_case: Variant in cases:
		assert_true(raw_case is Dictionary)
		if not raw_case is Dictionary:
			continue
		var case: Dictionary = raw_case as Dictionary
		var case_name: String = String(case.get("name", "unnamed"))
		var actual_errors: Array = []
		var actual_counts: Dictionary = {}
		if case.get("mode") == "schema":
			actual_errors = VALIDATOR.validate_schema(case.get("schema"))
		else:
			var result: Dictionary = VALIDATOR.validate(
				case.get("schema", {}) as Dictionary,
				case.get("value"),
				_context_from_fixture(case.get("context", {})),
				String(case.get("field_path", "root"))
			)
			actual_errors = result.get("errors", []) as Array
			actual_counts = result.get("counts", {}) as Dictionary
		assert_eq(
			actual_errors,
			case.get("errors", []) as Array,
			"%s errors" % case_name
		)
		assert_eq(
			actual_counts,
			_normalize_counts(case.get("counts", {}) as Dictionary),
			"%s counts" % case_name
		)


func _load_fixture_payload() -> Dictionary:
	var file: FileAccess = FileAccess.open(FIXTURE_PATH, FileAccess.READ)
	assert_not_null(file, "shared schema fixture opens")
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert_true(parsed is Dictionary, "shared schema fixture parses")
	return parsed as Dictionary if parsed is Dictionary else {}


func _context_from_fixture(raw_context: Variant) -> Dictionary:
	var fixture: Dictionary = (
		raw_context as Dictionary if raw_context is Dictionary else {}
	)
	var handlers: Dictionary = {}
	for raw_rule_id: Variant in fixture.get("semantic_rules", []) as Array:
		var rule_id: String = String(raw_rule_id)
		handlers[rule_id] = _fixture_semantic_handler.bind(rule_id)
	return {
		"references": _dictionary_or_empty(fixture.get("references", {})),
		"semantic_rules": handlers,
		"counts": _dictionary_or_empty(fixture.get("counts", {})),
		"headers": _dictionary_or_empty(fixture.get("headers", {})),
	}


func _fixture_semantic_handler(
	_value: Variant,
	field_path: String,
	_context: Dictionary,
	rule_id: String
) -> Array[Dictionary]:
	if rule_id == "fixture_reject":
		return [{
			"field": "%s.semantic" % field_path,
			"expected": "fixture semantic failure",
		}]
	return []


func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


func _normalize_counts(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw_key: Variant in value:
		var count: Variant = value[raw_key]
		result[raw_key] = int(count) if count is float else count
	return result
