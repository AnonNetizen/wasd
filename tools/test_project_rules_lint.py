#!/usr/bin/env python3
"""Regression tests for tools/lint_project_rules.py."""

from __future__ import annotations

import json
import tempfile
from pathlib import Path

import lint_project_rules


def main() -> int:
    tests = [
        ("golden project rules pass", _test_golden_project_rules_pass),
        ("undocumented data field fails", _test_undocumented_data_field_fails),
        ("missing locale translation fails", _test_missing_locale_translation_fails),
        ("release preset dev tools fail", _test_release_preset_dev_tools_fail),
    ]

    for name, test in tests:
        try:
            test()
        except AssertionError as exc:
            print(f"[project-rules-lint-test] {name}: failed: {exc}")
            return 1
        print(f"[project-rules-lint-test] {name}: passed")

    print("project rules lint tests passed")
    return 0


def _test_golden_project_rules_pass() -> None:
    with _temporary_project() as root:
        _write_minimal_project(root)
        _with_project_root(root)
        assert not lint_project_rules._check_data_fields_documented()
        assert not lint_project_rules._check_locale_bilingual()
        assert not lint_project_rules._check_release_presets()


def _test_undocumented_data_field_fails() -> None:
    with _temporary_project() as root:
        _write_minimal_project(root, item={"id": "item_a", "rarity": "rare"})
        _with_project_root(root)
        errors = lint_project_rules._check_data_fields_documented()
        assert any(error.field == "items[].rarity" for error in errors), [error.format() for error in errors]


def _test_missing_locale_translation_fails() -> None:
    with _temporary_project() as root:
        _write_minimal_project(root, locale_en="")
        _with_project_root(root)
        errors = lint_project_rules._check_locale_bilingual()
        assert any("missing en translation" in error.message for error in errors), [error.format() for error in errors]


def _test_release_preset_dev_tools_fail() -> None:
    with _temporary_project() as root:
        _write_minimal_project(root)
        (root / "client" / "export_presets.cfg").write_text(
            "\n".join(
                [
                    "[preset.0]",
                    'name="Windows"',
                    'export_path="build/windows/wasd.exe"',
                    'custom_features="dev_tools"',
                    "",
                ]
            ),
            encoding="utf-8",
        )
        _with_project_root(root)
        errors = lint_project_rules._check_release_presets()
        assert any(error.rule == "release-debug-assets" for error in errors), [error.format() for error in errors]


def _write_minimal_project(root: Path, *, item: dict[str, str] | None = None, locale_en: str = "Play") -> None:
    data_dir = root / "client" / "data"
    locale_dir = root / "client" / "locale"
    data_dir.mkdir(parents=True)
    locale_dir.mkdir(parents=True)

    (data_dir / "README.md").write_text(
        "\n".join(
            [
                "# Data",
                "",
                "| 字段路径 | 说明 |",
                "|----------|------|",
                "| `items[].id` | item id |",
                "",
            ]
        ),
        encoding="utf-8",
    )
    (data_dir / "items.json").write_text(
        json.dumps({"schema_version": 1, "items": [item or {"id": "item_a"}]}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    (locale_dir / "strings.csv").write_text(f"keys,zh_CN,en\nui_play,开始,{locale_en}\n", encoding="utf-8")


class _temporary_project:
    def __enter__(self) -> Path:
        self._directory = tempfile.TemporaryDirectory()
        return Path(self._directory.name)

    def __exit__(self, exc_type: object, exc_value: object, traceback: object) -> None:
        self._directory.cleanup()


def _with_project_root(root: Path) -> None:
    lint_project_rules.ROOT = root
    lint_project_rules.CLIENT_DATA = root / "client" / "data"
    lint_project_rules.DATA_README = lint_project_rules.CLIENT_DATA / "README.md"
    lint_project_rules.LOCALE_CSV = root / "client" / "locale" / "strings.csv"
    lint_project_rules.EXPORT_PRESETS = root / "client" / "export_presets.cfg"


if __name__ == "__main__":
    raise SystemExit(main())
