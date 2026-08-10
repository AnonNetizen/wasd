#!/usr/bin/env python3
"""Focused regression tests for the Godot bridge smoke safety policy."""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools import godot_bridge


class GodotBridgeTests(unittest.TestCase):
    def test_isolated_command_preserves_outer_user_directories(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            environment_paths = {
                "APPDATA": root / "appdata",
                "LOCALAPPDATA": root / "local_appdata",
                "XDG_DATA_HOME": root / "xdg_data",
                "XDG_CONFIG_HOME": root / "xdg_config",
                "XDG_CACHE_HOME": root / "xdg_cache",
                "HOME": root / "home",
                "USERPROFILE": root / "profile",
            }
            sentinels: list[Path] = []
            for path in environment_paths.values():
                path.mkdir(parents=True)
                sentinel = path / "sentinel.txt"
                sentinel.write_text("preserve", encoding="utf-8")
                sentinels.append(sentinel)

            probe = (
                "import os, pathlib, sys; "
                "pathlib.Path(os.environ['APPDATA'], 'probe.txt').write_text('isolated'); "
                "print('SMOKE PASS'); sys.exit(int(sys.argv[1]))"
            )
            with mock.patch.dict(
                os.environ,
                {key: str(value) for key, value in environment_paths.items()},
            ):
                success_result = godot_bridge._run_isolated_command(
                    [sys.executable, "-c", probe, "0"],
                    cwd=root,
                    failure_markers=godot_bridge.STANDARD_FATAL_MARKERS,
                    success_markers=("SMOKE PASS",),
                )
                failure_result = godot_bridge._run_isolated_command(
                    [sys.executable, "-c", probe, "7"],
                    cwd=root,
                    failure_markers=godot_bridge.STANDARD_FATAL_MARKERS,
                    success_markers=("SMOKE PASS",),
                )

            self.assertEqual(success_result, 0)
            self.assertEqual(failure_result, 7)
            for sentinel in sentinels:
                self.assertEqual(sentinel.read_text(encoding="utf-8"), "preserve")
                self.assertFalse((sentinel.parent / "probe.txt").exists())

    def test_success_marker_is_required(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            result = godot_bridge._run_command(
                [sys.executable, "-c", "print('completed without marker')"],
                cwd=Path(temporary_directory),
                success_markers=("SMOKE PASS",),
                print_output=False,
            )
        self.assertEqual(result, 1)

    def test_expected_error_allowlist_does_not_hide_extra_error(self) -> None:
        expected_error = "ERROR: expected negative fixture"
        expected_pattern = r"(?m)^ERROR: expected negative fixture\r?$"
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            accepted = godot_bridge._run_command(
                [sys.executable, "-c", f"print({expected_error!r}); print('SMOKE PASS')"],
                cwd=root,
                failure_markers=godot_bridge.STANDARD_FATAL_MARKERS,
                success_markers=("SMOKE PASS",),
                ignored_failure_patterns=(expected_pattern,),
                print_output=False,
            )
            rejected = godot_bridge._run_command(
                [
                    sys.executable,
                    "-c",
                    (
                        f"print({expected_error!r}); "
                        "print('ERROR: unexpected failure'); print('SMOKE PASS')"
                    ),
                ],
                cwd=root,
                failure_markers=godot_bridge.STANDARD_FATAL_MARKERS,
                success_markers=("SMOKE PASS",),
                ignored_failure_patterns=(expected_pattern,),
                print_output=False,
            )

        self.assertEqual(accepted, 0)
        self.assertEqual(rejected, 1)

    def test_shutdown_leak_allowance_is_command_scoped(self) -> None:
        leak_line = "ERROR: 3 resources still in use at exit"
        ordinary_name = "actor-scene-smoke"
        allowed_name = "input-smoke"
        ordinary_marker = godot_bridge.HEADLESS_SMOKE_SUCCESS_MARKERS[ordinary_name]
        allowed_marker = godot_bridge.HEADLESS_SMOKE_SUCCESS_MARKERS[allowed_name]
        probe = "print(%r); print(%r)"
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            ordinary_result = godot_bridge._run_smoke_command(
                ordinary_name,
                [sys.executable, "-c", probe % (ordinary_marker, leak_line)],
                cwd=root,
            )
            allowed_result = godot_bridge._run_smoke_command(
                allowed_name,
                [sys.executable, "-c", probe % (allowed_marker, leak_line)],
                cwd=root,
            )

        self.assertNotIn(
            ordinary_name,
            godot_bridge.HEADLESS_SMOKE_ALLOW_KNOWN_SHUTDOWN_LEAKS,
        )
        self.assertIn(
            allowed_name,
            godot_bridge.HEADLESS_SMOKE_ALLOW_KNOWN_SHUTDOWN_LEAKS,
        )
        self.assertEqual(ordinary_result, 1)
        self.assertEqual(allowed_result, 0)


if __name__ == "__main__":
    unittest.main()
