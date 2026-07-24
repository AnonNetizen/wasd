#!/usr/bin/env python3
"""Second-tier project rule lint for data, locale, and release boundaries."""

from __future__ import annotations

import csv
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
CLIENT_DATA = ROOT / "client" / "data"
DATA_README = CLIENT_DATA / "README.md"
LOCALE_CSV = ROOT / "client" / "locale" / "strings.csv"
EXPORT_PRESETS = ROOT / "client" / "export_presets.cfg"

IGNORE_DATA_FILES = {"_contracts.json"}
IGNORED_FIELD_LEAVES = {"schema_version"}
DEBUG_RESOURCE_RE = re.compile(r"(?:^|[/_\\-])(?:debug|dev_tools|gm_|debug_console)(?:[/_\\.-]|$)", re.IGNORECASE)
REQUIRED_RELEASE_DEBUG_EXCLUDES = {
    "scenes/debug/*",
    "scripts/debug/*",
    "tools/debug_test_arena_smoke.gd",
    "tools/debug_tools_smoke.gd",
}


@dataclass(frozen=True)
class LintError:
    path: Path
    field: str
    rule: str
    message: str

    def format(self) -> str:
        return f"[project-rules-lint] {_rel(self.path)}:{self.field}: {self.rule}: {self.message}"


def main() -> int:
    _configure_utf8_output()

    errors: list[LintError] = []
    errors.extend(_check_data_fields_documented())
    errors.extend(_check_locale_bilingual())
    errors.extend(_check_release_presets())

    if errors:
        for error in sorted(errors, key=lambda item: (_rel(item.path), item.field, item.rule)):
            print(error.format())
        return 1

    print("project rules lint passed")
    return 0


def _configure_utf8_output() -> None:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")


def _check_data_fields_documented() -> list[LintError]:
    errors: list[LintError] = []
    if not DATA_README.exists():
        return [
            LintError(
                DATA_README,
                "$",
                "data-readme-fields",
                "client/data/README.md is required to document data fields",
            )
        ]

    text = DATA_README.read_text(encoding="utf-8")
    documented_tokens = _documented_field_tokens(text)

    for path in _data_files():
        for field_path in _data_field_paths(path):
            if _is_ignored_field(field_path):
                continue
            if not _is_documented_field(field_path, documented_tokens):
                errors.append(
                    LintError(
                        path,
                        field_path,
                        "data-readme-fields",
                        "data field is not documented in client/data/README.md",
                    )
                )

    return errors


def _check_locale_bilingual() -> list[LintError]:
    errors: list[LintError] = []
    if not LOCALE_CSV.exists():
        return [LintError(LOCALE_CSV, "$", "locale-bilingual", "missing locale CSV")]

    with LOCALE_CSV.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        fieldnames = reader.fieldnames or []
        for required in ("keys", "zh_CN", "en"):
            if required not in fieldnames:
                errors.append(
                    LintError(
                        LOCALE_CSV,
                        "header",
                        "locale-bilingual",
                        f"missing required column {required}",
                    )
                )
        if errors:
            return errors

        seen: set[str] = set()
        for line_number, row in enumerate(reader, start=2):
            key = (row.get("keys") or "").strip()
            if not key:
                errors.append(LintError(LOCALE_CSV, f"line {line_number}", "locale-bilingual", "empty locale key"))
                continue
            if key in seen:
                errors.append(
                    LintError(LOCALE_CSV, f"line {line_number}", "locale-bilingual", f"duplicate locale key {key}")
                )
            seen.add(key)
            for locale in ("zh_CN", "en"):
                if not (row.get(locale) or "").strip():
                    errors.append(
                        LintError(
                            LOCALE_CSV,
                            f"line {line_number}",
                            "locale-bilingual",
                            f"missing {locale} translation for {key}",
                        )
                    )

    return errors


