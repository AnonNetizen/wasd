#!/usr/bin/env python3
"""Regression tests for tools/docs_health_check.py."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import docs_health_check


class DocsHealthCheckTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self._write_clean_fixture()

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_clean_repository_passes_without_machine_index(self) -> None:
        self.assertFalse((self.root / "docs/_kb_index.json").exists())
        self.assertEqual([], docs_health_check.check_repository(self.root))

    def test_dead_markdown_link_fails(self) -> None:
        self._write("docs/guide.md", "# Guide\n\n[missing](missing.md)\n")
        self._assert_error("missing Markdown link target")

    def test_invalid_doc_reference_fails(self) -> None:
        self._write("client/scripts/example.gd", "# Doc: docs/代码/missing.md\nextends Node\n")
        self._assert_error("invalid # Doc: path")

    def test_duplicate_adr_fails(self) -> None:
        self._write(
            "docs/决策记录.md",
            "# ADR\n\n| 1 | 2026-01-01 | A | A |\n| 1 | 2026-01-02 | B | B |\n",
        )
        self._assert_error("duplicate ADR number")

    def test_current_state_old_field_fails(self) -> None:
        state = self._state()
        state["latest_adr"] = 205
        self._write_json("docs/AI记忆/current_state.json", state)
        self._assert_error("keys must be exactly")

    def test_current_state_over_8_kib_fails(self) -> None:
        state = self._state()
        state["summary"] = "x" * (8 * 1024)
        self._write_json("docs/AI记忆/current_state.json", state)
        self._assert_error("exceeds 8 KiB")

    def test_adapter_without_shared_rule_fails(self) -> None:
        self._write(".codex/rules/game-coding-rules.md", "# Codex rules\n")
        self._assert_error("does not reference docs/AI协作/项目规则.md")

    def test_retired_path_reference_fails(self) -> None:
        self._write("docs/guide.md", "旧入口：docs\\_kb_index.json\n")
        self._assert_error("retired documentation path referenced")

    def _write_clean_fixture(self) -> None:
        self._write("docs/AI协作/项目规则.md", "# Shared rules\n")
        self._write("docs/TODO.md", "# TODO\n")
        self._write(
            "docs/决策记录.md",
            "# ADR\n\n| 1 | 2026-01-01 | A | A |\n| 2 | 2026-01-02 | B | B |\n",
        )
        self._write("docs/代码/README.md", "# Modules\n")
        self._write_json("docs/AI记忆/current_state.json", self._state())
        for adapter in docs_health_check.ADAPTERS:
            self._write(adapter.as_posix(), "Read `docs/AI协作/项目规则.md`.\n")

    def _state(self) -> dict[str, object]:
        return {
            "schema_version": 2,
            "updated_at": "2026-08-12",
            "phase": "test",
            "summary": "test fixture",
            "active_plan": "docs/TODO.md",
            "protocols": {"meta": 4, "run": 20, "replay": 10, "game": "1.19"},
            "blockers": [],
        }

    def _write_json(self, relative: str, value: object) -> None:
        self._write(relative, json.dumps(value, ensure_ascii=False, indent=2) + "\n")

    def _write(self, relative: str, text: str) -> None:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def _assert_error(self, fragment: str) -> None:
        errors = docs_health_check.check_repository(self.root)
        self.assertTrue(
            any(fragment in error for error in errors),
            msg=f"expected {fragment!r} in errors: {errors}",
        )


if __name__ == "__main__":
    unittest.main()
