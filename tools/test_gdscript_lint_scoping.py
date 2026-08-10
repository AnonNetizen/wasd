#!/usr/bin/env python3
"""Regression tests for project-owned versus vendored GDScript lint scope."""

from __future__ import annotations

from pathlib import Path

import lint_gdscript_rules
import lint_semantic_rules


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    vendored_script = root / "client" / "addons" / "gut" / "vendor_probe.gd"
    neighboring_addon = root / "client" / "addons" / "gut_helper" / "probe.gd"
    project_test = root / "client" / "tests" / "unit" / "probe.gd"

    for lint_module in (lint_gdscript_rules, lint_semantic_rules):
        assert lint_module._is_ignored(vendored_script), lint_module.__name__
        assert not lint_module._is_ignored(neighboring_addon), lint_module.__name__
        assert not lint_module._is_ignored(project_test), lint_module.__name__

    print("GDScript lint scope tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
