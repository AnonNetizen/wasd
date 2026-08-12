#!/usr/bin/env python3
"""Load and validate the ordered declarative project-data schema catalog."""

from __future__ import annotations

import csv
import json
from pathlib import Path
from typing import Any

from declarative_schema import ValidationContext, validate


def validate_catalog(data_root: Path) -> dict[str, Any]:
    schema_root = data_root / "schemas"
    catalog_path = schema_root / "catalog.json"
    errors: list[dict[str, str]] = []
    counts: dict[str, int] = {}
    references = _catalog_references(data_root)
    try:
        catalog = _load_json(catalog_path)
    except (OSError, json.JSONDecodeError) as error:
        return _result([_error(catalog_path, "root", f"readable JSON ({error})")], counts)
    if not isinstance(catalog, dict) or catalog.get("schema_version") != 1:
        return _result([_error(catalog_path, "schema_version", "must equal 1")], counts)
    sources = catalog.get("sources")
    if not isinstance(sources, list):
        return _result([_error(catalog_path, "sources", "must be an array")], counts)

    seen_sources: set[str] = set()
    seen_schemas: set[str] = set()
    for index, raw_entry in enumerate(sources):
        entry_path = f"sources[{index}]"
        if not isinstance(raw_entry, dict):
            errors.append(_error(catalog_path, entry_path, "must be an object"))
            continue
        source = raw_entry.get("source")
        format_id = raw_entry.get("format")
        schema_name = raw_entry.get("schema")
        if not all(isinstance(item, str) and item for item in (source, format_id, schema_name)):
            errors.append(_error(catalog_path, entry_path, "must name source, format, and schema"))
            continue
        if format_id not in {"csv", "json", "json-glob"}:
            errors.append(_error(catalog_path, f"{entry_path}.format", "must be csv, json, or json-glob"))
            continue
        if source in seen_sources or schema_name in seen_schemas:
            errors.append(_error(catalog_path, entry_path, "must be unique"))
            continue
        seen_sources.add(source)
        seen_schemas.add(schema_name)
        schema_path = schema_root / schema_name
        try:
            schema = _load_json(schema_path)
        except (OSError, json.JSONDecodeError) as error:
            errors.append(_error(schema_path, "root", f"readable JSON ({error})"))
            continue
        paths = sorted(data_root.glob(source))
        if not paths:
            errors.append(_error(data_root / source, "root", "existing data source"))
            continue
        for source_path in paths:
            value, headers, read_error = _read_source(source_path, format_id)
            if read_error:
                errors.append(_error(source_path, "root", read_error))
                continue
            result = validate(
                schema,
                value,
                context=ValidationContext(
                    references=references,
                    headers=headers,
                ),
            )
            counts.update(result["counts"])
            for issue in result["errors"]:
                errors.append(
                    _error(source_path, issue["field"], issue["expected"])
                )
    return _result(errors, counts)


def _read_source(
    path: Path,
    format_id: str,
) -> tuple[Any, dict[str, list[str]], str]:
    try:
        if format_id == "csv":
            with path.open(encoding="utf-8-sig", newline="") as handle:
                reader = csv.DictReader(handle)
                rows = list(reader)
                return rows, {path.name: list(reader.fieldnames or [])}, ""
        return _load_json(path), {}, ""
    except (OSError, json.JSONDecodeError, csv.Error) as error:
        return None, {}, f"readable {format_id} ({error})"


def _catalog_references(data_root: Path) -> dict[str, Any]:
    references: dict[str, Any] = {}
    try:
        contracts = _load_json(data_root / "_contracts.json").get("contracts", {})
        if isinstance(contracts, dict):
            for key, values in contracts.items():
                if isinstance(values, list):
                    references[f"contract:{key}"] = values
    except (AttributeError, OSError, json.JSONDecodeError):
        pass
    locale_path = data_root.parent / "locale" / "strings.csv"
    try:
        with locale_path.open(encoding="utf-8-sig", newline="") as handle:
            references["locale"] = [
                row["keys"]
                for row in csv.DictReader(handle)
                if row.get("keys")
            ]
    except (OSError, csv.Error):
        references["locale"] = []
    return references


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _error(path: Path, field: str, expected: str) -> dict[str, str]:
    return {"path": path.as_posix(), "field": field, "expected": expected}


def _result(errors: list[dict[str, str]], counts: dict[str, int]) -> dict[str, Any]:
    return {"ok": not errors, "errors": errors, "counts": counts}
