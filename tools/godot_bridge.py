#!/usr/bin/env python3
"""Lightweight bridge commands for Godot project inspection and validation."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
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

NODE_RE = re.compile(r"^\[node\s+(.+)\]$")
EXT_RESOURCE_RE = re.compile(r"^\[ext_resource\s+(?P<attrs>.+)\]$")
ATTR_RE = re.compile(r'(\w+)="([^"]*)"')
SCRIPT_RE = re.compile(r'^script\s*=\s*ExtResource\("(?P<id>[^"]+)"\)')


def main() -> int:
    parser = argparse.ArgumentParser(description="Godot bridge for wasd tooling.")
    parser.add_argument("--project", default=str(DEFAULT_PROJECT), help="Godot project directory. Defaults to the formal client.")
    parser.add_argument("--godot", default=None, help="Path to the Godot executable. Defaults to GODOT_PATH or common paths.")

    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("export-tree", help="Export .tscn node trees as JSON without launching Godot.")
    subparsers.add_parser("validate-data", help="Run tools/validate_data.py.")
    subparsers.add_parser("godot-version", help="Print the configured Godot version.")
    subparsers.add_parser(
        "headless-boot",
        help="Scan the project in a headless editor, then run a headless project boot.",
    )
    subparsers.add_parser("l1-smoke", help="Run the F8 temporary L1 infrastructure smoke in headless Godot.")
    subparsers.add_parser("replay-smoke", help="Run the F8 replay file roundtrip smoke in headless Godot.")
    subparsers.add_parser("replay-input-smoke", help="Run the F8 replay gameplay input recording smoke in headless Godot.")
    subparsers.add_parser("input-smoke", help="Run the G.U.I.D.E and InputService integration smoke in headless Godot.")
    subparsers.add_parser("rng-audit", help="Run the RNG cross-stream correlation audit in headless Godot.")
    replay_runner_parser = subparsers.add_parser("replay-runner", help="Run the F8 replay summary diff runner in headless Godot.")
    replay_runner_parser.add_argument("--replay-file", default=None, help="Optional .replay file to validate. Defaults to an internal smoke replay.")
    replay_runner_parser.add_argument("--expectation-file", default=None, help="Optional JSON summary expectation file.")
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
    capture_golden_parser = subparsers.add_parser("capture-golden-replay", help="Capture the checked-in F8 golden replay baseline.")
    capture_golden_parser.add_argument(
        "--golden-scenario",
        default=None,
        choices=["golden_basic_run", "golden_pause_resume", "golden_full_death", "golden_level_up_choice"],
        help="Golden replay scenario to capture. Defaults to golden_basic_run.",
    )
    subparsers.add_parser("perf-probe", help="Run the F8 lightweight perf probe in headless Godot.")
    subparsers.add_parser("startup-probe", help="Measure the first formal-project frame to a playable F13 module-world run (<=2 seconds).")
    subparsers.add_parser("debug-tools-smoke", help="Run the debug console / GM command smoke in headless Godot.")
    subparsers.add_parser(
        "debug-tools-release-smoke",
        help="Run the debug console release-mode guard smoke in headless Godot.",
    )
    subparsers.add_parser("f9-demo-smoke", help="Run the F9 demo content slice smoke in headless Godot.")
    subparsers.add_parser("runtime-smoke", help="Run the formal gameplay runtime smoke in headless Godot.")
    subparsers.add_parser("f4-smoke", help="Compatibility alias for runtime-smoke.")
    subparsers.add_parser("module-world-smoke", help="Run the F13 seamless module-world smoke in headless Godot.")
    subparsers.add_parser(
        "module-world-technical-slice-smoke",
        help="Run the F13 center-3x3 technical-slice smoke in headless Godot.",
    )
    subparsers.add_parser("gear-mod-smoke", help="Run the F11 Gear Mod loadout smoke in headless Godot.")
    subparsers.add_parser("save-smoke", help="Run the SaveManager run-save reliability smoke in headless Godot.")
    subparsers.add_parser("settings-smoke", help="Run the F7 Settings persistence smoke in headless Godot.")
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
    subparsers.add_parser("module-bake-smoke", help="Run focused module bake validation coverage in headless Godot.")
    subparsers.add_parser(
        "module-json-editor-smoke",
        help="Run isolated Module JSON document editing regressions in headless Godot.",
    )
    subparsers.add_parser(
        "actor-scene-smoke",
        help="Validate inherited character/enemy scenes and dedicated enemy pools.",
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
    if args.command == "module-bake-smoke":
        if not (project / "project.godot").exists():
            print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
            return 1
        return _run_command(
            [str(godot), "--headless", "--path", str(project), "--script", "res://tools/module_bake_smoke.gd"],
            cwd=project,
            failure_markers=("SCRIPT ERROR:", "Parse Error:", "Failed to load script"),
        )
    if args.command == "module-json-editor-smoke":
        if not (project / "project.godot").exists():
            print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
            return 1
        return _run_command(
            [
                str(godot),
                "--headless",
                "--path",
                str(project),
                "--script",
                "res://addons/module_authoring/module_json_document_self_test.gd",
            ],
            cwd=project,
            failure_markers=("SCRIPT ERROR:", "Parse Error:", "Failed to load script"),
        )
    if args.command == "actor-scene-smoke":
        if not (project / "project.godot").exists():
            print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
            return 1
        return _run_command(
            [
                str(godot),
                "--headless",
                "--path",
                str(project),
                "--",
                "--actor-scene-smoke",
            ],
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
    if args.command == "l1-smoke":
        if not (project / "project.godot").exists():
            print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
            return 1
        smoke_script = project / "tools" / "l1_smoke.gd"
        if not smoke_script.exists():
            print(f"[godot-bridge] missing L1 smoke script: {_rel(smoke_script)}")
            return 1
        return _run_command(
            [str(godot), "--headless", "--path", str(project), "--", "--l1-smoke"],
            cwd=project,
        )
    if args.command == "replay-smoke":
        if not (project / "project.godot").exists():
            print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
            return 1
        smoke_script = project / "tools" / "replay_smoke.gd"
        if not smoke_script.exists():
            print(f"[godot-bridge] missing Replay smoke script: {_rel(smoke_script)}")
            return 1
        return _run_command(
            [str(godot), "--headless", "--path", str(project), "--", "--replay-smoke"],
            cwd=project,
        )
    if args.command == "replay-input-smoke":
        if not (project / "project.godot").exists():
            print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
            return 1
        smoke_script = project / "tools" / "replay_input_smoke.gd"
        if not smoke_script.exists():
            print(f"[godot-bridge] missing Replay input smoke script: {_rel(smoke_script)}")
            return 1
        return _run_command(
            [str(godot), "--headless", "--path", str(project), "--", "--replay-input-smoke"],
            cwd=project,
        )
    if args.command == "input-smoke":
        if not (project / "project.godot").exists():
            print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
            return 1
        smoke_script = project / "tools" / "input_smoke.gd"
        if not smoke_script.exists():
            print(f"[godot-bridge] missing Input smoke script: {_rel(smoke_script)}")
            return 1
        return _run_command(
            [str(godot), "--headless", "--path", str(project), "--", "--input-smoke"],
            cwd=project,
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
        return _run_command(
            [str(godot), "--headless", "--path", str(project), "--", *user_args],
            cwd=project,
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
    if args.command in {"debug-tools-smoke", "debug-tools-release-smoke"}:
        if not (project / "project.godot").exists():
            print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
            return 1
        smoke_script = project / "tools" / "debug_tools_smoke.gd"
        if not smoke_script.exists():
            print(f"[godot-bridge] missing DebugTools smoke script: {_rel(smoke_script)}")
            return 1
        user_args = ["--debug-tools-smoke"]
        if args.command == "debug-tools-release-smoke":
            user_args.append("--force-release-debug-tools-off")
        return _run_command(
            [str(godot), "--headless", "--path", str(project), "--", *user_args],
            cwd=project,
        )
    if args.command == "f9-demo-smoke":
        if not (project / "project.godot").exists():
            print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
            return 1
        smoke_script = project / "tools" / "f9_demo_smoke.gd"
        if not smoke_script.exists():
            print(f"[godot-bridge] missing F9 demo smoke script: {_rel(smoke_script)}")
            return 1
        return _run_command(
            [str(godot), "--headless", "--path", str(project), "--", "--f9-demo-smoke"],
            cwd=project,
        )
    if args.command in {"runtime-smoke", "f4-smoke"}:
        if not (project / "project.godot").exists():
            print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
            return 1
        smoke_script = project / "tools" / "runtime_smoke.gd"
        if not smoke_script.exists():
            print(f"[godot-bridge] missing runtime smoke script: {_rel(smoke_script)}")
            return 1
        smoke_flag = "--runtime-smoke" if args.command == "runtime-smoke" else "--f4-smoke"
        return _run_command(
            [str(godot), "--headless", "--path", str(project), "--", smoke_flag],
            cwd=project,
        )
    if args.command in {"module-world-smoke", "module-world-technical-slice-smoke"}:
        if not (project / "project.godot").exists():
            print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
            return 1
        smoke_script = project / "tools" / "module_world_smoke.gd"
        if not smoke_script.exists():
            print(f"[godot-bridge] missing module world smoke script: {_rel(smoke_script)}")
            return 1
        flags = ["--module-world-smoke"]
        if args.command == "module-world-technical-slice-smoke":
            flags.append("--module-world-technical-slice")
        return _run_command([str(godot), "--headless", "--path", str(project), "--", *flags], cwd=project)
    if args.command == "save-smoke":
        if not (project / "project.godot").exists():
            print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
            return 1
        smoke_script = project / "tools" / "save_manager_smoke.gd"
        if not smoke_script.exists():
            print(f"[godot-bridge] missing SaveManager smoke script: {_rel(smoke_script)}")
            return 1
        return _run_command(
            [str(godot), "--headless", "--path", str(project), "--", "--save-smoke"],
            cwd=project,
        )
    if args.command == "gear-mod-smoke":
        if not (project / "project.godot").exists():
            print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
            return 1
        smoke_script = project / "tools" / "gear_mod_smoke.gd"
        if not smoke_script.exists():
            print(f"[godot-bridge] missing GearMod smoke script: {_rel(smoke_script)}")
            return 1
        return _run_command(
            [str(godot), "--headless", "--path", str(project), "--", "--gear-mod-smoke"],
            cwd=project,
        )
    if args.command == "settings-smoke":
        if not (project / "project.godot").exists():
            print(f"[godot-bridge] invalid Godot project: {_rel(project)}")
            return 1
        smoke_script = project / "tools" / "settings_smoke.gd"
        if not smoke_script.exists():
            print(f"[godot-bridge] missing Settings smoke script: {_rel(smoke_script)}")
            return 1
        return _run_command(
            [str(godot), "--headless", "--path", str(project), "--", "--settings-smoke"],
            cwd=project,
        )
    print(f"[godot-bridge] unknown command: {args.command}")
    return 1


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


def _run_command(command: list[str], *, cwd: Path, failure_markers: tuple[str, ...] = ()) -> int:
    completed = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        encoding="utf-8",
        errors="replace",
        capture_output=True,
        check=False,
    )
    if completed.stdout:
        print(completed.stdout, end="")
    if completed.stderr:
        print(completed.stderr, end="", file=sys.stderr)
    combined_output = completed.stdout + completed.stderr
    if completed.returncode == 0 and any(marker in combined_output for marker in failure_markers):
        print("[godot-bridge] command output contained a fatal validation marker.", file=sys.stderr)
        return 1
    return completed.returncode


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
