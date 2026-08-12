#!/usr/bin/env python3
"""Deterministic JSON-Schema subset shared by WASD data tooling."""

from __future__ import annotations

import math
import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable


SemanticRule = Callable[[Any, str, "ValidationContext"], list[dict[str, str]]]


SUPPORTED_KEYWORDS = frozenset(
    {
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
    }
)
SUPPORTED_TYPES = frozenset({"array", "boolean", "integer", "null", "number", "object", "string"})
CSV_PARSERS = frozenset({"boolean", "integer", "json", "number", "string"})
RELATION_OPERATIONS = frozenset({"equals", "greater_than", "less_or_equal"})


@dataclass
class ValidationContext:
    references: dict[str, Any] = field(default_factory=dict)
    semantic_rules: dict[str, SemanticRule] = field(default_factory=dict)
    counts: dict[str, int] = field(default_factory=dict)
    headers: dict[str, list[str]] = field(default_factory=dict)


def validate(
    schema: dict[str, Any],
    value: Any,
    *,
    context: ValidationContext | None = None,
    field_path: str = "root",
) -> dict[str, Any]:
    active_context = context or ValidationContext()
    errors: list[dict[str, str]] = []
    meta_errors = validate_schema(schema)
    if meta_errors:
        return {
            "ok": False,
            "errors": meta_errors,
            "counts": dict(active_context.counts),
        }
    _validate_node(schema, schema, value, field_path, active_context, errors)
    return {
        "ok": not errors,
        "errors": errors,
        "counts": dict(active_context.counts),
    }


def validate_schema(schema: Any, field_path: str = "schema") -> list[dict[str, str]]:
    errors: list[dict[str, str]] = []
    _validate_schema_node(schema, schema, field_path, errors)
    return errors


def load_json(path: Path) -> Any:
    import json

    return json.loads(path.read_text(encoding="utf-8"))


def _validate_schema_node(
    root_schema: Any,
    schema: Any,
    field_path: str,
    errors: list[dict[str, str]],
) -> None:
    if not isinstance(schema, dict):
        _append_error(errors, field_path, "must be an object")
        return
    for key in schema:
        if key not in SUPPORTED_KEYWORDS:
            _append_error(errors, f"{field_path}.{key}", "unknown schema keyword")
    expected_type = schema.get("type")
    if expected_type is not None and expected_type not in SUPPORTED_TYPES:
        _append_error(errors, f"{field_path}.type", "must be a supported type")
    reference = schema.get("$ref")
    if reference is not None and _resolve_local_reference(root_schema, reference) is None:
        _append_error(errors, f"{field_path}.$ref", "must be a valid local reference")
    for keyword in ("required", "x-wasd-order", "x-wasd-semantic-rules"):
        descriptor = schema.get(keyword)
        if descriptor is not None and (
            not isinstance(descriptor, list)
            or any(not isinstance(item, str) for item in descriptor)
        ):
            _append_error(errors, f"{field_path}.{keyword}", "must be an array of strings")
    if "enum" in schema and not isinstance(schema["enum"], list):
        _append_error(errors, f"{field_path}.enum", "must be an array")
    if "additionalProperties" in schema and not isinstance(schema["additionalProperties"], bool):
        _append_error(errors, f"{field_path}.additionalProperties", "must be a boolean")
    for keyword in (
        "exclusiveMaximum",
        "exclusiveMinimum",
        "maxItems",
        "maxLength",
        "maximum",
        "minItems",
        "minLength",
        "minimum",
    ):
        if keyword in schema and not _is_number(schema[keyword]):
            _append_error(errors, f"{field_path}.{keyword}", "must be a number")
    if "pattern" in schema:
        pattern = schema["pattern"]
        if not isinstance(pattern, str):
            _append_error(errors, f"{field_path}.pattern", "must be a string")
        else:
            try:
                re.compile(pattern)
            except re.error:
                _append_error(errors, f"{field_path}.pattern", "must be a valid regular expression")
    if "x-wasd-count-key" in schema and not isinstance(schema["x-wasd-count-key"], str):
        _append_error(errors, f"{field_path}.x-wasd-count-key", "must be a string")
    if "x-wasd-unique-by" in schema and not isinstance(schema["x-wasd-unique-by"], str):
        _append_error(errors, f"{field_path}.x-wasd-unique-by", "must be a string")
    removed = schema.get("x-wasd-removed-field")
    if removed is not None and not isinstance(removed, dict):
        _append_error(errors, f"{field_path}.x-wasd-removed-field", "must be an object")
    external_reference = schema.get("x-wasd-ref")
    if external_reference is not None and (
        not isinstance(external_reference, dict)
        or not isinstance(external_reference.get("source"), str)
    ):
        _append_error(errors, f"{field_path}.x-wasd-ref", "must name a reference source")
    relations = schema.get("x-wasd-relation")
    if relations is not None:
        if not isinstance(relations, list):
            _append_error(errors, f"{field_path}.x-wasd-relation", "must be an array")
        else:
            for index, relation in enumerate(relations):
                relation_path = f"{field_path}.x-wasd-relation[{index}]"
                if not isinstance(relation, dict):
                    _append_error(errors, relation_path, "must be an object")
                    continue
                if relation.get("op") not in RELATION_OPERATIONS:
                    _append_error(errors, f"{relation_path}.op", "must be a supported relation")
                for key in ("left", "right"):
                    if not isinstance(relation.get(key), str):
                        _append_error(errors, f"{relation_path}.{key}", "must be a string")
    csv_descriptor = schema.get("x-wasd-csv")
    if csv_descriptor is not None:
        _validate_csv_descriptor(csv_descriptor, f"{field_path}.x-wasd-csv", errors)
    properties = schema.get("properties", {})
    if properties is not None and not isinstance(properties, dict):
        _append_error(errors, f"{field_path}.properties", "must be an object")
    elif isinstance(properties, dict):
        for key, child in properties.items():
            _validate_schema_node(root_schema, child, f"{field_path}.properties.{key}", errors)
    items = schema.get("items")
    if items is not None:
        _validate_schema_node(root_schema, items, f"{field_path}.items", errors)
    definitions = schema.get("$defs", {})
    if definitions is not None and not isinstance(definitions, dict):
        _append_error(errors, f"{field_path}.$defs", "must be an object")
    elif isinstance(definitions, dict):
        for key, child in definitions.items():
            _validate_schema_node(root_schema, child, f"{field_path}.$defs.{key}", errors)


