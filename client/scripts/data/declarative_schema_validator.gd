# Doc: docs/代码/data_loader.md
class_name DeclarativeSchemaValidator
extends RefCounted


const SUPPORTED_KEYWORDS: Array[String] = [
	"$defs",
	"$id",
	"$ref",
	"$schema",
	"additionalProperties",
	"const",
	"enum",
	"exclusiveMaximum",
	"exclusiveMinimum",
	"items",
	"maxItems",
	"maxLength",
	"maximum",
	"minItems",
	"minLength",
	"minimum",
	"pattern",
	"properties",
	"required",
	"type",
	"x-wasd-count-key",
	"x-wasd-csv",
	"x-wasd-error",
	"x-wasd-order",
	"x-wasd-ref",
	"x-wasd-relation",
	"x-wasd-removed-field",
	"x-wasd-semantic-rules",
	"x-wasd-unique-by",
]
const SUPPORTED_TYPES: Array[String] = [
	"array", "boolean", "integer", "null", "number", "object", "string",
]
const CSV_PARSERS: Array[String] = [
	"boolean", "integer", "json", "number", "string",
]
const RELATION_OPERATIONS: Array[String] = [
	"equals", "greater_than", "less_or_equal",
]


static func validate(
	schema: Dictionary,
	value: Variant,
	context: Dictionary = {},
	field_path: String = "root"
) -> Dictionary:
	var active_context: Dictionary = context
	if not active_context.has("references"):
		active_context["references"] = {}
	if not active_context.has("semantic_rules"):
		active_context["semantic_rules"] = {}
	if not active_context.has("counts"):
		active_context["counts"] = {}
	if not active_context.has("headers"):
		active_context["headers"] = {}
	var errors: Array[Dictionary] = validate_schema(schema)
	if errors.is_empty():
		_validate_node(
			schema,
			schema,
			value,
			field_path,
			active_context,
			errors
		)
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"counts": _dictionary_or_empty(
			active_context.get("counts", {})
		).duplicate(true),
	}


static func validate_schema(
	schema: Variant,
	field_path: String = "schema"
) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	_validate_schema_node(schema, schema, field_path, errors)
	return errors


static func _validate_schema_node(
	root_schema: Variant,
	schema: Variant,
	field_path: String,
	errors: Array[Dictionary]
) -> void:
	if not schema is Dictionary:
		_append_error(errors, field_path, "must be an object")
		return
	var schema_data: Dictionary = schema as Dictionary
	for raw_key: Variant in schema_data:
		var key: String = String(raw_key)
		if key not in SUPPORTED_KEYWORDS:
			_append_error(
				errors,
				_child_path(field_path, key),
				"unknown schema keyword"
			)
	_validate_schema_descriptors(root_schema, schema_data, field_path, errors)
	var raw_properties: Variant = schema_data.get("properties", {})
	if not raw_properties is Dictionary:
		_append_error(
			errors,
			_child_path(field_path, "properties"),
			"must be an object"
		)
	else:
		var properties: Dictionary = raw_properties as Dictionary
		for raw_key: Variant in properties:
			var key: String = String(raw_key)
			_validate_schema_node(
				root_schema,
				properties[raw_key],
				_child_path(
					_child_path(field_path, "properties"),
					key
				),
				errors
			)
	if schema_data.has("items"):
		_validate_schema_node(
			root_schema,
			schema_data["items"],
			_child_path(field_path, "items"),
			errors
		)
	var raw_definitions: Variant = schema_data.get("$defs", {})
	if not raw_definitions is Dictionary:
		_append_error(
			errors,
			_child_path(field_path, "$defs"),
			"must be an object"
		)
	else:
		var definitions: Dictionary = raw_definitions as Dictionary
		for raw_key: Variant in definitions:
			var key: String = String(raw_key)
			_validate_schema_node(
				root_schema,
				definitions[raw_key],
				_child_path(_child_path(field_path, "$defs"), key),
				errors
			)


