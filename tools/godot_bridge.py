#!/usr/bin/env python3
"""Lightweight bridge commands for Godot project inspection and validation."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from queue import Empty, Queue
from threading import Thread
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PROJECT = ROOT / "client"
COMMON_GODOT_PATHS = [
    Path(r"E:\SteamLibrary\steamapps\common\Godot Engine\godot.exe"),
    Path(r"C:\Program Files\Godot\godot.exe"),
]

STANDARD_FATAL_MARKERS = (
    "SCRIPT ERROR:",
    "Parse Error:",
    "Failed to load script",
    "ERROR:",
)
GUT_FATAL_MARKERS = (*STANDARD_FATAL_MARKERS, "GUT ERROR")
GUT_RUNNER_RESOURCE_PATH = "res://addons/gut/gut_cmdln.gd"
GUT_DEFAULT_TEST_DIRS = (
    "res://tests/unit",
    "res://tests/integration",
)
SMOKE_COMMAND_CATALOG_RELATIVE_PATH = Path("tools") / "smoke_commands.json"
SMOKE_COMMAND_CATALOG_SCHEMA_VERSION = 1
SMOKE_COMMAND_ID_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
BUILTIN_COMMAND_IDS = frozenset(
    {
        "export-tree",
        "validate-data",
        "godot-version",
        "gut",
        "headless-boot",
        "rng-audit",
        "replay-runner",
        "replay-regression",
        "capture-golden-replay",
        "perf-probe",
        "startup-probe",
        "capture-gear-mod-pickup",
        "vfx-bake",
        "module-bake",
        "module-bake-check",
    }
)
SUPPORTED_SMOKE_RUNNER_TYPES = frozenset({"formal_boot", "script", "scene"})
SUPPORTED_FORMAL_BOOT_SETUPS = frozenset(
    {
        "runner_only",
        "show_title_menu",
        "start_gameplay",
        "start_open_warzone",
        "start_module_world_technical",
    }
)
SUPPORTED_SMOKE_PREFLIGHTS = frozenset({"release_debug_resource_exclusion"})
SMOKE_ISOLATION_POLICY = "temporary_user_environment"

NODE_RE = re.compile(r"^\[node\s+(.+)\]$")
EXT_RESOURCE_RE = re.compile(r"^\[ext_resource\s+(?P<attrs>.+)\]$")
ATTR_RE = re.compile(r'(\w+)="([^"]*)"')
SCRIPT_RE = re.compile(r'^script\s*=\s*ExtResource\("(?P<id>[^"]+)"\)')


class SmokeCommandCatalogError(ValueError):
    """Raised when the smoke command catalog violates its fail-closed schema."""


def _load_smoke_command_catalog(
    project: Path = DEFAULT_PROJECT,
) -> dict[str, dict[str, Any]]:
    catalog_path = project / SMOKE_COMMAND_CATALOG_RELATIVE_PATH
    try:
        payload = json.loads(catalog_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SmokeCommandCatalogError(
            f"cannot read smoke command catalog {_rel(catalog_path)}: {error}"
        ) from error
    if not isinstance(payload, dict):
        raise SmokeCommandCatalogError("smoke command catalog root must be an object")
    if payload.get("schema_version") != SMOKE_COMMAND_CATALOG_SCHEMA_VERSION:
        raise SmokeCommandCatalogError(
            "unsupported smoke command catalog schema: "
            f"{payload.get('schema_version')!r}; expected "
            f"{SMOKE_COMMAND_CATALOG_SCHEMA_VERSION}"
        )
    raw_commands = payload.get("commands")
    if not isinstance(raw_commands, list) or not raw_commands:
        raise SmokeCommandCatalogError(
            "smoke command catalog commands must be a non-empty array"
        )

    commands: dict[str, dict[str, Any]] = {}
    for index, raw_descriptor in enumerate(raw_commands):
        if not isinstance(raw_descriptor, dict):
            raise SmokeCommandCatalogError(
                f"smoke command descriptor at index {index} must be an object"
            )
        descriptor = dict(raw_descriptor)
        command_id = descriptor.get("id")
        if not isinstance(command_id, str) or not SMOKE_COMMAND_ID_RE.fullmatch(
            command_id
        ):
            raise SmokeCommandCatalogError(
                f"invalid smoke command id at index {index}: {command_id!r}"
            )
        if command_id in commands:
            raise SmokeCommandCatalogError(
                f"duplicate smoke command id: {command_id}"
            )
        if command_id in BUILTIN_COMMAND_IDS:
            raise SmokeCommandCatalogError(
                f"smoke command id conflicts with built-in command: {command_id}"
            )
        _validate_smoke_command_descriptor(command_id, descriptor)
        commands[command_id] = descriptor
    return commands


def _validate_smoke_command_descriptor(
    command_id: str,
    descriptor: dict[str, Any],
) -> None:
    help_text = descriptor.get("help")
    if not isinstance(help_text, str) or not help_text.strip():
        raise SmokeCommandCatalogError(
            f"smoke command {command_id} requires non-empty help text"
        )
    runner_type = descriptor.get("runner_type")
    if runner_type not in SUPPORTED_SMOKE_RUNNER_TYPES:
        raise SmokeCommandCatalogError(
            f"smoke command {command_id} has unsupported runner_type: "
            f"{runner_type!r}"
        )
    runner_path = descriptor.get("runner_path")
    if (
        not isinstance(runner_path, str)
        or not runner_path.startswith("res://")
        or "\\" in runner_path
        or ".." in runner_path.removeprefix("res://").split("/")
    ):
        raise SmokeCommandCatalogError(
            f"smoke command {command_id} has invalid runner_path: "
            f"{runner_path!r}"
        )
    expected_suffix = ".tscn" if runner_type == "scene" else ".gd"
    if not runner_path.endswith(expected_suffix):
        raise SmokeCommandCatalogError(
            f"smoke command {command_id} runner_path must end in "
            f"{expected_suffix}"
        )
    if descriptor.get("isolation") != SMOKE_ISOLATION_POLICY:
        raise SmokeCommandCatalogError(
            f"smoke command {command_id} must use {SMOKE_ISOLATION_POLICY}"
        )
    if descriptor.get("standard_fatal") is not True:
        raise SmokeCommandCatalogError(
            f"smoke command {command_id} must enable standard_fatal"
        )

    success_markers = _require_string_list(
        command_id,
        descriptor,
        "success_markers",
        allow_empty=False,
    )
    if len(set(success_markers)) != len(success_markers):
        raise SmokeCommandCatalogError(
            f"smoke command {command_id} has duplicate success markers"
        )
    extra_user_args = _require_string_list(
        command_id,
        descriptor,
        "extra_user_args",
        allow_empty=True,
    )
    if "--test-command" in extra_user_args:
        raise SmokeCommandCatalogError(
            f"smoke command {command_id} cannot override --test-command"
        )
    preflight = _require_string_list(
        command_id,
        descriptor,
        "preflight",
        allow_empty=True,
    )
    unsupported_preflight = set(preflight) - SUPPORTED_SMOKE_PREFLIGHTS
    if unsupported_preflight:
        raise SmokeCommandCatalogError(
            f"smoke command {command_id} has unsupported preflight: "
            f"{sorted(unsupported_preflight)}"
        )
    for field_name in (
        "expected_error_allow_patterns",
        "shutdown_allow_patterns",
    ):
        patterns = _require_string_list(
            command_id,
            descriptor,
            field_name,
            allow_empty=True,
        )
        for pattern in patterns:
            if not pattern.startswith("(?m)^") or not pattern.endswith("$"):
                raise SmokeCommandCatalogError(
                    f"smoke command {command_id} {field_name} must use "
                    "whole-line anchored patterns"
                )
            if ".*" in pattern or ".+" in pattern:
                raise SmokeCommandCatalogError(
                    f"smoke command {command_id} {field_name} cannot use "
                    "unbounded wildcard matches"
                )
            try:
                re.compile(pattern)
            except re.error as error:
                raise SmokeCommandCatalogError(
                    f"smoke command {command_id} has invalid {field_name}: "
                    f"{error}"
                ) from error

    if runner_type == "formal_boot":
        runner_node_name = descriptor.get("runner_node_name")
        if not isinstance(runner_node_name, str) or not runner_node_name:
            raise SmokeCommandCatalogError(
                f"smoke command {command_id} requires runner_node_name"
            )
        formal_boot_setup = descriptor.get("formal_boot_setup")
        if formal_boot_setup not in SUPPORTED_FORMAL_BOOT_SETUPS:
            raise SmokeCommandCatalogError(
                f"smoke command {command_id} has unsupported "
                f"formal_boot_setup: {formal_boot_setup!r}"
            )
    elif "runner_node_name" in descriptor or "formal_boot_setup" in descriptor:
        raise SmokeCommandCatalogError(
            f"smoke command {command_id} has FormalClientBoot-only fields"
        )


def _require_string_list(
    command_id: str,
    descriptor: dict[str, Any],
    field_name: str,
    *,
    allow_empty: bool,
) -> list[str]:
    value = descriptor.get(field_name)
    if (
        not isinstance(value, list)
        or (not allow_empty and not value)
        or any(
            not isinstance(item, str) or not item.strip()
            for item in value
        )
    ):
        qualifier = "" if allow_empty else " non-empty"
        raise SmokeCommandCatalogError(
            f"smoke command {command_id} {field_name} must be a{qualifier} "
            "string array"
        )
    return value


def main() -> int:
    requested_command = _requested_command(sys.argv[1:])
    smoke_commands: dict[str, dict[str, Any]] = {}
    if requested_command not in BUILTIN_COMMAND_IDS:
        try:
            smoke_commands = _load_smoke_command_catalog(DEFAULT_PROJECT)
        except SmokeCommandCatalogError as error:
            print(f"[godot-bridge] {error}", file=sys.stderr)
            return 1
    parser = argparse.ArgumentParser(description="Godot bridge for wasd tooling.")
    parser.add_argument("--project", default=str(DEFAULT_PROJECT), help="Godot project directory. Defaults to the formal client.")
    parser.add_argument("--godot", default=None, help="Path to the Godot executable. Defaults to GODOT_PATH or common paths.")

    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser(
        "export-tree",
        help="Export .tscn node trees as JSON without launching Godot.",
    )
    subparsers.add_parser("validate-data", help="Run tools/validate_data.py.")
    subparsers.add_parser(
        "godot-version",
        help="Print the configured Godot version.",
    )
    gut_parser = subparsers.add_parser(
        "gut",
        help=(
            "Run isolated GUT unit and integration tests with fatal-log and "
            "JUnit gates."
        ),
    )
    gut_parser.add_argument(
        "--test-dir",
        action="append",
        default=None,
        help=(
            "Optional test directory below res://tests. Repeat to select "
            "multiple directories; defaults to unit and integration."
        ),
    )
    subparsers.add_parser(
        "headless-boot",
        help="Scan the project in a headless editor, then run a headless project boot.",
    )
    subparsers.add_parser(
        "rng-audit",
        help="Run the RNG cross-stream correlation audit in headless Godot.",
    )
    replay_runner_parser = subparsers.add_parser(
        "replay-runner",
        help="Run the F8 replay summary diff runner in headless Godot.",
    )
    replay_runner_parser.add_argument(
        "--replay-file",
        default=None,
        help="Optional .replay file to validate. Defaults to an internal smoke replay.",
    )
    replay_runner_parser.add_argument(
        "--expectation-file",
        default=None,
        help="Optional JSON summary expectation file.",
    )
    replay_runner_parser.add_argument(
        "--allow-data-fingerprint-mismatch",
        action="store_true",
        help="Allow replay data_fingerprint to differ from the current project data fingerprint.",
    )
    replay_runner_parser.add_argument(
        "--rerun-runtime-summary",
        action="store_true",
        help="Rerun the replay seed through GameplayRunLoop and compare run_summary.",
    )
    replay_regression_parser = subparsers.add_parser(
        "replay-regression",
        help="Run all checked-in golden replays serially in one isolated Godot process.",
    )
    replay_regression_parser.add_argument(
        "--keep-going",
        action="store_true",
        help="Continue after a failed replay so all per-file results are reported.",
    )
    replay_regression_parser.add_argument(
        "--allow-data-fingerprint-mismatch",
        action="store_true",
        help="Diagnostic only: allow golden fingerprints to differ from current data.",
    )
    capture_golden_parser = subparsers.add_parser(
        "capture-golden-replay",
        help="Capture the checked-in F8 golden replay baseline.",
    )
    capture_golden_parser.add_argument(
        "--golden-scenario",
        default=None,
        choices=[
            "golden_basic_run",
            "golden_pause_resume",
            "golden_full_death",
            "golden_reward_choice",
        ],
        help="Golden replay scenario to capture. Defaults to golden_basic_run.",
    )
    subparsers.add_parser(
        "perf-probe",
        help="Run the F8 lightweight perf probe in headless Godot.",
    )
    subparsers.add_parser(
        "startup-probe",
        help=(
            "Measure the first formal-project frame to a playable F13 "
            "module-world run (<=2 seconds)."
        ),
    )
    subparsers.add_parser(
        "capture-gear-mod-pickup",
        help="Capture and probe the formal runtime Gear Mod pickup.",
    )
    subparsers.add_parser(
        "vfx-bake",
        help=(
            "Regenerate built-in VFX presets, composites, and scene-authored "
            "trail components."
        ),
    )
    module_bake_parser = subparsers.add_parser(
        "module-bake",
        help="Bake one canonical generated TSCN scene per module JSON.",
    )
    module_bake_parser.add_argument(
        "--module",
        default=None,
        help="Optional registered module id. Defaults to all modules.",
    )
    module_bake_check_parser = subparsers.add_parser(
        "module-bake-check",
        help="Check canonical module TSCN fingerprints without writing files.",
    )
    module_bake_check_parser.add_argument(
        "--module",
        default=None,
        help="Optional registered module id. Defaults to all modules.",
    )
    for descriptor in smoke_commands.values():
        subparsers.add_parser(
            descriptor["id"],
            help=descriptor["help"],
        )

    args = parser.parse_args()
    project = Path(args.project).resolve()

    if args.command == "export-tree":
        return _export_tree(project)
    if args.command == "validate-data":
        return _run_python_tool("validate_data.py")

    godot = _resolve_godot(args.godot)
    if godot is None:
        print("[godot-bridge] Godot executable not found. Set --godot or GODOT_PATH.")
        return 1
    if args.command == "godot-version":
        return _run_command([str(godot), "--version"], cwd=ROOT)
    if args.command == "gut":
        return _run_gut(
            godot,
            project,
            requested_test_dirs=args.test_dir,
        )
    if args.command in smoke_commands:
        try:
            project_smoke_commands = (
                smoke_commands
                if project == DEFAULT_PROJECT.resolve()
                else _load_smoke_command_catalog(project)
            )
        except SmokeCommandCatalogError as error:
            print(f"[godot-bridge] {error}", file=sys.stderr)
            return 1
        return _run_smoke_command(
            args.command,
            project_smoke_commands,
            godot=godot,
            project=project,
        )
    if args.command == "vfx-bake":
        runner_script = project / "tools" / "vfx_resource_baker.gd"
        if not runner_script.exists():
            print(f"[godot-bridge] missing VFX resource baker: {_rel(runner_script)}")
            return 1
        return _run_command(
            [
                str(godot),
                "--headless",
                "--path",
                str(project),
                "--script",
                "res://tools/vfx_resource_baker.gd",
            ],
            cwd=project,
            failure_markers=("SCRIPT ERROR:", "Parse Error:", "Failed to load script"),
        )
    if args.command in {"module-bake", "module-bake-check"}:
        if not (project / "project.godot").exists():
            print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
            return 1
        runner_script = project / "tools" / "module_bake_cli.gd"
        if not runner_script.exists():
            print(f"[godot-bridge] missing module bake script: {_rel(runner_script)}")
            return 1
        user_args = [f"--{args.command}"]
        if args.module:
            user_args.extend(["--module", args.module])
        return _run_command(
            [str(godot), "--headless", "--path", str(project), "--script", "res://tools/module_bake_cli.gd", "--", *user_args],
            cwd=project,
            failure_markers=("SCRIPT ERROR:", "Parse Error:", "Failed to load script"),
        )
    if args.command == "startup-probe":
        return _run_startup_probe(godot, project)
    if args.command == "headless-boot":
        if not (project / "project.godot").exists():
            print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
            return 1
        editor_result = _run_command(
            [str(godot), "--headless", "--editor", "--path", str(project), "--quit-after", "300"],
            cwd=project,
            failure_markers=("SCRIPT ERROR:", "Parse Error:", "Failed to load script"),
        )
        if editor_result != 0:
            return editor_result
        return _run_command(
            [str(godot), "--headless", "--path", str(project), "--quit"],
            cwd=project,
            failure_markers=("SCRIPT ERROR:", "Parse Error:", "Failed to load script"),
        )
    if args.command == "rng-audit":
        if not (project / "project.godot").exists():
            print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
            return 1
        audit_script = project / "tools" / "rng_audit.gd"
        if not audit_script.exists():
            print(f"[godot-bridge] missing RNG audit script: {_rel(audit_script)}")
            return 1
        return _run_command(
            [str(godot), "--headless", "--path", str(project), "--", "--rng-audit"],
            cwd=project,
        )
    if args.command == "replay-runner":
        if not (project / "project.godot").exists():
            print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
            return 1
        runner_script = project / "tools" / "replay_runner.gd"
        if not runner_script.exists():
            print(f"[godot-bridge] missing Replay runner script: {_rel(runner_script)}")
            return 1
        user_args = ["--replay-runner"]
        if args.replay_file:
            user_args.extend(["--replay-file", str(Path(args.replay_file).resolve())])
        if args.expectation_file:
            user_args.extend(["--expectation-file", str(Path(args.expectation_file).resolve())])
        if args.allow_data_fingerprint_mismatch:
            user_args.append("--allow-data-fingerprint-mismatch")
        if args.rerun_runtime_summary:
            user_args.append("--rerun-runtime-summary")
        return _run_isolated_command(
            [str(godot), "--headless", "--path", str(project), "--", *user_args],
            cwd=project,
            failure_markers=("SCRIPT ERROR:", "Parse Error:", "Failed to load script"),
            success_markers=("[ReplayRunner] passed;",),
        )
    if args.command == "replay-regression":
        if not (project / "project.godot").exists():
            print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
            return 1
        runner_script = project / "tools" / "replay_runner.gd"
        if not runner_script.exists():
            print(f"[godot-bridge] missing Replay runner script: {_rel(runner_script)}")
            return 1
        replay_root = project / "tests" / "replays"
        replay_files = sorted(replay_root.glob("golden_*.replay"))
        if not replay_files:
            print(f"[godot-bridge] no golden replays found under {_rel(replay_root)}")
            return 1
        user_args = ["--replay-runner", "--rerun-runtime-summary"]
        for replay_file in replay_files:
            user_args.extend(["--replay-file", str(replay_file.resolve())])
        if args.keep_going:
            user_args.append("--keep-going")
        if args.allow_data_fingerprint_mismatch:
            user_args.append("--allow-data-fingerprint-mismatch")
        return _run_isolated_command(
            [str(godot), "--headless", "--path", str(project), "--", *user_args],
            cwd=project,
            failure_markers=("SCRIPT ERROR:", "Parse Error:", "Failed to load script"),
            success_markers=("[ReplayRunner] regression passed;",),
        )
    if args.command == "capture-golden-replay":
        if not (project / "project.godot").exists():
            print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
            return 1
        capture_script = project / "tools" / "golden_replay_capture.gd"
        if not capture_script.exists():
            print(f"[godot-bridge] missing golden replay capture script: {_rel(capture_script)}")
            return 1
        user_args = ["--capture-golden-replay"]
        if args.golden_scenario:
            user_args.extend(["--golden-scenario", args.golden_scenario])
        return _run_command([str(godot), "--headless", "--path", str(project), "--", *user_args], cwd=project)
    if args.command == "perf-probe":
        if not (project / "project.godot").exists():
            print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
            return 1
        probe_script = project / "tools" / "perf_probe.gd"
        if not probe_script.exists():
            print(f"[godot-bridge] missing perf probe script: {_rel(probe_script)}")
            return 1
        return _run_command(
            [str(godot), "--headless", "--path", str(project), "--", "--perf-probe"],
            cwd=project,
        )
    if args.command == "capture-gear-mod-pickup":
        capture_script = project / "tools" / "capture_gear_mod_pickup_runtime.gd"
        if not capture_script.exists():
            print(f"[godot-bridge] missing Gear Mod pickup capture script: {_rel(capture_script)}")
            return 1
        return _run_command(
            [
                str(godot),
                "--resolution",
                "1920x1080",
                "--path",
                str(project),
                "--",
                "--capture-gear-mod-pickup",
            ],
            cwd=project,
        )
    print(f"[godot-bridge] unknown command: {args.command}")
    return 1


def _requested_command(arguments: list[str]) -> str | None:
    option_requires_value = {"--project", "--godot"}
    skip_next = False
    for argument in arguments:
        if skip_next:
            skip_next = False
            continue
        if argument in option_requires_value:
            skip_next = True
            continue
        if argument.startswith("--project=") or argument.startswith("--godot="):
            continue
        if argument.startswith("-"):
            continue
        return argument
    return None


def _export_tree(project: Path) -> int:
    if not (project / "project.godot").exists():
        print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
        return 1

    scenes_dir = project / "scenes"
    scene_paths = sorted(scenes_dir.rglob("*.tscn")) if scenes_dir.exists() else []
    payload = {
        "schema_version": 1,
        "project": _rel(project),
        "main_scene": _main_scene(project),
        "scenes": [_parse_scene(project, path) for path in scene_paths],
    }
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


def _parse_scene(project: Path, path: Path) -> dict[str, Any]:
    ext_resources: dict[str, dict[str, str]] = {}
    nodes: list[dict[str, Any]] = []
    current_node: dict[str, Any] | None = None

    for line in path.read_text(encoding="utf-8").splitlines():
        ext_match = EXT_RESOURCE_RE.match(line)
        if ext_match:
            attrs = dict(ATTR_RE.findall(ext_match.group("attrs")))
            resource_id = attrs.get("id")
            if resource_id:
                ext_resources[resource_id] = {
                    "type": attrs.get("type", ""),
                    "path": attrs.get("path", ""),
                }
            current_node = None
            continue

        node_match = NODE_RE.match(line)
        if node_match:
            attrs = dict(ATTR_RE.findall(node_match.group(1)))
            node = {
                "name": attrs.get("name", ""),
                "type": attrs.get("type", ""),
                "parent": attrs.get("parent", ""),
                "path": "",
            }
            nodes.append(node)
            current_node = node
            continue

        if current_node is not None:
            script_match = SCRIPT_RE.match(line)
            if script_match:
                resource = ext_resources.get(script_match.group("id"))
                if resource is not None:
                    current_node["script"] = resource["path"]

    _assign_node_paths(nodes)
    return {
        "path": _rel(path),
        "nodes": nodes,
    }


def _assign_node_paths(nodes: list[dict[str, Any]]) -> None:
    if not nodes:
        return
    root_name = nodes[0].get("name", "root") or "root"
    known: dict[str, str] = {".": root_name, "": root_name}
    nodes[0]["path"] = root_name
    for node in nodes[1:]:
        parent = str(node.get("parent", ""))
        parent_path = known.get(parent, f"{root_name}/{parent}" if parent else root_name)
        node_path = f"{parent_path}/{node.get('name', '')}"
        node["path"] = node_path
        relative_path = node_path.removeprefix(f"{root_name}/")
        known[relative_path] = node_path


def _main_scene(project: Path) -> str | None:
    project_file = project / "project.godot"
    for line in project_file.read_text(encoding="utf-8").splitlines():
        if line.startswith("run/main_scene="):
            return line.split("=", 1)[1].strip().strip('"')
    return None


def _run_python_tool(script_name: str) -> int:
    command = [sys.executable, str(ROOT / "tools" / script_name)]
    return _run_command(command, cwd=ROOT)


def _run_gut(
    godot: Path,
    project: Path,
    *,
    requested_test_dirs: list[str] | None = None,
) -> int:
    if not (project / "project.godot").is_file():
        print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
        return 1
    runner_script = project / GUT_RUNNER_RESOURCE_PATH.removeprefix("res://")
    if not runner_script.is_file():
        print(
            f"[godot-bridge] missing GUT runner: {_rel(runner_script)}",
            file=sys.stderr,
        )
        return 1
    try:
        test_dirs = _normalize_gut_test_dirs(project, requested_test_dirs)
    except ValueError as error:
        print(f"[godot-bridge] {error}", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory(prefix="wasd-gut-") as directory:
        root = Path(directory)
        result_dir = root / "results"
        result_dir.mkdir(parents=True, exist_ok=True)
        junit_path = result_dir / "gut.xml"
        isolated_env = _isolated_user_environment(root / "user")
        command = [
            str(godot),
            "--headless",
            "--path",
            str(project),
            "--script",
            GUT_RUNNER_RESOURCE_PATH,
            f"-gdir={','.join(test_dirs)}",
            "-ginclude_subdirs",
            f"-gjunit_xml_file={junit_path}",
        ]
        run_result = _run_command(
            command,
            cwd=project,
            env=isolated_env,
            failure_markers=GUT_FATAL_MARKERS,
        )
        if run_result != 0:
            return run_result
        return _validate_gut_junit(junit_path)


def _normalize_gut_test_dirs(
    project: Path,
    requested_test_dirs: list[str] | None,
) -> tuple[str, ...]:
    raw_dirs = requested_test_dirs or list(GUT_DEFAULT_TEST_DIRS)
    normalized: list[str] = []
    project_root = project.resolve()
    tests_root = (project_root / "tests").resolve()
    for raw_dir in raw_dirs:
        if not isinstance(raw_dir, str) or not raw_dir.strip():
            raise ValueError("GUT test directories must be non-empty strings")
        value = raw_dir.strip()
        if "\\" in value or "," in value or value.startswith("/"):
            raise ValueError(f"invalid GUT test directory: {raw_dir!r}")
        if value.startswith("res://"):
            relative = value.removeprefix("res://")
        elif value.startswith("tests/"):
            relative = value
        elif "://" not in value and ":" not in value:
            relative = f"tests/{value}"
        else:
            raise ValueError(f"invalid GUT test directory: {raw_dir!r}")
        parts = relative.split("/")
        if (
            len(parts) < 2
            or parts[0] != "tests"
            or any(part in {"", ".", ".."} for part in parts)
        ):
            raise ValueError(
                "GUT test directories must stay below res://tests: "
                f"{raw_dir!r}"
            )
        host_path = project_root.joinpath(*parts).resolve()
        try:
            host_path.relative_to(tests_root)
        except ValueError as error:
            raise ValueError(
                "GUT test directories must stay below res://tests: "
                f"{raw_dir!r}"
            ) from error
        if not host_path.is_dir():
            raise ValueError(
                f"missing GUT test directory: {_rel(host_path)}"
            )
        resource_path = f"res://{'/'.join(parts)}"
        if resource_path not in normalized:
            normalized.append(resource_path)
    if not normalized:
        raise ValueError("at least one GUT test directory is required")
    return tuple(normalized)


def _validate_gut_junit(junit_path: Path) -> int:
    if not junit_path.is_file():
        print(
            f"[godot-bridge] GUT did not create JUnit results: {junit_path}",
            file=sys.stderr,
        )
        return 1
    try:
        root = ET.parse(junit_path).getroot()
    except (OSError, ET.ParseError) as error:
        print(
            f"[godot-bridge] invalid GUT JUnit results {junit_path}: {error}",
            file=sys.stderr,
        )
        return 1
    if root.tag.rsplit("}", 1)[-1] != "testsuites":
        print(
            f"[godot-bridge] invalid GUT JUnit root: {root.tag!r}",
            file=sys.stderr,
        )
        return 1
    try:
        tests = _parse_junit_count(root, "tests", required=True)
        failures = _parse_junit_count(root, "failures", required=True)
        errors = _parse_junit_count(root, "errors", required=False)
    except ValueError as error:
        print(f"[godot-bridge] invalid GUT JUnit results: {error}", file=sys.stderr)
        return 1
    if tests <= 0:
        print("[godot-bridge] GUT JUnit results contain no tests", file=sys.stderr)
        return 1
    if failures != 0 or errors != 0:
        print(
            "[godot-bridge] GUT JUnit results failed: "
            f"tests={tests}, failures={failures}, errors={errors}",
            file=sys.stderr,
        )
        return 1
    print(
        "[godot-bridge] GUT JUnit gate passed: "
        f"tests={tests}, failures={failures}, errors={errors}"
    )
    return 0


def _parse_junit_count(
    root: ET.Element,
    name: str,
    *,
    required: bool,
) -> int:
    raw_value = root.attrib.get(name)
    if raw_value is None:
        if required:
            raise ValueError(f"missing {name!r} attribute")
        raw_value = "0"
    try:
        value = int(raw_value)
    except ValueError as error:
        raise ValueError(
            f"non-integer {name!r} attribute: {raw_value!r}"
        ) from error
    if value < 0:
        raise ValueError(f"negative {name!r} attribute: {value}")
    return value


def _run_startup_probe(godot: Path, project: Path) -> int:
    if not (project / "project.godot").exists():
        print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
        return 1
    budget_seconds = 2.0
    started = time.perf_counter()
    process = subprocess.Popen(
        [str(godot), "--headless", "--path", str(project), "--", "--startup-probe"],
        cwd=project,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    output_queue: Queue[str | None] = Queue()

    def _collect_output() -> None:
        if process.stdout is not None:
            for line in process.stdout:
                output_queue.put(line)
        output_queue.put(None)

    reader = Thread(target=_collect_output, daemon=True)
    reader.start()
    output_lines: list[str] = []
    boot_begin_elapsed_seconds: float | None = None
    marker_elapsed_seconds: float | None = None
    deadline = started + 30.0
    reached_eof = False
    while not reached_eof and time.perf_counter() < deadline:
        try:
            line = output_queue.get(timeout=0.1)
        except Empty:
            continue
        if line is None:
            reached_eof = True
            break
        output_lines.append(line)
        if boot_begin_elapsed_seconds is None and "[StartupProbe] BOOT_BEGIN" in line:
            boot_begin_elapsed_seconds = time.perf_counter() - started
        if marker_elapsed_seconds is None and "[StartupProbe] PLAYABLE" in line:
            marker_elapsed_seconds = time.perf_counter() - started
    if not reached_eof:
        process.kill()
    return_code = process.wait(timeout=5.0)
    reader.join(timeout=1.0)
    while not output_queue.empty():
        line = output_queue.get_nowait()
        if line is not None:
            output_lines.append(line)
    if output_lines:
        print("".join(output_lines), end="")
    marker_found = boot_begin_elapsed_seconds is not None and marker_elapsed_seconds is not None
    elapsed_seconds = (
        marker_elapsed_seconds - boot_begin_elapsed_seconds
        if boot_begin_elapsed_seconds is not None and marker_elapsed_seconds is not None
        else time.perf_counter() - started
    )
    status = "pass" if return_code == 0 and marker_found and elapsed_seconds <= budget_seconds else "fail"
    print(json.dumps({
        "budget_seconds": budget_seconds,
        "elapsed_seconds": round(elapsed_seconds, 6),
        "process_to_boot_begin_seconds": round(boot_begin_elapsed_seconds, 6) if boot_begin_elapsed_seconds is not None else None,
        "marker_found": marker_found,
        "status": status,
    }, ensure_ascii=False, sort_keys=True))
    return 0 if status == "pass" else 1


def _run_command(
    command: list[str],
    *,
    cwd: Path,
    failure_markers: tuple[str, ...] = (),
    success_markers: tuple[str, ...] = (),
    env: dict[str, str] | None = None,
    print_output: bool = True,
    ignored_failure_patterns: tuple[str, ...] = (),
) -> int:
    completed = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        check=False,
    )
    if completed.stdout and print_output:
        print(completed.stdout, end="")
    if completed.stderr and print_output:
        print(completed.stderr, end="", file=sys.stderr)
    combined_output = completed.stdout + completed.stderr
    validation_output = combined_output
    for pattern in ignored_failure_patterns:
        validation_output = re.sub(pattern, "", validation_output)
    if completed.returncode == 0 and any(
        marker in validation_output for marker in failure_markers
    ):
        if not print_output:
            if completed.stdout:
                print(completed.stdout, end="")
            if completed.stderr:
                print(completed.stderr, end="", file=sys.stderr)
        print("[godot-bridge] command output contained a fatal validation marker.", file=sys.stderr)
        return 1
    if completed.returncode == 0 and any(
        marker not in validation_output for marker in success_markers
    ):
        if not print_output:
            if completed.stdout:
                print(completed.stdout, end="")
            if completed.stderr:
                print(completed.stderr, end="", file=sys.stderr)
        print(
            "[godot-bridge] command output missed a required success marker.",
            file=sys.stderr,
        )
        return 1
    if completed.returncode != 0 and not print_output:
        if completed.stdout:
            print(completed.stdout, end="")
        if completed.stderr:
            print(completed.stderr, end="", file=sys.stderr)
    return completed.returncode


def _run_smoke_command(
    smoke_name: str,
    smoke_commands: dict[str, dict[str, Any]],
    *,
    godot: Path,
    project: Path,
) -> int:
    descriptor = smoke_commands.get(smoke_name)
    if descriptor is None:
        print(
            f"[godot-bridge] unknown smoke command: {smoke_name}",
            file=sys.stderr,
        )
        return 1
    if not (project / "project.godot").is_file():
        print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
        return 1
    runner_path = descriptor["runner_path"]
    runner_file = project / runner_path.removeprefix("res://")
    if not runner_file.is_file():
        print(
            f"[godot-bridge] missing smoke runner for {smoke_name}: "
            f"{_rel(runner_file)}",
            file=sys.stderr,
        )
        return 1
    for preflight in descriptor["preflight"]:
        if preflight == "release_debug_resource_exclusion":
            preflight_result = _verify_release_debug_resource_exclusion(
                godot,
                project,
                ignored_failure_patterns=tuple(
                    descriptor["shutdown_allow_patterns"]
                ),
            )
        else:
            print(
                f"[godot-bridge] unsupported smoke preflight for "
                f"{smoke_name}: {preflight}",
                file=sys.stderr,
            )
            return 1
        if preflight_result != 0:
            return preflight_result

    command = _build_smoke_process_command(
        descriptor,
        godot=godot,
        project=project,
    )
    ignored_failure_patterns = tuple(
        descriptor["expected_error_allow_patterns"]
        + descriptor["shutdown_allow_patterns"]
    )
    return _run_isolated_command(
        command,
        cwd=project,
        failure_markers=STANDARD_FATAL_MARKERS,
        success_markers=tuple(descriptor["success_markers"]),
        ignored_failure_patterns=ignored_failure_patterns,
    )


def _build_smoke_process_command(
    descriptor: dict[str, Any],
    *,
    godot: Path,
    project: Path,
) -> list[str]:
    command = [str(godot), "--headless", "--path", str(project)]
    runner_type = descriptor["runner_type"]
    runner_path = descriptor["runner_path"]
    extra_user_args = descriptor["extra_user_args"]
    if runner_type == "formal_boot":
        command.extend(
            ["--", "--test-command", descriptor["id"], *extra_user_args]
        )
    elif runner_type == "script":
        command.extend(["--script", runner_path])
        if extra_user_args:
            command.extend(["--", *extra_user_args])
    elif runner_type == "scene":
        command.append(runner_path)
        if extra_user_args:
            command.extend(["--", *extra_user_args])
    else:
        raise SmokeCommandCatalogError(
            f"smoke command {descriptor.get('id', '<unknown>')} has unsupported "
            f"runner_type: {runner_type!r}"
        )
    return command


def _run_isolated_command(
    command: list[str],
    *,
    cwd: Path,
    failure_markers: tuple[str, ...] = (),
    success_markers: tuple[str, ...] = (),
    ignored_failure_patterns: tuple[str, ...] = (),
) -> int:
    with tempfile.TemporaryDirectory(prefix="wasd-godot-user-") as directory:
        root = Path(directory)
        isolated_env = _isolated_user_environment(root)
        return _run_command(
            command,
            cwd=cwd,
            failure_markers=failure_markers,
            success_markers=success_markers,
            env=isolated_env,
            ignored_failure_patterns=ignored_failure_patterns,
        )


def _isolated_user_environment(root: Path) -> dict[str, str]:
    appdata = root / "AppData" / "Roaming"
    local_appdata = root / "AppData" / "Local"
    xdg_data = root / "xdg-data"
    xdg_config = root / "xdg-config"
    xdg_cache = root / "xdg-cache"
    for path in (
        appdata,
        local_appdata,
        xdg_data,
        xdg_config,
        xdg_cache,
    ):
        path.mkdir(parents=True, exist_ok=True)
    isolated_env = os.environ.copy()
    isolated_env.update(
        {
            "APPDATA": str(appdata),
            "LOCALAPPDATA": str(local_appdata),
            "XDG_DATA_HOME": str(xdg_data),
            "XDG_CONFIG_HOME": str(xdg_config),
            "XDG_CACHE_HOME": str(xdg_cache),
            "HOME": str(root),
            "USERPROFILE": str(root),
        }
    )
    return isolated_env


def _verify_release_debug_resource_exclusion(
    godot: Path,
    project: Path,
    *,
    ignored_failure_patterns: tuple[str, ...] = (),
) -> int:
    checker = ROOT / "tools" / "release_debug_resource_check.gd"
    if not checker.exists():
        print(
            "[godot-bridge] missing release resource checker: "
            f"{_rel(checker)}",
            file=sys.stderr,
        )
        return 1
    with tempfile.TemporaryDirectory(
        prefix="wasd-release-debug-check-"
    ) as directory:
        check_root = Path(directory)
        isolated_env = _isolated_user_environment(check_root / "user")
        pack_path = check_root / "wasd-release.pck"
        export_result = _run_command(
            [
                str(godot),
                "--headless",
                "--path",
                str(project),
                "--export-pack",
                "Windows Desktop",
                str(pack_path),
            ],
            cwd=project,
            failure_markers=(*STANDARD_FATAL_MARKERS, "Failed to export"),
            ignored_failure_patterns=ignored_failure_patterns,
            env=isolated_env,
            print_output=False,
        )
        if export_result != 0:
            return export_result
        if not pack_path.is_file():
            print(
                "[godot-bridge] release export did not create a PCK.",
                file=sys.stderr,
            )
            return 1
        return _run_command(
            [
                str(godot),
                "--headless",
                "--main-pack",
                str(pack_path),
                "--script",
                str(checker),
            ],
            cwd=check_root,
            failure_markers=(
                *STANDARD_FATAL_MARKERS,
                "exported debug resource:",
            ),
            success_markers=("RELEASE DEBUG RESOURCE CHECK PASS",),
            ignored_failure_patterns=ignored_failure_patterns,
            env=isolated_env,
        )


def _resolve_godot(argument: str | None) -> Path | None:
    candidates: list[Path] = []
    if argument:
        candidates.append(Path(argument))
    env_path = os.environ.get("GODOT_PATH")
    if env_path:
        candidates.append(Path(env_path))
    candidates.extend(COMMON_GODOT_PATHS)

    for candidate in candidates:
        if candidate.exists():
            return candidate.resolve()
    return None


def _rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return path.as_posix()


if __name__ == "__main__":
    sys.exit(main())