def _validate_csv_descriptor(
    descriptor: Any,
    field_path: str,
    errors: list[dict[str, str]],
) -> None:
    if not isinstance(descriptor, dict):
        _append_error(errors, field_path, "must be an object")
        return
    if not isinstance(descriptor.get("source"), str):
        _append_error(errors, f"{field_path}.source", "must be a string")
    headers = descriptor.get("headers")
    if not isinstance(headers, list) or any(not isinstance(item, str) for item in headers):
        _append_error(errors, f"{field_path}.headers", "must be an array of strings")
    columns = descriptor.get("columns", {})
    if not isinstance(columns, dict):
        _append_error(errors, f"{field_path}.columns", "must be an object")
        return
    for column, parser in columns.items():
        if not isinstance(column, str) or parser not in CSV_PARSERS:
            _append_error(errors, f"{field_path}.columns.{column}", "must name a supported parser")


def _validate_node(
    root_schema: dict[str, Any],
    schema: dict[str, Any],
    value: Any,
    field_path: str,
    context: ValidationContext,
    errors: list[dict[str, str]],
) -> None:
    value = _prepare_csv(schema, value, field_path, context, errors)
    reference = schema.get("$ref")
    if reference is not None:
        resolved = _resolve_local_reference(root_schema, reference)
        if resolved is None:
            _append_error(errors, field_path, f"unknown local schema reference {reference}")
            return
        _validate_node(root_schema, resolved, value, field_path, context, errors)
        return

    expected_type = schema.get("type")
    if expected_type is not None and not _matches_type(value, expected_type):
        _append_error(
            errors,
            field_path,
            _expected(schema, "type", f"must be {expected_type}"),
        )
        return

    if "const" in schema and not _json_equal(value, schema["const"]):
        _append_error(
            errors,
            field_path,
            _expected(schema, "const", f"must equal {schema['const']}"),
        )
    if "enum" in schema and not any(_json_equal(value, item) for item in schema["enum"]):
        _append_error(
            errors,
            field_path,
            _expected(schema, "enum", "must be one of the allowed values"),
        )

    if isinstance(value, dict):
        _validate_object(root_schema, schema, value, field_path, context, errors)
    elif isinstance(value, list):
        _validate_array(root_schema, schema, value, field_path, context, errors)
    elif isinstance(value, str):
        _validate_string(schema, value, field_path, errors)
    elif _is_number(value):
        _validate_number(schema, float(value), field_path, errors)

    _validate_external_reference(schema, value, field_path, context, errors)
    _validate_relations(schema, value, field_path, errors)
    _validate_semantic_rules(schema, value, field_path, context, errors)
    count_key = schema.get("x-wasd-count-key")
    if isinstance(count_key, str):
        context.counts[count_key] = len(value) if isinstance(value, (list, dict)) else 1