static func _validate_schema_descriptors(
	root_schema: Variant,
	schema: Dictionary,
	field_path: String,
	errors: Array[Dictionary]
) -> void:
	if schema.has("type") and String(schema["type"]) not in SUPPORTED_TYPES:
		_append_error(errors, _child_path(field_path, "type"), "must be a supported type")
	if schema.has("$ref"):
		var root: Dictionary = _dictionary_or_empty(root_schema)
		if _resolve_local_reference(root, schema["$ref"]).is_empty():
			_append_error(errors, _child_path(field_path, "$ref"), "must be a valid local reference")
	for keyword: String in ["required", "x-wasd-order", "x-wasd-semantic-rules"]:
		if schema.has(keyword) and not _is_string_array(schema[keyword]):
			_append_error(errors, _child_path(field_path, keyword), "must be an array of strings")
	if schema.has("enum") and not schema["enum"] is Array:
		_append_error(errors, _child_path(field_path, "enum"), "must be an array")
	if schema.has("additionalProperties") and not schema["additionalProperties"] is bool:
		_append_error(errors, _child_path(field_path, "additionalProperties"), "must be a boolean")
	for keyword: String in [
		"exclusiveMaximum",
		"exclusiveMinimum",
		"maxItems",
		"maxLength",
		"maximum",
		"minItems",
		"minLength",
		"minimum",
	]:
		if schema.has(keyword) and not _is_number(schema[keyword]):
			_append_error(errors, _child_path(field_path, keyword), "must be a number")
	if schema.has("pattern"):
		if not schema["pattern"] is String:
			_append_error(errors, _child_path(field_path, "pattern"), "must be a string")
		else:
			var pattern: String = String(schema["pattern"])
			var regex := RegEx.new()
			if not _pattern_delimiters_are_balanced(pattern) or regex.compile(pattern) != OK:
				_append_error(errors, _child_path(field_path, "pattern"), "must be a valid regular expression")
	for keyword: String in ["x-wasd-count-key", "x-wasd-unique-by"]:
		if schema.has(keyword) and not schema[keyword] is String:
			_append_error(errors, _child_path(field_path, keyword), "must be a string")
	if schema.has("x-wasd-removed-field") and not schema["x-wasd-removed-field"] is Dictionary:
		_append_error(errors, _child_path(field_path, "x-wasd-removed-field"), "must be an object")
	if schema.has("x-wasd-ref"):
		var reference: Dictionary = _dictionary_or_empty(schema["x-wasd-ref"])
		if reference.is_empty() or not reference.get("source") is String:
			_append_error(errors, _child_path(field_path, "x-wasd-ref"), "must name a reference source")
	if schema.has("x-wasd-relation"):
		_validate_relation_descriptors(schema["x-wasd-relation"], _child_path(field_path, "x-wasd-relation"), errors)
	if schema.has("x-wasd-csv"):
		_validate_csv_descriptor(schema["x-wasd-csv"], _child_path(field_path, "x-wasd-csv"), errors)


static func _validate_relation_descriptors(
	value: Variant,
	field_path: String,
	errors: Array[Dictionary]
) -> void:
	if not value is Array:
		_append_error(errors, field_path, "must be an array")
		return
	var descriptors: Array = value as Array
	for index: int in descriptors.size():
		var relation_path: String = "%s[%d]" % [field_path, index]
		if not descriptors[index] is Dictionary:
			_append_error(errors, relation_path, "must be an object")
			continue
		var relation: Dictionary = descriptors[index] as Dictionary
		if String(relation.get("op", "")) not in RELATION_OPERATIONS:
			_append_error(errors, _child_path(relation_path, "op"), "must be a supported relation")
		for key: String in ["left", "right"]:
			if not relation.get(key) is String:
				_append_error(errors, _child_path(relation_path, key), "must be a string")


static func _validate_csv_descriptor(
	value: Variant,
	field_path: String,
	errors: Array[Dictionary]
) -> void:
	if not value is Dictionary:
		_append_error(errors, field_path, "must be an object")
		return
	var descriptor: Dictionary = value as Dictionary
	if not descriptor.get("source") is String:
		_append_error(errors, _child_path(field_path, "source"), "must be a string")
	if not _is_string_array(descriptor.get("headers")):
		_append_error(errors, _child_path(field_path, "headers"), "must be an array of strings")
	if not descriptor.get("columns", {}) is Dictionary:
		_append_error(errors, _child_path(field_path, "columns"), "must be an object")
		return
	var columns: Dictionary = descriptor.get("columns", {}) as Dictionary
	for raw_column: Variant in columns:
		var column: String = String(raw_column)
		if not raw_column is String or String(columns[raw_column]) not in CSV_PARSERS:
			_append_error(errors, _child_path(_child_path(field_path, "columns"), column), "must name a supported parser")


