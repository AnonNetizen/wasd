#!/usr/bin/env python3
"""Focused regression tests for the Godot bridge smoke and GUT runners."""

from __future__ import annotations

import copy
import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tools import godot_bridge


LEGACY_SMOKE_COMMANDS = frozenset(
    {
        "module-bake-smoke",
        "module-json-editor-smoke",
        "data-table-editor-smoke",
        "world-event-smoke",
        "actor-scene-smoke",
        "l1-smoke",
        "replay-smoke",
        "replay-input-smoke",
        "content-progression-smoke",
        "codex-smoke",
        "input-smoke",
        "debug-tools-smoke",
        "debug-tools-release-smoke",
        "debug-test-arena-smoke",
        "f9-demo-smoke",
        "runtime-smoke",
        "f4-smoke",
        "loading-smoke",
        "module-world-smoke",
        "module-world-technical-slice-smoke",
        "teleporter-smoke",
        "save-smoke",
        "gear-mod-smoke",
        "mod-loader-smoke",
        "effect-runtime-smoke",
        "gear-mod-pickup-smoke",
        "settings-smoke",
        "ui-manager-smoke",
        "vfx-smoke",
    }
)

PASSING_GUT_JUNIT = (
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<testsuites name="GutTests" tests="2" failures="0">\n'
    '</testsuites>'
)


def _create_gut_project(
    project: Path,
    *,
    include_unit: bool = True,
    include_integration: bool = True,
) -> None:
    project.mkdir(parents=True, exist_ok=True)
    (project / "project.godot").write_text("[application]\n", encoding="utf-8")
    runner = project / "addons" / "gut" / "gut_cmdln.gd"
    runner.parent.mkdir(parents=True, exist_ok=True)
    runner.write_text("extends SceneTree\n", encoding="utf-8")
    if include_unit:
        (project / "tests" / "unit").mkdir(parents=True, exist_ok=True)
    if include_integration:
        (project / "tests" / "integration").mkdir(
            parents=True,
            exist_ok=True,
        )


def _gut_junit_path(command: list[str]) -> Path:
    prefix = "-gjunit_xml_file="
    argument = next(item for item in command if item.startswith(prefix))
    return Path(argument.removeprefix(prefix))


class GodotBridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.catalog = godot_bridge._load_smoke_command_catalog()

    def test_catalog_is_complete_and_fail_closed(self) -> None:
        self.assertEqual(set(self.catalog), LEGACY_SMOKE_COMMANDS)
        for command_id, descriptor in self.catalog.items():
            with self.subTest(command=command_id):
                self.assertEqual(
                    descriptor["isolation"],
                    godot_bridge.SMOKE_ISOLATION_POLICY,
                )
                self.assertIs(descriptor["standard_fatal"], True)
                self.assertTrue(descriptor["success_markers"])
                runner_file = (
                    godot_bridge.DEFAULT_PROJECT
                    / descriptor["runner_path"].removeprefix("res://")
                )
                self.assertTrue(runner_file.is_file(), runner_file)
                for field_name in (
                    "expected_error_allow_patterns",
                    "shutdown_allow_patterns",
                ):
                    for pattern in descriptor[field_name]:
                        self.assertTrue(pattern.startswith("(?m)^"))
                        self.assertTrue(pattern.endswith("$"))
                        self.assertNotIn("RID allocations of type .+", pattern)
                        re.compile(pattern)

    def test_all_legacy_cli_names_route_through_the_catalog(self) -> None:
        fake_godot = ROOT / "fake-godot.exe"
        for command_id in sorted(LEGACY_SMOKE_COMMANDS):
            with self.subTest(command=command_id):
                with (
                    mock.patch.object(
                        sys,
                        "argv",
                        ["godot_bridge.py", command_id],
                    ),
                    mock.patch.dict(
                        os.environ,
                        {
                            godot_bridge.PROJECT_EXECUTION_MODE_ENV:
                            godot_bridge.PROJECT_EXECUTION_MODE_ISOLATED,
                        },
                    ),
                    mock.patch.object(
                        godot_bridge,
                        "_resolve_godot",
                        return_value=fake_godot,
                    ),
                    mock.patch.object(
                        godot_bridge,
                        "_run_smoke_command",
                        return_value=0,
                    ) as run_smoke,
                ):
                    result = godot_bridge.main()
                self.assertEqual(result, 0)
                self.assertEqual(run_smoke.call_args.args[0], command_id)
                self.assertIsNotNone(run_smoke.call_args.args[1])

    def test_process_commands_cover_all_runner_types(self) -> None:
        fake_godot = Path("godot.exe")
        project = godot_bridge.DEFAULT_PROJECT.resolve()
        formal = godot_bridge._build_smoke_process_command(
            self.catalog["runtime-smoke"],
            godot=fake_godot,
            project=project,
        )
        script = godot_bridge._build_smoke_process_command(
            self.catalog["module-bake-smoke"],
            godot=fake_godot,
            project=project,
        )
        scene = godot_bridge._build_smoke_process_command(
            self.catalog["debug-test-arena-smoke"],
            godot=fake_godot,
            project=project,
        )

        self.assertEqual(
            formal[-3:],
            ["--", "--test-command", "runtime-smoke"],
        )
        self.assertEqual(
            script[-2:],
            ["--script", "res://tools/module_bake_smoke.gd"],
        )
        self.assertEqual(
            scene[-2:],
            ["--", "--debug-test-arena-smoke"],
        )
        self.assertIn("res://scenes/debug/debug_test_arena.tscn", scene)

    def test_every_formal_runner_uses_only_the_generic_test_hook(self) -> None:
        fake_godot = Path("godot.exe")
        project = godot_bridge.DEFAULT_PROJECT.resolve()
        for command_id, descriptor in self.catalog.items():
            if descriptor["runner_type"] != "formal_boot":
                continue
            with self.subTest(command=command_id):
                command = godot_bridge._build_smoke_process_command(
                    descriptor,
                    godot=fake_godot,
                    project=project,
                )
                separator = command.index("--")
                self.assertEqual(
                    command[separator + 1 : separator + 3],
                    ["--test-command", command_id],
                )
                self.assertNotIn(f"--{command_id}", command)

    def test_runtime_compatibility_alias_keeps_identical_policy(self) -> None:
        runtime = self.catalog["runtime-smoke"]
        compatibility_alias = self.catalog["f4-smoke"]
        for field_name in (
            "runner_type",
            "runner_path",
            "runner_node_name",
            "formal_boot_setup",
            "extra_user_args",
            "preflight",
            "isolation",
            "success_markers",
            "standard_fatal",
            "expected_error_allow_patterns",
            "shutdown_allow_patterns",
        ):
            with self.subTest(field=field_name):
                self.assertEqual(
                    compatibility_alias[field_name],
                    runtime[field_name],
                )

    def test_every_command_propagates_its_catalog_policy(self) -> None:
        fake_godot = ROOT / "fake-godot.exe"
        with (
            mock.patch.object(
                godot_bridge,
                "_run_isolated_command",
                return_value=0,
            ) as run_isolated,
            mock.patch.object(
                godot_bridge,
                "_verify_release_debug_resource_exclusion",
                return_value=0,
            ) as release_preflight,
        ):
            for command_id, descriptor in self.catalog.items():
                with self.subTest(command=command_id):
                    result = godot_bridge._run_smoke_command(
                        command_id,
                        self.catalog,
                        godot=fake_godot,
                        project=godot_bridge.DEFAULT_PROJECT,
                    )
                    self.assertEqual(result, 0)
                    kwargs = run_isolated.call_args.kwargs
                    self.assertEqual(
                        kwargs["failure_markers"],
                        godot_bridge.STANDARD_FATAL_MARKERS,
                    )
                    self.assertEqual(
                        kwargs["success_markers"],
                        tuple(descriptor["success_markers"]),
                    )
                    self.assertEqual(
                        kwargs["ignored_failure_patterns"],
                        tuple(
                            descriptor["expected_error_allow_patterns"]
                            + descriptor["shutdown_allow_patterns"]
                        ),
                    )
                    run_isolated.reset_mock()
        release_preflight.assert_called_once()
        release_descriptor = self.catalog["debug-tools-release-smoke"]
        self.assertEqual(
            release_preflight.call_args.kwargs["ignored_failure_patterns"],
            tuple(release_descriptor["shutdown_allow_patterns"]),
        )

    def test_builtin_command_does_not_depend_on_smoke_catalog(self) -> None:
        with (
            mock.patch.object(
                sys,
                "argv",
                ["godot_bridge.py", "validate-data"],
            ),
            mock.patch.object(
                godot_bridge,
                "_load_smoke_command_catalog",
                side_effect=godot_bridge.SmokeCommandCatalogError("broken"),
            ) as load_catalog,
            mock.patch.object(
                godot_bridge,
                "_run_python_tool",
                return_value=0,
            ) as run_python_tool,
        ):
            result = godot_bridge.main()

        self.assertEqual(result, 0)
        load_catalog.assert_not_called()
        run_python_tool.assert_called_once_with("validate_data.py")

    def test_gut_builtin_does_not_depend_on_smoke_catalog(self) -> None:
        fake_godot = ROOT / "fake-godot.exe"
        with (
            mock.patch.object(
                sys,
                "argv",
                ["godot_bridge.py", "gut"],
            ),
            mock.patch.object(
                godot_bridge,
                "_load_smoke_command_catalog",
                side_effect=godot_bridge.SmokeCommandCatalogError("broken"),
            ) as load_catalog,
            mock.patch.object(
                godot_bridge,
                "_resolve_godot",
                return_value=fake_godot,
            ),
            mock.patch.dict(
                os.environ,
                {
                    godot_bridge.PROJECT_EXECUTION_MODE_ENV:
                    godot_bridge.PROJECT_EXECUTION_MODE_ISOLATED,
                },
            ),
            mock.patch.object(
                godot_bridge,
                "_run_gut",
                return_value=0,
            ) as run_gut,
        ):
            result = godot_bridge.main()

        self.assertEqual(result, 0)
        load_catalog.assert_not_called()
        run_gut.assert_called_once_with(
            fake_godot,
            godot_bridge.DEFAULT_PROJECT.resolve(),
            requested_test_dirs=None,
        )

    def test_read_only_main_command_routes_through_project_snapshot(self) -> None:
        fake_godot = ROOT / "fake-godot.exe"
        with (
            mock.patch.object(
                sys,
                "argv",
                ["godot_bridge.py", "gut", "--test-dir", "unit"],
            ),
            mock.patch.object(
                godot_bridge,
                "_resolve_godot",
                return_value=fake_godot,
            ),
            mock.patch.object(
                godot_bridge,
                "_run_isolated_project_command",
                return_value=0,
            ) as run_isolated,
            mock.patch.object(
                godot_bridge,
                "_run_gut",
            ) as run_gut,
        ):
            result = godot_bridge.main()

        self.assertEqual(result, 0)
        run_isolated.assert_called_once_with(
            ["gut", "--test-dir", "unit"],
            godot_bridge.DEFAULT_PROJECT.resolve(),
        )
        run_gut.assert_not_called()

    def test_source_writing_main_command_routes_through_exclusive_lock(self) -> None:
        fake_godot = ROOT / "fake-godot.exe"
        with (
            mock.patch.object(
                sys,
                "argv",
                ["godot_bridge.py", "vfx-bake"],
            ),
            mock.patch.object(
                godot_bridge,
                "_resolve_godot",
                return_value=fake_godot,
            ),
            mock.patch.object(
                godot_bridge,
                "_run_exclusive_project_command",
                return_value=0,
            ) as run_exclusive,
        ):
            result = godot_bridge.main()

        self.assertEqual(result, 0)
        run_exclusive.assert_called_once_with(
            ["vfx-bake"],
            godot_bridge.DEFAULT_PROJECT.resolve(),
        )

    def test_source_writing_command_set_is_explicit(self) -> None:
        self.assertEqual(
            godot_bridge.PROJECT_MUTATING_COMMAND_IDS,
            {
                "capture-gear-mod-pickup",
                "capture-golden-replay",
                "module-bake",
                "vfx-bake",
            },
        )

    def test_project_argument_rewrite_is_stable_and_deduplicated(self) -> None:
        project = Path("C:/isolated/project")
        self.assertEqual(
            godot_bridge._replace_project_argument(
                [
                    "--godot",
                    "C:/Godot/godot.exe",
                    "--project=old-project",
                    "gut",
                    "--test-dir",
                    "unit",
                ],
                project,
            ),
            [
                "--project",
                str(project.resolve()),
                "--godot",
                "C:/Godot/godot.exe",
                "gut",
                "--test-dir",
                "unit",
            ],
        )

    def test_project_snapshot_keeps_only_reusable_cache_seed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source = root / "source"
            destination = root / "destination"
            (source / "scripts").mkdir(parents=True)
            (source / "scripts" / "example.gd").write_text(
                "extends Node\n",
                encoding="utf-8",
            )
            (source / "project.godot").write_text(
                "[application]\n",
                encoding="utf-8",
            )
            (source / ".godot" / "imported").mkdir(parents=True)
            (source / ".godot" / "imported" / "asset.ctex").write_bytes(
                b"asset"
            )
            (source / ".godot" / "editor").mkdir()
            (source / ".godot" / "editor" / "volatile.cfg").write_text(
                "volatile",
                encoding="utf-8",
            )
            (source / ".godot" / "global_script_class_cache.cfg").write_text(
                "cache",
                encoding="utf-8",
            )
            (source / ".godot" / "export_credentials.cfg").write_text(
                "secret",
                encoding="utf-8",
            )

            godot_bridge._copy_project_snapshot(source, destination)

            self.assertTrue((destination / "project.godot").is_file())
            self.assertTrue((destination / "scripts" / "example.gd").is_file())
            self.assertTrue(
                (destination / ".godot" / "imported" / "asset.ctex").is_file()
            )
            self.assertTrue(
                (
                    destination
                    / ".godot"
                    / "global_script_class_cache.cfg"
                ).is_file()
            )
            self.assertFalse((destination / ".godot" / "editor").exists())
            self.assertFalse(
                (destination / ".godot" / "export_credentials.cfg").exists()
            )

    def test_project_snapshot_retries_when_source_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source = root / "source"
            destination = root / "destination"
            _create_gut_project(source)
            first = (("project.godot", 1, 1),)
            changed = (("project.godot", 2, 2),)
            stable = (("project.godot", 3, 3),)

            with mock.patch.object(
                godot_bridge,
                "_project_source_manifest",
                side_effect=[first, changed, stable, stable],
            ) as manifest:
                godot_bridge._copy_project_snapshot(source, destination)

            self.assertEqual(manifest.call_count, 4)
            self.assertTrue((destination / "project.godot").is_file())

    def test_isolated_project_command_reexecutes_with_private_roots(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            project = Path(temporary_directory) / "source"
            _create_gut_project(project)
            captured: dict[str, object] = {}

            def fake_run(
                command: list[str],
                **kwargs: object,
            ) -> int:
                captured["command"] = command
                captured["env"] = kwargs["env"]
                return 0

            with mock.patch.object(
                godot_bridge,
                "_run_command",
                side_effect=fake_run,
            ):
                result = godot_bridge._run_isolated_project_command(
                    ["--project", str(project), "gut"],
                    project,
                )

        self.assertEqual(result, 0)
        command = captured["command"]
        self.assertEqual(command[0], sys.executable)
        project_index = command.index("--project")
        self.assertNotEqual(
            Path(command[project_index + 1]),
            project.resolve(),
        )
        environment = captured["env"]
        self.assertEqual(
            environment[godot_bridge.PROJECT_EXECUTION_MODE_ENV],
            godot_bridge.PROJECT_EXECUTION_MODE_ISOLATED,
        )
        self.assertEqual(environment["PYTHONIOENCODING"], "utf-8")
        self.assertEqual(environment["PYTHONUTF8"], "1")

    def test_exclusive_project_command_keeps_source_project(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            project = Path(temporary_directory) / "source"
            _create_gut_project(project)
            captured: dict[str, object] = {}

            def fake_run(
                command: list[str],
                **kwargs: object,
            ) -> int:
                captured["command"] = command
                captured["env"] = kwargs["env"]
                return 0

            with mock.patch.object(
                godot_bridge,
                "_run_command",
                side_effect=fake_run,
            ):
                result = godot_bridge._run_exclusive_project_command(
                    ["--project", str(project), "vfx-bake"],
                    project,
                )

        self.assertEqual(result, 0)
        command = captured["command"]
        project_index = command.index("--project")
        self.assertEqual(
            Path(command[project_index + 1]),
            project.resolve(),
        )
        environment = captured["env"]
        self.assertEqual(
            environment[godot_bridge.PROJECT_EXECUTION_MODE_ENV],
            godot_bridge.PROJECT_EXECUTION_MODE_EXCLUSIVE,
        )

    def test_process_output_falls_back_for_console_encoding(self) -> None:
        class AsciiStream:
            encoding = "ascii"

            def __init__(self) -> None:
                self.value = ""

            def write(self, text: str) -> None:
                text.encode(self.encoding)
                self.value += text

        stream = AsciiStream()

        godot_bridge._write_process_output("Godot \ufffd output", stream=stream)

        self.assertEqual(stream.value, "Godot ? output")

    def test_gut_runner_isolates_user_data_and_runs_default_suites(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            project = root / "project"
            _create_gut_project(project)
            outer_paths = {
                "APPDATA": root / "outer_appdata",
                "LOCALAPPDATA": root / "outer_local_appdata",
                "XDG_DATA_HOME": root / "outer_xdg_data",
                "XDG_CONFIG_HOME": root / "outer_xdg_config",
                "XDG_CACHE_HOME": root / "outer_xdg_cache",
                "HOME": root / "outer_home",
                "USERPROFILE": root / "outer_profile",
            }
            sentinels: list[Path] = []
            for path in outer_paths.values():
                path.mkdir(parents=True)
                sentinel = path / "sentinel.txt"
                sentinel.write_text("preserve", encoding="utf-8")
                sentinels.append(sentinel)

            captured_commands: list[list[str]] = []
            captured_environments: list[dict[str, str]] = []

            def fake_run(command: list[str], **kwargs: object) -> object:
                environment = kwargs["env"]
                self.assertIsInstance(environment, dict)
                captured_commands.append(command)
                captured_environments.append(environment)
                Path(environment["APPDATA"], "probe.txt").write_text(
                    "isolated",
                    encoding="utf-8",
                )
                if "--import" not in command:
                    _gut_junit_path(command).write_text(
                        PASSING_GUT_JUNIT,
                        encoding="utf-8",
                    )
                return subprocess.CompletedProcess(
                    command,
                    0,
                    stdout=(
                        "Import completed\n"
                        if "--import" in command
                        else "GUT completed\n"
                    ),
                    stderr="",
                )

            with (
                mock.patch.dict(
                    os.environ,
                    {key: str(value) for key, value in outer_paths.items()},
                ),
                mock.patch.object(
                    godot_bridge.subprocess,
                    "run",
                    side_effect=fake_run,
                ),
            ):
                result = godot_bridge._run_gut(
                    root / "fake-godot.exe",
                    project,
                )

            self.assertEqual(result, 0)
            self.assertEqual(len(captured_commands), 2)
            self.assertEqual(
                captured_commands[0],
                [
                    str(root / "fake-godot.exe"),
                    "--headless",
                    "--path",
                    str(project),
                    "--import",
                ],
            )
            gut_command = captured_commands[1]
            self.assertIn(godot_bridge.GUT_RUNNER_RESOURCE_PATH, gut_command)
            self.assertIn(
                "-gdir=res://tests/unit,res://tests/integration",
                gut_command,
            )
            self.assertIn("-ginclude_subdirs", gut_command)
            self.assertIs(
                captured_environments[0],
                captured_environments[1],
            )
            isolated_env = captured_environments[0]
            for key, outer_path in outer_paths.items():
                self.assertNotEqual(isolated_env[key], str(outer_path))
            for sentinel in sentinels:
                self.assertEqual(
                    sentinel.read_text(encoding="utf-8"),
                    "preserve",
                )
                self.assertFalse((sentinel.parent / "probe.txt").exists())

    def test_gut_runner_stops_when_import_reports_fatal_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            project = root / "project"
            _create_gut_project(project)

            with mock.patch.object(
                godot_bridge.subprocess,
                "run",
                return_value=subprocess.CompletedProcess(
                    ["fake-godot", "--import"],
                    0,
                    stdout="ERROR: import failed\n",
                    stderr="",
                ),
            ) as run_process:
                result = godot_bridge._run_gut(
                    root / "fake-godot.exe",
                    project,
                )

        self.assertEqual(result, 1)
        run_process.assert_called_once()
        self.assertIn("--import", run_process.call_args.args[0])

    def test_gut_runner_rejects_missing_suite_before_launch(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            project = root / "project"
            _create_gut_project(project, include_integration=False)
            with mock.patch.object(
                godot_bridge.subprocess,
                "run",
            ) as run_process:
                result = godot_bridge._run_gut(
                    root / "fake-godot.exe",
                    project,
                )

        self.assertEqual(result, 1)
        run_process.assert_not_called()

    def test_gut_runner_rejects_exit_zero_gut_error(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            project = root / "project"
            _create_gut_project(project)

            def fake_run(command: list[str], **_kwargs: object) -> object:
                if "--import" in command:
                    return subprocess.CompletedProcess(
                        command,
                        0,
                        stdout="Import completed\n",
                        stderr="",
                    )
                _gut_junit_path(command).write_text(
                    PASSING_GUT_JUNIT,
                    encoding="utf-8",
                )
                return subprocess.CompletedProcess(
                    command,
                    0,
                    stdout="GUT ERROR could not load test script\n",
                    stderr="",
                )

            with mock.patch.object(
                godot_bridge.subprocess,
                "run",
                side_effect=fake_run,
            ):
                result = godot_bridge._run_gut(
                    root / "fake-godot.exe",
                    project,
                )

        self.assertEqual(result, 1)

    def test_gut_runner_requires_nonempty_passing_junit(self) -> None:
        junit_cases = {
            "missing": None,
            "empty": "",
            "no_tests": '<testsuites tests="0" failures="0"/>',
            "failure": '<testsuites tests="2" failures="1"/>',
            "error": (
                '<testsuites tests="2" failures="0" errors="1"/>'
            ),
        }
        for case_name, junit_text in junit_cases.items():
            with self.subTest(case=case_name):
                with tempfile.TemporaryDirectory() as temporary_directory:
                    root = Path(temporary_directory)
                    project = root / "project"
                    _create_gut_project(project)

                    def fake_run(
                        command: list[str],
                        **_kwargs: object,
                    ) -> object:
                        if "--import" in command:
                            return subprocess.CompletedProcess(
                                command,
                                0,
                                stdout="Import completed\n",
                                stderr="",
                            )
                        if junit_text is not None:
                            _gut_junit_path(command).write_text(
                                junit_text,
                                encoding="utf-8",
                            )
                        return subprocess.CompletedProcess(
                            command,
                            0,
                            stdout="GUT completed\n",
                            stderr="",
                        )

                    with mock.patch.object(
                        godot_bridge.subprocess,
                        "run",
                        side_effect=fake_run,
                    ):
                        result = godot_bridge._run_gut(
                            root / "fake-godot.exe",
                            project,
                        )

                self.assertEqual(result, 1)

    def test_gut_test_dir_override_stays_below_project_tests(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            project = Path(temporary_directory) / "project"
            _create_gut_project(project)
            self.assertEqual(
                godot_bridge._normalize_gut_test_dirs(project, ["unit"]),
                ("res://tests/unit",),
            )
            for invalid_path in ("../unit", "user://tests", "C:/tests"):
                with self.subTest(path=invalid_path):
                    with self.assertRaises(ValueError):
                        godot_bridge._normalize_gut_test_dirs(
                            project,
                            [invalid_path],
                        )

    def test_release_preflight_propagates_shutdown_policy(self) -> None:
        patterns = (r"(?m)^ERROR: exact shutdown fixture\r?$",)

        def fake_run(command: list[str], **_kwargs: object) -> int:
            if "--export-pack" in command:
                export_index = command.index("--export-pack")
                Path(command[export_index + 2]).write_bytes(b"fixture")
            return 0

        with mock.patch.object(
            godot_bridge,
            "_run_command",
            side_effect=fake_run,
        ) as run_command:
            result = godot_bridge._verify_release_debug_resource_exclusion(
                ROOT / "fake-godot.exe",
                godot_bridge.DEFAULT_PROJECT,
                ignored_failure_patterns=patterns,
            )

        self.assertEqual(result, 0)
        self.assertEqual(run_command.call_count, 2)
        for call in run_command.call_args_list:
            self.assertEqual(
                call.kwargs["ignored_failure_patterns"],
                patterns,
            )

    def test_unknown_smoke_command_fails_closed(self) -> None:
        with mock.patch.object(
            godot_bridge,
            "_run_isolated_command",
        ) as run_isolated:
            result = godot_bridge._run_smoke_command(
                "unknown-smoke",
                self.catalog,
                godot=ROOT / "fake-godot.exe",
                project=godot_bridge.DEFAULT_PROJECT,
            )
        self.assertEqual(result, 1)
        run_isolated.assert_not_called()

    def test_catalog_rejects_duplicate_and_unanchored_policies(self) -> None:
        source_path = (
            godot_bridge.DEFAULT_PROJECT
            / godot_bridge.SMOKE_COMMAND_CATALOG_RELATIVE_PATH
        )
        payload = json.loads(source_path.read_text(encoding="utf-8"))
        cases = {}
        duplicate = copy.deepcopy(payload)
        duplicate["commands"].append(copy.deepcopy(duplicate["commands"][0]))
        cases["duplicate"] = duplicate
        unanchored = copy.deepcopy(payload)
        unanchored["commands"][0]["shutdown_allow_patterns"] = ["ERROR: broad"]
        cases["unanchored"] = unanchored
        broad = copy.deepcopy(payload)
        broad["commands"][0]["shutdown_allow_patterns"] = [
            r"(?m)^ERROR: .*$"
        ]
        cases["broad"] = broad
        blank_marker = copy.deepcopy(payload)
        blank_marker["commands"][0]["success_markers"] = [" "]
        cases["blank_marker"] = blank_marker
        built_in_collision = copy.deepcopy(payload)
        built_in_collision["commands"][0]["id"] = "headless-boot"
        cases["built_in_collision"] = built_in_collision

        for case_name, case_payload in cases.items():
            with self.subTest(case=case_name):
                with tempfile.TemporaryDirectory() as temporary_directory:
                    project = Path(temporary_directory)
                    catalog_path = (
                        project
                        / godot_bridge.SMOKE_COMMAND_CATALOG_RELATIVE_PATH
                    )
                    catalog_path.parent.mkdir(parents=True)
                    catalog_path.write_text(
                        json.dumps(case_payload),
                        encoding="utf-8",
                    )
                    with self.assertRaises(
                        godot_bridge.SmokeCommandCatalogError
                    ):
                        godot_bridge._load_smoke_command_catalog(project)

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

    def test_release_preflight_preserves_outer_user_directories(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            project = root / "project"
            project.mkdir()
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

            captured_environments: list[dict[str, str]] = []

            def fake_run(command: list[str], **kwargs: object) -> object:
                environment = kwargs["env"]
                self.assertIsInstance(environment, dict)
                captured_environments.append(environment)
                Path(environment["APPDATA"], "probe.txt").write_text(
                    "isolated",
                    encoding="utf-8",
                )
                if "--export-pack" in command:
                    Path(command[-1]).write_bytes(b"test-pack")
                    stdout = ""
                else:
                    stdout = "RELEASE DEBUG RESOURCE CHECK PASS\n"
                return subprocess.CompletedProcess(
                    command,
                    0,
                    stdout=stdout,
                    stderr="",
                )

            with (
                mock.patch.dict(
                    os.environ,
                    {key: str(value) for key, value in environment_paths.items()},
                ),
                mock.patch.object(
                    godot_bridge.subprocess,
                    "run",
                    side_effect=fake_run,
                ),
            ):
                result = godot_bridge._verify_release_debug_resource_exclusion(
                    root / "fake-godot.exe",
                    project,
                )

            self.assertEqual(result, 0)
            self.assertEqual(len(captured_environments), 2)
            for environment in captured_environments:
                for key, outer_path in environment_paths.items():
                    self.assertNotEqual(environment[key], str(outer_path))
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
                [
                    sys.executable,
                    "-c",
                    f"print({expected_error!r}); print('SMOKE PASS')",
                ],
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

    def test_shutdown_allowlist_is_exact_and_command_scoped(self) -> None:
        descriptor = self.catalog["input-smoke"]
        marker = descriptor["success_markers"][0]
        known_lines = [
            (
                "ERROR: 25 RID allocations of type "
                "'PN13RendererDummy14TextureStorage12DummyTextureE' "
                "were leaked at exit."
            ),
            (
                "ERROR: 2 RID allocations of type "
                "'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit."
            ),
            "ERROR: 41 resources still in use at exit (run with --verbose for details).",
        ]
        unexpected_line = (
            "ERROR: 1 RID allocations of type 'UnexpectedType' were leaked at exit."
        )

        def probe(lines: list[str]) -> list[str]:
            script = "; ".join(f"print({line!r})" for line in [marker, *lines])
            return [sys.executable, "-c", script]

        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            accepted = godot_bridge._run_command(
                probe(known_lines),
                cwd=root,
                failure_markers=godot_bridge.STANDARD_FATAL_MARKERS,
                success_markers=(marker,),
                ignored_failure_patterns=tuple(
                    descriptor["shutdown_allow_patterns"]
                ),
                print_output=False,
            )
            unexpected = godot_bridge._run_command(
                probe([*known_lines, unexpected_line]),
                cwd=root,
                failure_markers=godot_bridge.STANDARD_FATAL_MARKERS,
                success_markers=(marker,),
                ignored_failure_patterns=tuple(
                    descriptor["shutdown_allow_patterns"]
                ),
                print_output=False,
            )
            ordinary = godot_bridge._run_command(
                probe(known_lines),
                cwd=root,
                failure_markers=godot_bridge.STANDARD_FATAL_MARKERS,
                success_markers=(marker,),
                print_output=False,
            )

        self.assertEqual(accepted, 0)
        self.assertEqual(unexpected, 1)
        self.assertEqual(ordinary, 1)

    def test_module_world_policy_is_exact_for_both_runners(self) -> None:
        descriptor = self.catalog["module-world-smoke"]
        technical = self.catalog["module-world-technical-slice-smoke"]
        self.assertEqual(
            descriptor["expected_error_allow_patterns"],
            technical["expected_error_allow_patterns"],
        )
        self.assertEqual(
            descriptor["shutdown_allow_patterns"],
            technical["shutdown_allow_patterns"],
        )
        marker = descriptor["success_markers"][0]
        known_lines = [
            "ERROR: [ModuleWorldManager] snapshot map hash does not match assignment",
            "ERROR: [GameplayRunLoop] module-world snapshot restore failed",
            (
                "ERROR: 32 RID allocations of type "
                "'PN13RendererDummy14TextureStorage12DummyTextureE' "
                "were leaked at exit."
            ),
            (
                "ERROR: 2 RID allocations of type "
                "'PN18TextServerAdvanced12FontAdvancedE' were leaked at exit."
            ),
            "ERROR: 41 resources still in use at exit (run with --verbose for details).",
        ]

        def probe(lines: list[str]) -> list[str]:
            script = "; ".join(f"print({line!r})" for line in [marker, *lines])
            return [sys.executable, "-c", script]

        patterns = tuple(
            descriptor["expected_error_allow_patterns"]
            + descriptor["shutdown_allow_patterns"]
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            accepted = godot_bridge._run_command(
                probe(known_lines),
                cwd=root,
                failure_markers=godot_bridge.STANDARD_FATAL_MARKERS,
                success_markers=(marker,),
                ignored_failure_patterns=patterns,
                print_output=False,
            )
            rejected = godot_bridge._run_command(
                probe([*known_lines, "ERROR: unexpected module-world failure"]),
                cwd=root,
                failure_markers=godot_bridge.STANDARD_FATAL_MARKERS,
                success_markers=(marker,),
                ignored_failure_patterns=patterns,
                print_output=False,
            )

        self.assertEqual(accepted, 0)
        self.assertEqual(rejected, 1)


if __name__ == "__main__":
    unittest.main()