def _check_release_presets() -> list[LintError]:
    if not EXPORT_PRESETS.exists():
        return []

    errors: list[LintError] = []
    presets: dict[str, dict[str, tuple[str, int]]] = {}
    current_section = ""
    preset_section_re = re.compile(r"preset\.\d+")

    for line_number, raw_line in enumerate(
        EXPORT_PRESETS.read_text(encoding="utf-8").splitlines(),
        start=1,
    ):
        line = raw_line.strip()
        if not line or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            current_section = line[1:-1]
            continue
        if (
            "=" not in line
            or preset_section_re.fullmatch(current_section) is None
        ):
            continue

        key, raw_value = line.split("=", 1)
        key = key.strip()
        value = _unquote(raw_value.strip())
        presets.setdefault(current_section, {})[key] = (value, line_number)

    for section, values in presets.items():
        name = values.get("name", ("", 0))[0]
        export_path = values.get("export_path", ("", 0))[0]
        if _value_mentions_debug(name) or _value_mentions_debug(export_path):
            continue

        custom_features, features_line = values.get(
            "custom_features",
            ("", 0),
        )
        if _contains_debug_feature(custom_features):
            errors.append(
                LintError(
                    EXPORT_PRESETS,
                    f"line {features_line}",
                    "release-debug-assets",
                    "release preset custom_features must not include "
                    f"debug/dev_tools: {custom_features}",
                )
            )
        for key in ("include_filter", "export_files", "resources"):
            value, line_number = values.get(key, ("", 0))
            if value and DEBUG_RESOURCE_RE.search(value):
                errors.append(
                    LintError(
                        EXPORT_PRESETS,
                        f"line {line_number}",
                        "release-debug-assets",
                        "release preset must not include debug/dev_tools "
                        f"resources in {section}:{key}",
                    )
                )

        exclude_filter, exclude_line = values.get(
            "exclude_filter",
            ("", 0),
        )
        excluded = {
            item.strip().replace("\\", "/").removeprefix("res://")
            for item in exclude_filter.split(",")
            if item.strip()
        }
        missing = sorted(REQUIRED_RELEASE_DEBUG_EXCLUDES - excluded)
        if missing:
            errors.append(
                LintError(
                    EXPORT_PRESETS,
                    f"line {exclude_line}" if exclude_line > 0 else section,
                    "release-debug-assets",
                    "release preset must explicitly exclude test-arena "
                    f"resources: {', '.join(missing)}",
                )
            )

    return errors


def _data_files() -> list[Path]:
    if not CLIENT_DATA.exists():
        return []
    paths = [
        path
        for path in CLIENT_DATA.iterdir()
        if path.is_file() and path.name not in IGNORE_DATA_FILES and path.suffix.lower() in {".json", ".csv"}
    ]
    return sorted(paths)


def _data_field_paths(path: Path) -> set[str]:
    if path.suffix.lower() == ".csv":
        with path.open(encoding="utf-8-sig", newline="") as handle:
            return {field.strip() for field in (csv.DictReader(handle).fieldnames or []) if field.strip()}

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return set()

    fields: set[str] = set()
    _collect_json_fields(data, "", fields)
    return fields


def _collect_json_fields(data: Any, prefix: str, fields: set[str]) -> None:
    if isinstance(data, dict):
        for key, value in data.items():
            if not isinstance(key, str):
                continue
            path = f"{prefix}.{key}" if prefix else key
            if isinstance(value, dict):
                _collect_json_fields(value, path, fields)
            elif isinstance(value, list):
                if not value or all(not isinstance(item, (dict, list)) for item in value):
                    fields.add(path)
                _collect_json_fields(value, path, fields)
            else:
                fields.add(path)
    elif isinstance(data, list):
        array_prefix = f"{prefix}[]" if prefix else "[]"
        for item in data:
            _collect_json_fields(item, array_prefix, fields)


def _documented_field_tokens(text: str) -> set[str]:
    tokens = set(re.findall(r"(?<!`)`([^`\n]+?)`(?!`)", text))
    return {
        token.strip()
        for token in tokens
        if token.strip()
        and "/" not in token
        and "," not in token
        and not token.strip().endswith((".json", ".csv", ".md", ".gd", ".py"))
        and " " not in token.strip()
    }


def _is_ignored_field(field_path: str) -> bool:
    leaf = field_path.rsplit(".", 1)[-1].removesuffix("[]")
    return leaf in IGNORED_FIELD_LEAVES


def _is_documented_field(field_path: str, documented_tokens: set[str]) -> bool:
    if field_path in documented_tokens:
        return True

    normalized_path = field_path.replace("[]", "")
    leaf = field_path.rsplit(".", 1)[-1].removesuffix("[]")
    for token in documented_tokens:
        if token == leaf:
            return True
        if token.startswith("*."):
            token_suffix = token[2:]
            if field_path.endswith(f".{token_suffix}") or field_path == token_suffix:
                return True
        if "*" in token and _token_pattern(token).search(field_path):
            return True
        if field_path.endswith(f".{token}") or normalized_path.endswith(f".{token.replace('[]', '')}"):
            return True
    return False


def _token_pattern(token: str) -> re.Pattern[str]:
    escaped = re.escape(token)
    escaped = escaped.replace(r"\*", r"[^.]+")
    return re.compile(escaped)


def _contains_debug_feature(value: str) -> bool:
    features = {item.strip().lower() for item in value.split(",") if item.strip()}
    return bool(features.intersection({"debug", "dev_tools"}))


def _value_mentions_debug(value: str) -> bool:
    lowered = value.lower()
    return "debug" in lowered or "dev_tools" in lowered


def _unquote(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] == '"':
        return value[1:-1]
    return value


def _rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return path.as_posix()


if __name__ == "__main__":
    sys.exit(main())