static func _validate_node(
	root_schema: Dictionary,
	schema: Dictionary,
	value: Variant,
	field_path: String,
	context: Dictionary,
	errors: Array[Dictionary]
) -> void:
	value = _prepare_csv(schema, value, field_path, context, errors)
	if schema.has("$ref"):
		var resolved: Dictionary = _resolve_local_reference(
			root_schema,
			schema.get("$ref", "")
		)
		if resolved.is_empty():
			_append_error(
				errors,
				field_path,
				"unknown local schema reference %s" % schema.get("$ref", "")
			)
			return
		_validate_node(
			root_schema,
			resolved,
			value,
			field_path,
			context,
			errors
		)
		return

	var expected_type: String = String(schema.get("type", ""))
	if not expected_type.is_empty() and not _matches_type(value, expected_type):
		_append_error(
			errors,
			field_path,
			_expected(schema, "type", "must be %s" % expected_type)
		)
		return

	if schema.has("const") and not _json_equal(value, schema["const"]):
		_append_error(
			errors,
			field_path,
			_expected(schema, "const", "must equal %s" % schema["const"])
		)
	if schema.has("enum"):
		var raw_enum: Variant = schema["enum"]
		var enum_matches: bool = false
		if raw_enum is Array:
			for candidate: Variant in raw_enum as Array:
				if _json_equal(value, candidate):
					enum_matches = true
					break
		if not enum_matches:
			_append_error(
				errors,
				field_path,
				_expected(
					schema,
					"enum",
					"must be one of the allowed values"
				)
			)

	if value is Dictionary:
		_validate_object(
			root_schema,
			schema,
			value as Dictionary,
			field_path,
			context,
			errors
		)
	elif value is Array:
		_validate_array(
			root_schema,
			schema,
			value as Array,
			field_path,
			context,
			errors
		)
	elif value is String:
		_validate_string(schema, String(value), field_path, errors)
	elif _is_number(value):
		_validate_number(schema, float(value), field_path, errors)

	_validate_external_reference(schema, value, field_path, context, errors)
	_validate_relations(schema, value, field_path, errors)
	_validate_semantic_rules(schema, value, field_path, context, errors)
	var count_key: String = String(schema.get("x-wasd-count-key", ""))
	if not count_key.is_empty():
		var counts: Dictionary = _dictionary_or_empty(context.get("counts", {}))
		if value is Array or value is Dictionary:
			counts[count_key] = value.size()
		else:
			counts[count_key] = 1


static func _prepare_csv(
	schema: Dictionary,
	value: Variant,
	field_path: String,
	context: Dictionary,
	errors: Array[Dictionary]
) -> Variant:
	if not schema.get("x-wasd-csv") is Dictionary or not value is Array:
		return value
	var descriptor: Dictionary = schema["x-wasd-csv"] as Dictionary
	var source: String = String(descriptor["source"])
	var expected_headers: Array = descriptor["headers"] as Array
	var headers: Dictionary = _dictionary_or_empty(context.get("headers", {}))
	if not headers.has(source):
		_append_error(errors, field_path, "missing CSV headers for %s" % source)
	elif headers[source] != expected_headers:
		_append_error(errors, field_path, "CSV header does not match schema")
	var columns: Dictionary = _dictionary_or_empty(descriptor.get("columns", {}))
	var parsed_rows: Array = []
	var rows: Array = value as Array
	for index: int in rows.size():
		var raw_row: Variant = rows[index]
		if not raw_row is Dictionary:
			parsed_rows.append(raw_row)
			continue
		var parsed_row: Dictionary = (raw_row as Dictionary).duplicate(true)
		for raw_column: Variant in columns:
			if not parsed_row.has(raw_column):
				continue
			var column: String = String(raw_column)
			var parsed: Dictionary = _parse_csv_value(
				parsed_row[raw_column],
				String(columns[raw_column])
			)
			if not bool(parsed.get("ok", false)):
				_append_error(
					errors,
					"%s[%d].%s" % [field_path, index, column],
					"must parse as %s" % columns[raw_column]
				)
			else:
				parsed_row[raw_column] = parsed.get("value")
		parsed_rows.append(parsed_row)
	return parsed_rows