def _prepare_csv(
    schema: dict[str, Any],
    value: Any,
    field_path: str,
    context: ValidationContext,
    errors: list[dict[str, str]],
) -> Any:
    descriptor = schema.get("x-wasd-csv")
    if not isinstance(descriptor, dict) or not isinstance(value, list):
        return value
    source = descriptor["source"]
    expected_headers = descriptor["headers"]
    actual_headers = context.headers.get(source)
    if actual_headers is None:
        _append_error(errors, field_path, f"missing CSV headers for {source}")
    elif actual_headers != expected_headers:
        _append_error(errors, field_path, "CSV header does not match schema")
    columns = descriptor.get("columns", {})
    parsed_rows: list[Any] = []
    for index, row in enumerate(value):
        if not isinstance(row, dict):
            parsed_rows.append(row)
            continue
        parsed_row = dict(row)
        for column, parser in columns.items():
            if column not in parsed_row:
                continue
            try:
                parsed_row[column] = _parse_csv_value(parsed_row[column], parser)
            except (TypeError, ValueError, json.JSONDecodeError):
                _append_error(
                    errors,
                    f"{field_path}[{index}].{column}",
                    f"must parse as {parser}",
                )
        parsed_rows.append(parsed_row)
    return parsed_rows


def _parse_csv_value(value: Any, parser: str) -> Any:
    if not isinstance(value, str):
        raise TypeError
    if parser == "string":
        return value
    if parser == "integer":
        if re.fullmatch(r"[+-]?\d+", value) is None:
            raise ValueError
        return int(value)
    if parser == "number":
        parsed = float(value)
        if not math.isfinite(parsed):
            raise ValueError
        return parsed
    if parser == "boolean":
        normalized = value.lower()
        if normalized not in {"false", "true"}:
            raise ValueError
        return normalized == "true"
    if parser == "json":
        return json.loads(value)
    raise ValueError


def _validate_object(
    root_schema: dict[str, Any],
    schema: dict[str, Any],
    value: dict[str, Any],
    field_path: str,
    context: ValidationContext,
    errors: list[dict[str, str]],
) -> None:
    properties = schema.get("properties", {})
    required = schema.get("required", [])
    order = schema.get("x-wasd-order", required)
    ordered_keys: list[str] = []
    for key in [*order, *required, *properties.keys()]:
        if key not in ordered_keys:
            ordered_keys.append(key)
    for key in ordered_keys:
        child_path = _child_path(field_path, key)
        if key in required and key not in value:
            _append_error(
                errors,
                child_path,
                _expected(schema, f"required.{key}", "is required"),
            )
            continue
        if key in value and key in properties:
            _validate_node(
                root_schema,
                properties[key],
                value[key],
                child_path,
                context,
                errors,
            )

    removed = schema.get("x-wasd-removed-field", {})
    if isinstance(removed, dict):
        for key, expected in removed.items():
            if key in value:
                _append_error(errors, _child_path(field_path, key), str(expected))

    if schema.get("additionalProperties") is False:
        for key in value:
            if key not in properties:
                _append_error(
                    errors,
                    _child_path(field_path, key),
                    _expected(schema, "additionalProperties", "is not allowed"),
                )


def _validate_array(
    root_schema: dict[str, Any],
    schema: dict[str, Any],
    value: list[Any],
    field_path: str,
    context: ValidationContext,
    errors: list[dict[str, str]],
) -> None:
    if len(value) < int(schema.get("minItems", 0)):
        _append_error(errors, field_path, _expected(schema, "minItems", "has too few items"))
    if "maxItems" in schema and len(value) > int(schema["maxItems"]):
        _append_error(errors, field_path, _expected(schema, "maxItems", "has too many items"))
    item_schema = schema.get("items")
    if isinstance(item_schema, dict):
        for index, item in enumerate(value):
            _validate_node(
                root_schema,
                item_schema,
                item,
                f"{field_path}[{index}]",
                context,
                errors,
            )
    unique_key = schema.get("x-wasd-unique-by")
    if isinstance(unique_key, str):
        seen: set[Any] = set()
        for index, item in enumerate(value):
            if not isinstance(item, dict) or unique_key not in item:
                continue
            candidate = item[unique_key]
            if candidate in seen:
                _append_error(
                    errors,
                    f"{field_path}[{index}].{unique_key}",
                    _expected(schema, "x-wasd-unique-by", "must be unique"),
                )
            seen.add(candidate)


def _validate_string(
    schema: dict[str, Any],
    value: str,
    field_path: str,
    errors: list[dict[str, str]],
) -> None:
    if len(value) < int(schema.get("minLength", 0)):
        _append_error(errors, field_path, _expected(schema, "minLength", "is too short"))
    if "maxLength" in schema and len(value) > int(schema["maxLength"]):
        _append_error(errors, field_path, _expected(schema, "maxLength", "is too long"))
    pattern = schema.get("pattern")
    if isinstance(pattern, str) and re.search(pattern, value) is None:
        _append_error(errors, field_path, _expected(schema, "pattern", "has invalid format"))


