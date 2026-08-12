#!/usr/bin/env python3
"""Fast in-process conformance and canonical DataLoader schema checks."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from declarative_schema import ValidationContext, validate, validate_schema
import validate_data


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "client" / "tests" / "fixtures" / "schema_conformance.json"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Run shared schema conformance fixtures in process."
    )
    parser.add_argument(
        "--jobs",
        type=int,
        default=1,
        help="compatibility option; fixtures are intentionally single-process",
    )
    args = parser.parse_args(argv)
    if args.jobs < 1:
        parser.error("--jobs must be at least 1")

    payload = json.loads(FIXTURES.read_text(encoding="utf-8"))
    cases = payload.get("cases", [])
    failures: list[str] = []
    for case in cases:
        failure = _run_case(case)
        if failure:
            failures.append(failure)
    if failures:
        for failure in failures:
            print(f"[schema-fixture] {failure}")
        return 1

    print(f"schema conformance passed ({len(cases)} cases)")
    return validate_data.main()


def _run_case(case: dict[str, Any]) -> str:
    name = str(case.get("name", "unnamed"))
    schema = case.get("schema")
    if case.get("mode") == "schema":
        actual_errors = validate_schema(schema)
        actual_counts: dict[str, int] = {}
    else:
        context = _context_from_fixture(case.get("context", {}))
        result = validate(
            schema,
            case.get("value"),
            context=context,
            field_path=str(case.get("field_path", "root")),
        )
        actual_errors = result["errors"]
        actual_counts = result["counts"]
    expected_errors = case.get("errors", [])
    expected_counts = case.get("counts", {})
    if actual_errors != expected_errors:
        return f"{name}: errors {actual_errors!r} != {expected_errors!r}"
    if actual_counts != expected_counts:
        return f"{name}: counts {actual_counts!r} != {expected_counts!r}"
    return ""


def _context_from_fixture(payload: Any) -> ValidationContext:
    if not isinstance(payload, dict):
        return ValidationContext()
    semantic_rules = {
        rule_id: _fixture_semantic_handler(rule_id)
        for rule_id in payload.get("semantic_rules", [])
    }
    return ValidationContext(
        references=dict(payload.get("references", {})),
        semantic_rules=semantic_rules,
        counts=dict(payload.get("counts", {})),
        headers=dict(payload.get("headers", {})),
    )


def _fixture_semantic_handler(rule_id: str):
    def handler(
        _value: Any,
        field_path: str,
        _context: ValidationContext,
    ) -> list[dict[str, str]]:
        if rule_id == "fixture_accept":
            return []
        if rule_id == "fixture_reject":
            return [
                {
                    "field": f"{field_path}.semantic",
                    "expected": "fixture semantic failure",
                }
            ]
        return []

    return handler


if __name__ == "__main__":
    raise SystemExit(main())