static func _parse_csv_value(value: Variant, parser: String) -> Dictionary:
	if not value is String:
		return {"ok": false}
	var text: String = value
	match parser:
		"string":
			return {"ok": true, "value": text}
		"integer":
			return {"ok": text.is_valid_int(), "value": text.to_int()}
		"number":
			var parsed_number: float = text.to_float()
			return {
				"ok": text.is_valid_float() and is_finite(parsed_number),
				"value": parsed_number,
			}
		"boolean":
			var normalized: String = text.to_lower()
			return {
				"ok": normalized == "true" or normalized == "false",
				"value": normalized == "true",
			}
		"json":
			var parser_instance := JSON.new()
			var parse_error: Error = parser_instance.parse(text)
			return {
				"ok": parse_error == OK,
				"value": parser_instance.data,
			}
	return {"ok": false}


static func _validate_object(
	root_schema: Dictionary,
	schema: Dictionary,
	value: Dictionary,
	field_path: String,
	context: Dictionary,
	errors: Array[Dictionary]
) -> void:
	var properties: Dictionary = _dictionary_or_empty(
		schema.get("properties", {})
	)
	var required: Array = _array_or_empty(schema.get("required", []))
	var order: Array = _array_or_empty(schema.get("x-wasd-order", required))
	var ordered_keys: Array[String] = []
	for source: Array in [order, required, properties.keys()]:
		for raw_key: Variant in source:
			var key: String = String(raw_key)
			if key not in ordered_keys:
				ordered_keys.append(key)
	for key: String in ordered_keys:
		var child_path: String = _child_path(field_path, key)
		if key in required and not value.has(key):
			_append_error(
				errors,
				child_path,
				_expected(schema, "required.%s" % key, "is required")
			)
			continue
		if value.has(key) and properties.has(key):
			_validate_node(
				root_schema,
				properties[key] as Dictionary,
				value[key],
				child_path,
				context,
				errors
			)

	var removed: Dictionary = _dictionary_or_empty(
		schema.get("x-wasd-removed-field", {})
	)
	for raw_key: Variant in removed:
		var key: String = String(raw_key)
		if value.has(key):
			_append_error(
				errors,
				_child_path(field_path, key),
				String(removed[raw_key])
			)

	if schema.get("additionalProperties", true) == false:
		for raw_key: Variant in value:
			var key: String = String(raw_key)
			if not properties.has(key):
				_append_error(
					errors,
					_child_path(field_path, key),
					_expected(
						schema,
						"additionalProperties",
						"is not allowed"
					)
				)


static func _validate_array(
	root_schema: Dictionary,
	schema: Dictionary,
	value: Array,
	field_path: String,
	context: Dictionary,
	errors: Array[Dictionary]
) -> void:
	if value.size() < int(schema.get("minItems", 0)):
		_append_error(
			errors,
			field_path,
			_expected(schema, "minItems", "has too few items")
		)
	if schema.has("maxItems") and value.size() > int(schema["maxItems"]):
		_append_error(
			errors,
			field_path,
			_expected(schema, "maxItems", "has too many items")
		)
	var raw_item_schema: Variant = schema.get("items")
	if raw_item_schema is Dictionary:
		var item_schema: Dictionary = raw_item_schema as Dictionary
		for index: int in range(value.size()):
			_validate_node(
				root_schema,
				item_schema,
				value[index],
				"%s[%d]" % [field_path, index],
				context,
				errors
			)
	var unique_key: String = String(schema.get("x-wasd-unique-by", ""))
	if unique_key.is_empty():
		return
	var seen: Dictionary = {}
	for index: int in range(value.size()):
		var raw_item: Variant = value[index]
		if not raw_item is Dictionary:
			continue
		var item: Dictionary = raw_item as Dictionary
		if not item.has(unique_key):
			continue
		var candidate: Variant = item[unique_key]
		if seen.has(candidate):
			_append_error(
				errors,
				"%s[%d].%s" % [field_path, index, unique_key],
				_expected(schema, "x-wasd-unique-by", "must be unique")
			)
		seen[candidate] = true