def _validate_number(
    schema: dict[str, Any],
    value: float,
    field_path: str,
    errors: list[dict[str, str]],
) -> None:
    if not math.isfinite(value):
        _append_error(errors, field_path, _expected(schema, "type", "must be finite"))
        return
    checks = (
        ("minimum", lambda limit: value < limit, "is below minimum"),
        ("exclusiveMinimum", lambda limit: value <= limit, "must be above minimum"),
        ("maximum", lambda limit: value > limit, "is above maximum"),
        ("exclusiveMaximum", lambda limit: value >= limit, "must be below maximum"),
    )
    for keyword, fails, default in checks:
        if keyword in schema and fails(float(schema[keyword])):
            _append_error(errors, field_path, _expected(schema, keyword, default))


def _validate_external_reference(
    schema: dict[str, Any],
    value: Any,
    field_path: str,
    context: ValidationContext,
    errors: list[dict[str, str]],
) -> None:
    descriptor = schema.get("x-wasd-ref")
    if not isinstance(descriptor, dict):
        return
    source = descriptor.get("source")
    candidates = context.references.get(source)
    if isinstance(candidates, dict):
        valid = value in candidates
    elif isinstance(candidates, (list, set, tuple)):
        valid = value in candidates
    else:
        _append_error(errors, field_path, f"unknown reference source {source}")
        return
    if not valid:
        _append_error(
            errors,
            field_path,
            str(descriptor.get("expected", f"must reference {source}")),
        )


def _validate_relations(
    schema: dict[str, Any],
    value: Any,
    field_path: str,
    errors: list[dict[str, str]],
) -> None:
    descriptors = schema.get("x-wasd-relation", [])
    if not isinstance(value, dict) or not isinstance(descriptors, list):
        return
    for descriptor in descriptors:
        if not isinstance(descriptor, dict):
            continue
        left_key = descriptor.get("left")
        right_key = descriptor.get("right")
        if left_key not in value or right_key not in value:
            continue
        left = value[left_key]
        right = value[right_key]
        operation = descriptor.get("op")
        valid = True
        if operation == "greater_than":
            valid = _is_number(left) and _is_number(right) and float(left) > float(right)
        elif operation == "less_or_equal":
            valid = _is_number(left) and _is_number(right) and float(left) <= float(right)
        elif operation == "equals":
            valid = _json_equal(left, right)
        else:
            _append_error(errors, field_path, f"unknown relation operation {operation}")
            continue
        if not valid:
            _append_error(
                errors,
                _child_path(field_path, str(left_key)),
                str(descriptor.get("expected", "relation is invalid")),
            )


def _validate_semantic_rules(
    schema: dict[str, Any],
    value: Any,
    field_path: str,
    context: ValidationContext,
    errors: list[dict[str, str]],
) -> None:
    rules = schema.get("x-wasd-semantic-rules", [])
    if not isinstance(rules, list):
        return
    for rule_id in rules:
        handler = context.semantic_rules.get(rule_id)
        if handler is None:
            _append_error(errors, field_path, f"unknown semantic rule {rule_id}")
            continue
        errors.extend(handler(value, field_path, context))


def _resolve_local_reference(
    root_schema: dict[str, Any],
    reference: Any,
) -> dict[str, Any] | None:
    if not isinstance(reference, str) or not reference.startswith("#/"):
        return None
    current: Any = root_schema
    for raw_token in reference[2:].split("/"):
        token = raw_token.replace("~1", "/").replace("~0", "~")
        if not isinstance(current, dict) or token not in current:
            return None
        current = current[token]
    return current if isinstance(current, dict) else None


def _matches_type(value: Any, expected_type: Any) -> bool:
    if expected_type == "object":
        return isinstance(value, dict)
    if expected_type == "array":
        return isinstance(value, list)
    if expected_type == "string":
        return isinstance(value, str)
    if expected_type == "boolean":
        return isinstance(value, bool)
    if expected_type == "integer":
        return _is_number(value) and float(value).is_integer()
    if expected_type == "number":
        return _is_number(value)
    if expected_type == "null":
        return value is None
    return False


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _json_equal(left: Any, right: Any) -> bool:
    if _is_number(left) and _is_number(right):
        return float(left) == float(right)
    return type(left) is type(right) and left == right


def _expected(schema: dict[str, Any], keyword: str, default: str) -> str:
    overrides = schema.get("x-wasd-error", {})
    if isinstance(overrides, dict) and keyword in overrides:
        return str(overrides[keyword])
    return default


def _child_path(parent: str, child: str) -> str:
    return child if not parent or parent == "root" else f"{parent}.{child}"


def _append_error(
    errors: list[dict[str, str]],
    field_path: str,
    expected: str,
) -> None:
    errors.append({"field": field_path, "expected": expected})