static func _validate_string(
	schema: Dictionary,
	value: String,
	field_path: String,
	errors: Array[Dictionary]
) -> void:
	if value.length() < int(schema.get("minLength", 0)):
		_append_error(
			errors,
			field_path,
			_expected(schema, "minLength", "is too short")
		)
	if schema.has("maxLength") and value.length() > int(schema["maxLength"]):
		_append_error(
			errors,
			field_path,
			_expected(schema, "maxLength", "is too long")
		)
	var pattern: String = String(schema.get("pattern", ""))
	if pattern.is_empty():
		return
	var regex := RegEx.new()
	if regex.compile(pattern) != OK or regex.search(value) == null:
		_append_error(
			errors,
			field_path,
			_expected(schema, "pattern", "has invalid format")
		)


static func _validate_number(
	schema: Dictionary,
	value: float,
	field_path: String,
	errors: Array[Dictionary]
) -> void:
	if not is_finite(value):
		_append_error(
			errors,
			field_path,
			_expected(schema, "type", "must be finite")
		)
		return
	var checks: Array[Dictionary] = [
		{"key": "minimum", "failed": value < float(schema.get("minimum", value))},
		{
			"key": "exclusiveMinimum",
			"failed": value <= float(schema.get("exclusiveMinimum", value - 1.0)),
		},
		{"key": "maximum", "failed": value > float(schema.get("maximum", value))},
		{
			"key": "exclusiveMaximum",
			"failed": value >= float(schema.get("exclusiveMaximum", value + 1.0)),
		},
	]
	var defaults: Dictionary = {
		"minimum": "is below minimum",
		"exclusiveMinimum": "must be above minimum",
		"maximum": "is above maximum",
		"exclusiveMaximum": "must be below maximum",
	}
	for check: Dictionary in checks:
		var key: String = String(check["key"])
		if schema.has(key) and bool(check["failed"]):
			_append_error(
				errors,
				field_path,
				_expected(schema, key, String(defaults[key]))
			)


static func _validate_external_reference(
	schema: Dictionary,
	value: Variant,
	field_path: String,
	context: Dictionary,
	errors: Array[Dictionary]
) -> void:
	var raw_descriptor: Variant = schema.get("x-wasd-ref")
	if not raw_descriptor is Dictionary:
		return
	var descriptor: Dictionary = raw_descriptor as Dictionary
	var source: String = String(descriptor.get("source", ""))
	var references: Dictionary = _dictionary_or_empty(
		context.get("references", {})
	)
	if not references.has(source):
		_append_error(errors, field_path, "unknown reference source %s" % source)
		return
	var candidates: Variant = references[source]
	var valid: bool = false
	if candidates is Dictionary:
		valid = (candidates as Dictionary).has(value)
	elif candidates is Array:
		valid = value in (candidates as Array)
	if not valid:
		_append_error(
			errors,
			field_path,
			String(descriptor.get("expected", "must reference %s" % source))
		)


static func _validate_relations(
	schema: Dictionary,
	value: Variant,
	field_path: String,
	errors: Array[Dictionary]
) -> void:
	var raw_descriptors: Variant = schema.get("x-wasd-relation", [])
	if not value is Dictionary or not raw_descriptors is Array:
		return
	var dictionary: Dictionary = value as Dictionary
	for raw_descriptor: Variant in raw_descriptors as Array:
		if not raw_descriptor is Dictionary:
			continue
		var descriptor: Dictionary = raw_descriptor as Dictionary
		var left_key: String = String(descriptor.get("left", ""))
		var right_key: String = String(descriptor.get("right", ""))
		if not dictionary.has(left_key) or not dictionary.has(right_key):
			continue
		var left: Variant = dictionary[left_key]
		var right: Variant = dictionary[right_key]
		var operation: String = String(descriptor.get("op", ""))
		var valid: bool = true
		match operation:
			"greater_than":
				valid = (
					_is_number(left)
					and _is_number(right)
					and float(left) > float(right)
				)
			"less_or_equal":
				valid = (
					_is_number(left)
					and _is_number(right)
					and float(left) <= float(right)
				)
			"equals":
				valid = _json_equal(left, right)
			_:
				_append_error(
					errors,
					field_path,
					"unknown relation operation %s" % operation
				)
				continue
		if not valid:
			_append_error(
				errors,
				_child_path(field_path, left_key),
				String(descriptor.get("expected", "relation is invalid"))
			)


static func _validate_semantic_rules(
	schema: Dictionary,
	value: Variant,
	field_path: String,
	context: Dictionary,
	errors: Array[Dictionary]
) -> void:
	var rules: Array = _array_or_empty(
		schema.get("x-wasd-semantic-rules", [])
	)
	var handlers: Dictionary = _dictionary_or_empty(
		context.get("semantic_rules", {})
	)
	for raw_rule_id: Variant in rules:
		var rule_id: String = String(raw_rule_id)
		var raw_handler: Variant = handlers.get(rule_id)
		if not raw_handler is Callable or not (raw_handler as Callable).is_valid():
			_append_error(
				errors,
				field_path,
				"unknown semantic rule %s" % rule_id
			)
			continue
		var raw_result: Variant = (raw_handler as Callable).call(
			value,
			field_path,
			context
		)
		if raw_result is Array:
			for raw_error: Variant in raw_result as Array:
				if raw_error is Dictionary:
					errors.append((raw_error as Dictionary).duplicate(true))


static func _resolve_local_reference(
	root_schema: Dictionary,
	raw_reference: Variant
) -> Dictionary:
	var reference: String = String(raw_reference)
	if not reference.begins_with("#/"):
		return {}
	var current: Variant = root_schema
	for raw_token: String in reference.trim_prefix("#/").split("/"):
		var token: String = raw_token.replace("~1", "/").replace("~0", "~")
		if not current is Dictionary or not (current as Dictionary).has(token):
			return {}
		current = (current as Dictionary)[token]
	return current as Dictionary if current is Dictionary else {}


static func _matches_type(value: Variant, expected_type: String) -> bool:
	match expected_type:
		"object":
			return value is Dictionary
		"array":
			return value is Array
		"string":
			return value is String or value is StringName
		"boolean":
			return value is bool
		"integer":
			return _is_number(value) and is_equal_approx(float(value), roundf(float(value)))
		"number":
			return _is_number(value)
		"null":
			return value == null
		_:
			return false


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _json_equal(left: Variant, right: Variant) -> bool:
	if _is_number(left) and _is_number(right):
		return is_equal_approx(float(left), float(right))
	return typeof(left) == typeof(right) and left == right


static func _expected(
	schema: Dictionary,
	keyword: String,
	default_value: String
) -> String:
	var overrides: Dictionary = _dictionary_or_empty(
		schema.get("x-wasd-error", {})
	)
	return String(overrides.get(keyword, default_value))


static func _child_path(parent: String, child: String) -> String:
	if parent.is_empty() or parent == "root":
		return child
	return "%s.%s" % [parent, child]


static func _append_error(
	errors: Array[Dictionary],
	field_path: String,
	expected: String
) -> void:
	errors.append({"field": field_path, "expected": expected})


static func _dictionary_or_empty(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


static func _array_or_empty(value: Variant) -> Array:
	return value as Array if value is Array else []


static func _is_string_array(value: Variant) -> bool:
	if not value is Array:
		return false
	for item: Variant in value as Array:
		if not item is String:
			return false
	return true


static func _pattern_delimiters_are_balanced(pattern: String) -> bool:
	var square_depth: int = 0
	var round_depth: int = 0
	var escaped: bool = false
	for index: int in pattern.length():
		var character: String = pattern.substr(index, 1)
		if escaped:
			escaped = false
			continue
		if character == "\\":
			escaped = true
			continue
		if character == "[":
			square_depth += 1
		elif character == "]":
			square_depth -= 1
		elif character == "(" and square_depth == 0:
			round_depth += 1
		elif character == ")" and square_depth == 0:
			round_depth -= 1
		if square_depth < 0 or round_depth < 0:
			return false
	return not escaped and square_depth == 0 and round_depth == 0
