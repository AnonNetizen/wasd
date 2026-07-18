#!/usr/bin/env python3
"""Install, verify, smoke-test, and export the pinned Steamworks Slime Lab integration."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import socket
import stat
import subprocess
import sys
import tempfile
import time
import urllib.request
import zipfile
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
LAB_ROOT = ROOT / "output" / "steamworks_lab"
LOCK_PATH = LAB_ROOT / "steam_toolchain.lock.json"
EXPORT_PRESET_PATH = LAB_ROOT / "export_presets.cfg"
PRESENCE_SMOKE_PATH = LAB_ROOT / "tests" / "steam_runtime_presence_smoke.gd"
EXPORT_ROOT = LAB_ROOT / "build" / "windows"
EXPORT_EXE = EXPORT_ROOT / "SteamworksSlimeLab.exe"
THIRD_PARTY_NOTICES_PATH = LAB_ROOT / "THIRD_PARTY_NOTICES.txt"
LEGACY_TOOLCHAIN_ROOT = LAB_ROOT / ".toolchain"
STEAM_APP_ID_PATH = LAB_ROOT / "steam_appid.txt"
EXPECTED_STEAM_APP_ID = "4955670"
SMOKE_SUITES = ["all", "boot", "steam-config", "local-couch", "battle", "enet"]
SMOKE_TIMEOUT_SECONDS = 90.0
ENET_READY_TIMEOUT_SECONDS = 10.0
ENET_TIMEOUT_SECONDS = 45.0
SMOKE_FATAL_MARKERS = ["SCRIPT ERROR", "ERROR:"]
STANDARD_TEMPLATE_NAMES = [
    "version.txt",
    "windows_debug_x86_64.exe",
    "windows_debug_x86_64_console.exe",
    "windows_release_x86_64.exe",
    "windows_release_x86_64_console.exe",
]
COMMON_GODOT_PATHS = [
    Path(r"E:\SteamLibrary\steamapps\common\Godot Engine\godot.exe"),
    Path(r"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.exe"),
    Path(r"C:\Program Files\Godot\godot.exe"),
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--godot",
        help="Path to a normal Godot 4.7 editor. Defaults to GODOT_PATH, PATH, or common Windows installs.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("setup", help="Download, verify, and install the pinned GodotSteam GDExtension.")
    subparsers.add_parser("verify", help="Verify the normal Godot editor, GDExtension, and runtime classes.")
    subparsers.add_parser("export-release", help="Export and validate the Windows x64 Steam release build.")
    smoke_parser = subparsers.add_parser("smoke", help="Run isolated Steamworks Slime Lab smoke suites.")
    smoke_parser.add_argument("--suite", choices=SMOKE_SUITES, default="all")
    smoke_parser.add_argument("--battle-runs", type=int, default=5)
    args = parser.parse_args()

    try:
        lock = _load_lock()
        _verify_development_app_id()
        if args.command == "setup":
            _setup(lock, _resolve_source_godot(args.godot))
        elif args.command == "verify":
            _verify(lock, _resolve_source_godot(args.godot), run_presence_smoke=True)
        elif args.command == "export-release":
            _export_release(lock, _resolve_source_godot(args.godot))
        elif args.command == "smoke":
            _run_smoke_suite(
                lock,
                _resolve_source_godot(args.godot),
                suite=str(args.suite),
                battle_runs=int(args.battle_runs),
            )
        else:
            raise ToolchainError(f"unsupported command: {args.command}")
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError, zipfile.BadZipFile) as error:
        print(f"[steamworks-lab-toolchain] ERROR {error}")
        return 1
    return 0


class ToolchainError(RuntimeError):
    """Expected setup, verification, or export failure."""


def _load_lock() -> dict[str, Any]:
    if not LOCK_PATH.is_file():
        raise ToolchainError(f"missing dependency lock: {_relative(LOCK_PATH)}")
    lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
    if int(lock.get("schema_version", 0)) != 2:
        raise ToolchainError("steam_toolchain.lock.json schema_version must be 2")
    if lock.get("integration_mode") != "gdextension":
        raise ToolchainError("steam_toolchain.lock.json must select gdextension integration")
    if lock.get("platform") != "windows-x86_64":
        raise ToolchainError("only the pinned windows-x86_64 integration is supported")
    assets = lock.get("assets")
    if not isinstance(assets, list) or len(assets) != 1:
        raise ToolchainError("dependency lock must contain exactly one GDExtension asset")
    required_files = lock.get("required_files")
    if not isinstance(required_files, dict) or not required_files:
        raise ToolchainError("dependency lock required_files is missing")
    return lock


def _setup(lock: dict[str, Any], source_godot: Path) -> None:
    if os.name != "nt":
        raise ToolchainError("Steamworks Slime Lab setup currently supports Windows only")
    version_output = _validate_normal_godot(source_godot, str(lock["godot_version"]))
    _cleanup_legacy_toolchain()
    asset = _require_dictionary(lock["assets"][0], "asset")
    with tempfile.TemporaryDirectory(prefix="wasd-steamworks-lab-") as temporary_directory:
        temporary_root = Path(temporary_directory)
        archive = temporary_root / _require_string(asset, "file_name")
        _ensure_download(asset, archive)
        staging_root = temporary_root / "extracted"
        staging_root.mkdir()
        _extract_zip(archive, staging_root)
        package_root = staging_root / "addons" / "godotsteam"
        _verify_required_files(lock, package_root)
        _install_package(lock, package_root)

    print(
        "[steamworks-lab-toolchain] SETUP PASS "
        f"GodotSteam {lock['godotsteam_version']} GDExtension / Steamworks {lock['steamworks_sdk_version']}"
    )
    print(f"[steamworks-lab-toolchain] installed at {_relative(_install_root(lock))}")
    print(f"[steamworks-lab-toolchain] normal editor {version_output} at {_relative(source_godot)}")


def _verify(lock: dict[str, Any], godot: Path, run_presence_smoke: bool) -> str:
    install_root = _install_root(lock)
    _verify_required_files(lock, install_root)
    version_output = _validate_normal_godot(godot, str(lock["godot_version"]))
    print(f"[steamworks-lab-toolchain] normal editor {version_output}")

    if run_presence_smoke:
        if not PRESENCE_SMOKE_PATH.is_file():
            raise ToolchainError(f"missing runtime-presence smoke: {_relative(PRESENCE_SMOKE_PATH)}")
        _run_checked(
            [str(godot), "--headless", "--editor", "--path", str(LAB_ROOT), "--quit"],
            cwd=LAB_ROOT,
            label="GDExtension discovery scan",
        )
        _run_checked(
            [
                str(godot),
                "--headless",
                "--path",
                str(LAB_ROOT),
                "--script",
                "res://tests/steam_runtime_presence_smoke.gd",
            ],
            cwd=LAB_ROOT,
            label="GDExtension runtime-presence smoke",
        )
    print("[steamworks-lab-toolchain] VERIFY PASS")
    return version_output


def _run_smoke_suite(lock: dict[str, Any], godot: Path, suite: str, battle_runs: int) -> None:
    if suite not in SMOKE_SUITES:
        raise ToolchainError(f"unsupported smoke suite: {suite}")
    if battle_runs < 1 or battle_runs > 50:
        raise ToolchainError("--battle-runs must be between 1 and 50")

    version_output = _validate_normal_godot(godot, str(lock["godot_version"]))
    smoke_godot = _godot_cli_executable(godot)
    protected_before = _snapshot_protected_files()
    print(f"[steamworks-lab-smoke] Godot {version_output} via {_relative(smoke_godot)}")
    try:
        with tempfile.TemporaryDirectory(prefix="wasd-steamworks-lab-smoke-") as temporary_directory:
            temporary_root = Path(temporary_directory)
            requested = ["boot", "steam-config", "local-couch", "battle", "enet"] if suite == "all" else [suite]
            for selected_suite in requested:
                if selected_suite == "boot":
                    _run_boot_smoke(smoke_godot, temporary_root / "boot")
                elif selected_suite == "steam-config":
                    _run_script_smoke(
                        smoke_godot,
                        "steam-config",
                        "res://tests/steam_config_smoke.gd",
                        "[steam-config-smoke] ALL PASS",
                        temporary_root / "steam-config",
                    )
                elif selected_suite == "local-couch":
                    _run_script_smoke(
                        smoke_godot,
                        "local-couch",
                        "res://tests/local_couch_smoke.gd",
                        "[local-couch-smoke] ALL PASS",
                        temporary_root / "local-couch",
                    )
                elif selected_suite == "battle":
                    for run_index in range(1, battle_runs + 1):
                        _run_script_smoke(
                            smoke_godot,
                            f"battle {run_index}/{battle_runs}",
                            "res://tests/battle_smoke.gd",
                            "[battle-smoke] ALL PASS",
                            temporary_root / f"battle-{run_index}",
                        )
                elif selected_suite == "enet":
                    _run_enet_smoke(smoke_godot, temporary_root / "enet")
    finally:
        _assert_protected_files_unchanged(protected_before)
        _verify_development_app_id()
    print(f"[steamworks-lab-smoke] ALL PASS suite={suite}")


def _run_boot_smoke(godot: Path, isolated_root: Path) -> None:
    command = [
        str(godot),
        "--headless",
        "--path",
        str(LAB_ROOT),
        "--quit",
        "--",
        "--disable-steam",
    ]
    _run_smoke_command(command, LAB_ROOT, "headless boot", None, isolated_root)


def _run_script_smoke(
    godot: Path,
    label: str,
    script_path: str,
    success_marker: str,
    isolated_root: Path,
) -> None:
    command = [
        str(godot),
        "--headless",
        "--max-fps",
        "60",
        "--path",
        str(LAB_ROOT),
        "--script",
        script_path,
        "--",
        "--disable-steam",
    ]
    _run_smoke_command(command, LAB_ROOT, label, success_marker, isolated_root)


def _run_smoke_command(
    command: list[str],
    cwd: Path,
    label: str,
    success_marker: str | None,
    isolated_root: Path,
) -> None:
    try:
        result = _run(
            command,
            cwd,
            env=_isolated_smoke_environment(isolated_root),
            timeout=SMOKE_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as error:
        _print_failed_smoke_output(
            label,
            _combined_output(_decode_process_stream(error.stdout), _decode_process_stream(error.stderr)),
        )
        raise ToolchainError(f"{label} timed out after {SMOKE_TIMEOUT_SECONDS:.0f}s") from error
    _validate_smoke_result(label, result, success_marker)
    print(f"[steamworks-lab-smoke] PASS {label}")


def _validate_smoke_result(
    label: str,
    result: subprocess.CompletedProcess[str],
    success_marker: str | None,
    forbidden_markers: list[str] | None = None,
) -> None:
    output = _combined_output(result.stdout, result.stderr)
    failures = _smoke_result_failures(result, success_marker, forbidden_markers)
    if not failures:
        return
    _print_failed_smoke_output(label, output)
    raise ToolchainError(f"{label} failed: {', '.join(failures)}")


def _smoke_result_failures(
    result: subprocess.CompletedProcess[str],
    success_marker: str | None,
    forbidden_markers: list[str] | None = None,
) -> list[str]:
    output = _combined_output(result.stdout, result.stderr)
    failures: list[str] = []
    if result.returncode != 0:
        failures.append(f"exit code {result.returncode}")
    if success_marker is not None and success_marker not in output.splitlines():
        failures.append(f"missing exact success marker {success_marker}")
    for marker in [*SMOKE_FATAL_MARKERS, *(forbidden_markers or [])]:
        if marker in output:
            failures.append(f"forbidden log marker {marker}")
    return failures


def _run_enet_smoke(godot: Path, temporary_root: Path) -> None:
    temporary_root.mkdir(parents=True, exist_ok=True)
    client_project = temporary_root / "client-project"
    _copy_lightweight_lab_project(client_project)
    port = _find_available_local_port()
    ready_marker = f"[net-host-smoke] READY port={port}"
    host_log_path = temporary_root / "host.log"
    client_log_path = temporary_root / "client.log"
    host_command = _net_smoke_command(godot, LAB_ROOT, "res://tests/net_host_smoke.gd", port)
    client_command = _net_smoke_command(godot, client_project, "res://tests/net_client_smoke.gd", port)
    host_process: subprocess.Popen[bytes] | None = None
    client_process: subprocess.Popen[bytes] | None = None
    host_log = host_log_path.open("wb")
    client_log = client_log_path.open("wb")
    try:
        host_process = subprocess.Popen(
            host_command,
            cwd=LAB_ROOT,
            env=_isolated_smoke_environment(temporary_root / "host-user"),
            stdout=host_log,
            stderr=subprocess.STDOUT,
        )
        if not _wait_for_log_marker(host_log_path, ready_marker, host_process, ENET_READY_TIMEOUT_SECONDS):
            _terminate_processes([host_process])
            raise ToolchainError(f"ENet host did not report {ready_marker}")

        client_process = subprocess.Popen(
            client_command,
            cwd=client_project,
            env=_isolated_smoke_environment(temporary_root / "client-user"),
            stdout=client_log,
            stderr=subprocess.STDOUT,
        )
        if not _wait_for_processes([host_process, client_process], ENET_TIMEOUT_SECONDS):
            _terminate_processes([host_process, client_process])
            raise ToolchainError(f"ENet host/client timed out after {ENET_TIMEOUT_SECONDS:.0f}s")
    except Exception:
        _terminate_processes([process for process in [host_process, client_process] if process is not None])
        if not host_log.closed:
            host_log.close()
        if not client_log.closed:
            client_log.close()
        _print_failed_smoke_output("ENet host", _read_log(host_log_path))
        _print_failed_smoke_output("ENet client", _read_log(client_log_path))
        raise
    finally:
        if not host_log.closed:
            host_log.close()
        if not client_log.closed:
            client_log.close()

    host_result = subprocess.CompletedProcess(host_command, int(host_process.returncode), _read_log(host_log_path), "")
    client_result = subprocess.CompletedProcess(
        client_command,
        int(client_process.returncode),
        _read_log(client_log_path),
        "",
    )
    host_failures = _smoke_result_failures(
        host_result,
        "[net-host-smoke] ALL PASS",
        forbidden_markers=["above the MTU"],
    )
    client_failures = _smoke_result_failures(
        client_result,
        "[net-client-smoke] ALL PASS",
        forbidden_markers=["above the MTU"],
    )
    if host_failures or client_failures:
        _print_failed_smoke_output("ENet host", host_result.stdout)
        _print_failed_smoke_output("ENet client", client_result.stdout)
        summaries: list[str] = []
        if host_failures:
            summaries.append(f"host: {', '.join(host_failures)}")
        if client_failures:
            summaries.append(f"client: {', '.join(client_failures)}")
        raise ToolchainError(f"ENet smoke failed: {'; '.join(summaries)}")
    for line in host_result.stdout.splitlines():
        if "snapshot wire chunks stay within 900 bytes" in line:
            print(f"[steamworks-lab-smoke] {line}")
    print(f"[steamworks-lab-smoke] PASS enet port={port}")


def _net_smoke_command(godot: Path, project: Path, script_path: str, port: int) -> list[str]:
    return [
        str(godot),
        "--headless",
        "--max-fps",
        "60",
        "--path",
        str(project),
        "--script",
        script_path,
        "--",
        "--disable-steam",
        "--net-smoke-port",
        str(port),
    ]


def _wait_for_log_marker(
    log_path: Path,
    marker: str,
    process: subprocess.Popen[bytes],
    timeout: float,
) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if marker in _read_log(log_path).splitlines():
            return True
        if process.poll() is not None:
            return marker in _read_log(log_path).splitlines()
        time.sleep(0.05)
    return False


def _wait_for_processes(processes: list[subprocess.Popen[bytes]], timeout: float) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if all(process.poll() is not None for process in processes):
            return True
        time.sleep(0.05)
    return all(process.poll() is not None for process in processes)


def _terminate_processes(processes: list[subprocess.Popen[bytes]]) -> None:
    running = [process for process in processes if process.poll() is None]
    for process in running:
        process.terminate()
    deadline = time.monotonic() + 2.0
    while running and time.monotonic() < deadline:
        running = [process for process in running if process.poll() is None]
        if running:
            time.sleep(0.05)
    for process in running:
        process.kill()
    for process in processes:
        if process.poll() is None:
            try:
                process.wait(timeout=2.0)
            except subprocess.TimeoutExpired:
                pass


def _copy_lightweight_lab_project(destination: Path) -> None:
    if destination.exists():
        raise ToolchainError(f"temporary client project already exists: {destination}")
    destination.mkdir(parents=True)
    shutil.copy2(LAB_ROOT / "project.godot", destination / "project.godot")
    for directory_name in ["scenes", "scripts", "tests"]:
        shutil.copytree(LAB_ROOT / directory_name, destination / directory_name)


def _find_available_local_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return int(probe.getsockname()[1])


def _isolated_smoke_environment(root: Path) -> dict[str, str]:
    environment = os.environ.copy()
    roots = {
        "APPDATA": root / "appdata",
        "LOCALAPPDATA": root / "localappdata",
        "HOME": root / "home",
        "XDG_DATA_HOME": root / "xdg-data",
        "XDG_CONFIG_HOME": root / "xdg-config",
        "XDG_CACHE_HOME": root / "xdg-cache",
    }
    for key, path in roots.items():
        path.mkdir(parents=True, exist_ok=True)
        environment[key] = str(path)
    return environment


def _godot_cli_executable(godot: Path) -> Path:
    if os.name != "nt" or godot.stem.lower().endswith("_console"):
        return godot
    console_candidate = godot.with_name(f"{godot.stem}_console{godot.suffix}")
    if console_candidate.is_file():
        return console_candidate.resolve()
    return godot


def _snapshot_protected_files() -> dict[Path, bytes | None]:
    paths = [STEAM_APP_ID_PATH]
    user_root = _default_godot_user_root()
    if user_root is not None:
        paths.extend([user_root / "settings.cfg", user_root / "save.cfg"])
    return {path: path.read_bytes() if path.is_file() else None for path in paths}


def _assert_protected_files_unchanged(snapshot: dict[Path, bytes | None]) -> None:
    changed: list[str] = []
    for path, before in snapshot.items():
        after = path.read_bytes() if path.is_file() else None
        if after != before:
            changed.append(_relative(path))
    if changed:
        raise ToolchainError(f"smoke changed protected player/source files: {', '.join(changed)}")
    print("[steamworks-lab-smoke] PASS protected player/source files unchanged")


def _default_godot_user_root() -> Path | None:
    project_name = _project_name()
    if sys.platform == "win32":
        appdata = os.environ.get("APPDATA")
        return Path(appdata) / "Godot" / "app_userdata" / project_name if appdata else None
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "Godot" / "app_userdata" / project_name
    data_root = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
    return data_root / "godot" / "app_userdata" / project_name


def _project_name() -> str:
    project_text = (LAB_ROOT / "project.godot").read_text(encoding="utf-8")
    match = re.search(r'^config/name="([^"]+)"$', project_text, flags=re.MULTILINE)
    if match is None:
        raise ToolchainError("Steamworks Slime Lab project name is missing")
    return match.group(1)


def _verify_development_app_id() -> bytes:
    if not STEAM_APP_ID_PATH.is_file():
        raise ToolchainError("development steam_appid.txt is missing from the Lab source directory")
    raw = STEAM_APP_ID_PATH.read_bytes()
    if raw.decode("utf-8-sig").strip() != EXPECTED_STEAM_APP_ID:
        raise ToolchainError(f"steam_appid.txt must contain only {EXPECTED_STEAM_APP_ID}")
    return raw


def _combined_output(stdout: str | None, stderr: str | None) -> str:
    return "\n".join(part.rstrip("\n") for part in [stdout or "", stderr or ""] if part)


def _decode_process_stream(stream: bytes | str | None) -> str:
    if isinstance(stream, bytes):
        return stream.decode("utf-8", errors="replace")
    return stream or ""


def _read_log(path: Path) -> str:
    if not path.is_file():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def _print_failed_smoke_output(label: str, output: str) -> None:
    print(f"[steamworks-lab-smoke] --- {label} output ---")
    print(output or "<empty>")
    print(f"[steamworks-lab-smoke] --- end {label} output ---")


def _export_release(lock: dict[str, Any], godot: Path) -> None:
    version_output = _verify(lock, godot, run_presence_smoke=True)
    template_root = _find_standard_template_root(version_output)
    print(f"[steamworks-lab-toolchain] export templates at {_relative(template_root)}")
    preset_text = _verified_export_preset_text()
    preset_name = _export_preset_name(preset_text)

    _safe_clear_export_root()
    EXPORT_ROOT.mkdir(parents=True)
    _run_checked(
        [
            str(godot),
            "--headless",
            "--path",
            str(LAB_ROOT),
            "--export-release",
            preset_name,
            str(EXPORT_EXE),
        ],
        cwd=LAB_ROOT,
        label="Windows GDExtension release export",
    )

    if not THIRD_PARTY_NOTICES_PATH.is_file():
        raise ToolchainError(f"missing release notices: {_relative(THIRD_PARTY_NOTICES_PATH)}")
    notices_destination = EXPORT_ROOT / THIRD_PARTY_NOTICES_PATH.name
    shutil.copy2(THIRD_PARTY_NOTICES_PATH, notices_destination)

    required_files = _require_dictionary(lock["required_files"], "required_files")
    release_library_name = Path(_require_string(required_files, "release_library")).name
    steam_api_name = Path(_require_string(required_files, "steam_api")).name
    release_library = _find_exported_file(release_library_name)
    steam_api = _find_exported_file(steam_api_name)
    expected_outputs = [
        EXPORT_EXE,
        EXPORT_EXE.with_suffix(".pck"),
        release_library,
        steam_api,
        notices_destination,
    ]
    missing = [_relative(path) for path in expected_outputs if not path.is_file()]
    if missing:
        raise ToolchainError(f"release output is incomplete: {', '.join(missing)}")

    leaked: list[Path] = []
    for path in EXPORT_ROOT.rglob("*"):
        relative_parts = {part.lower() for part in path.relative_to(EXPORT_ROOT).parts}
        if path.name.lower() == "steam_appid.txt" or "tests" in relative_parts:
            leaked.append(path)
    if leaked:
        raise ToolchainError(f"forbidden release content: {', '.join(_relative(path) for path in leaked)}")

    _run_checked(
        [str(EXPORT_EXE), "--headless", "--quit", "--", "--disable-steam"],
        cwd=EXPORT_ROOT,
        label="exported offline boot",
    )
    _verify_development_app_id()
    print(f"[steamworks-lab-toolchain] EXPORT PASS {_relative(EXPORT_ROOT)}")


def _verified_export_preset_text() -> str:
    if not EXPORT_PRESET_PATH.is_file():
        raise ToolchainError(f"missing export preset: {_relative(EXPORT_PRESET_PATH)}")
    preset_text = EXPORT_PRESET_PATH.read_text(encoding="utf-8")
    for excluded_path in [
        "steam_appid.txt",
        "tests/*",
        "addons/godotsteam/editor/*",
        "addons/godotsteam/plugin.cfg",
        "addons/godotsteam/godotsteam_plugin.gd",
    ]:
        if excluded_path not in preset_text:
            raise ToolchainError(f"export preset does not exclude {excluded_path}")
    for key in ["custom_template/debug", "custom_template/release"]:
        if f'{key}=""' not in preset_text:
            raise ToolchainError(f"GDExtension export must use the normal Godot template: {key}")
    if "godotsteam-4.20-g47-win64" in preset_text:
        raise ToolchainError("export preset still references the retired GodotSteam module toolchain")
    return preset_text


def _export_preset_name(preset_text: str) -> str:
    match = re.search(r'^name="([^"]+)"$', preset_text, flags=re.MULTILINE)
    if match is None:
        raise ToolchainError("export preset name is missing")
    return match.group(1)


def _ensure_download(asset: dict[str, Any], archive: Path) -> None:
    expected_hash = _require_string(asset, "sha256").lower()
    expected_size = int(asset.get("size", 0))
    if archive.is_file() and _sha256(archive) == expected_hash and archive.stat().st_size == expected_size:
        print(f"[steamworks-lab-toolchain] cached {_relative(archive)}")
        return

    temporary = archive.with_suffix(archive.suffix + ".part")
    temporary.unlink(missing_ok=True)
    url = _require_string(asset, "url")
    print(f"[steamworks-lab-toolchain] downloading {url}")
    request = urllib.request.Request(url, headers={"User-Agent": "wasd-steamworks-lab-toolchain/2"})
    with urllib.request.urlopen(request, timeout=120) as response, temporary.open("wb") as output:
        shutil.copyfileobj(response, output, length=1024 * 1024)
    if temporary.stat().st_size != expected_size:
        temporary.unlink(missing_ok=True)
        raise ToolchainError(f"download size mismatch for {archive.name}")
    actual_hash = _sha256(temporary)
    if actual_hash != expected_hash:
        temporary.unlink(missing_ok=True)
        raise ToolchainError(f"download hash mismatch for {archive.name}: {actual_hash}")
    temporary.replace(archive)


def _extract_zip(archive: Path, destination: Path) -> None:
    destination_resolved = destination.resolve()
    with zipfile.ZipFile(archive) as package:
        for member in package.infolist():
            target = (destination / member.filename).resolve()
            if not target.is_relative_to(destination_resolved):
                raise ToolchainError(f"unsafe archive member in {archive.name}: {member.filename}")
            unix_mode = (member.external_attr >> 16) & 0xFFFF
            if stat.S_IFMT(unix_mode) == stat.S_IFLNK:
                raise ToolchainError(f"archive links are not allowed in {archive.name}: {member.filename}")
        package.extractall(destination)


def _verify_required_files(lock: dict[str, Any], install_root: Path) -> None:
    if not install_root.is_dir():
        raise ToolchainError("GodotSteam GDExtension is not installed; run the setup command first")
    missing: list[str] = []
    for relative_path in lock["required_files"].values():
        candidate = install_root / str(relative_path)
        if not candidate.is_file():
            missing.append(str(relative_path))
    if missing:
        raise ToolchainError(f"GDExtension files are missing: {', '.join(missing)}")


def _resolve_source_godot(argument: str | None) -> Path:
    if argument:
        candidate = Path(argument).expanduser()
        if not candidate.is_file():
            raise ToolchainError(f"--godot does not point to an executable file: {candidate}")
        return candidate.resolve()

    env_path = os.environ.get("GODOT_PATH")
    if env_path:
        candidate = Path(env_path).expanduser()
        if not candidate.is_file():
            raise ToolchainError(f"GODOT_PATH does not point to an executable file: {candidate}")
        return candidate.resolve()

    candidates: list[Path] = []
    for executable_name in ["godot4", "godot"]:
        discovered = shutil.which(executable_name)
        if discovered:
            candidates.append(Path(discovered))
    candidates.extend(COMMON_GODOT_PATHS)

    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()
    raise ToolchainError("normal Godot 4.7 editor not found; pass --godot or set GODOT_PATH")


def _reject_conflicting_steam_editor(godot: Path) -> None:
    if not godot.is_file():
        raise ToolchainError(f"Godot editor does not exist: {godot}")
    if (godot.parent / "steam_api64.dll").is_file():
        raise ToolchainError(
            "the selected Godot directory contains its own steam_api64.dll, which conflicts with GodotSteam; "
            "select a clean normal Godot editor such as the one configured by GODOT_PATH"
        )


def _validate_normal_godot(godot: Path, expected_version: str) -> str:
    _reject_conflicting_steam_editor(godot)
    version_result = _run([str(godot), "--version"], cwd=LAB_ROOT)
    version_output = (version_result.stdout + version_result.stderr).strip()
    if version_result.returncode != 0:
        raise ToolchainError(
            f"Godot version check failed with exit code {version_result.returncode}: {version_output or '<empty>'}"
        )
    if expected_version not in version_output or "custom_build" in version_output.lower():
        raise ToolchainError(f"a normal Godot {expected_version} editor is required: {version_output or '<empty>'}")
    return version_output


def _find_standard_template_root(version_output: str) -> Path:
    version_match = re.match(r"^(\d+\.\d+(?:\.\d+)?\.stable)(?:\.|$)", version_output)
    if version_match is None:
        raise ToolchainError(f"cannot determine the Godot export template version from: {version_output}")
    appdata = os.environ.get("APPDATA")
    if not appdata:
        raise ToolchainError("APPDATA is not set; cannot locate the standard Godot export templates")
    template_version = version_match.group(1)
    template_root = Path(appdata) / "Godot" / "export_templates" / template_version
    missing = [file_name for file_name in STANDARD_TEMPLATE_NAMES if not (template_root / file_name).is_file()]
    if missing:
        raise ToolchainError(
            f"matching Godot {template_version} Windows x86_64 export templates are missing at {template_root}; "
            f"install them with the selected editor (missing: {', '.join(missing)})"
        )
    return template_root.resolve()


def _install_package(lock: dict[str, Any], package_root: Path) -> None:
    install_root = _install_root(lock)
    install_root.parent.mkdir(parents=True, exist_ok=True)
    staging_root = install_root.with_name(f"{install_root.name}.tmp")
    backup_root = install_root.with_name(f"{install_root.name}.bak")
    _safe_remove_tree(staging_root, install_root.parent)
    _safe_remove_tree(backup_root, install_root.parent)
    try:
        shutil.copytree(package_root, staging_root)
        _verify_required_files(lock, staging_root)
        if install_root.exists():
            install_root.replace(backup_root)
        try:
            staging_root.replace(install_root)
        except OSError:
            if backup_root.exists() and not install_root.exists():
                backup_root.replace(install_root)
            raise
    finally:
        _safe_remove_tree(staging_root, install_root.parent)
        if install_root.exists():
            _safe_remove_tree(backup_root, install_root.parent)


def _install_root(lock: dict[str, Any]) -> Path:
    root = (LAB_ROOT / _require_string(lock, "install_dir")).resolve()
    if not root.is_relative_to(LAB_ROOT.resolve()):
        raise ToolchainError(f"invalid GDExtension install path: {root}")
    return root


def _cleanup_legacy_toolchain() -> None:
    if not LEGACY_TOOLCHAIN_ROOT.exists():
        return
    _safe_remove_tree(LEGACY_TOOLCHAIN_ROOT, LAB_ROOT)
    print(f"[steamworks-lab-toolchain] removed legacy toolchain {_relative(LEGACY_TOOLCHAIN_ROOT)}")


def _find_exported_file(file_name: str) -> Path:
    matches = [path for path in EXPORT_ROOT.rglob(file_name) if path.is_file()]
    if len(matches) != 1:
        raise ToolchainError(f"expected one exported {file_name}, found {len(matches)}")
    return matches[0]


def _safe_remove_tree(path: Path, allowed_parent: Path) -> None:
    resolved = path.resolve()
    parent = allowed_parent.resolve()
    if not resolved.is_relative_to(parent) or resolved == parent:
        raise ToolchainError(f"refusing to remove unexpected path: {resolved}")
    if resolved.is_dir():
        shutil.rmtree(resolved)
    elif resolved.exists():
        resolved.unlink()


def _safe_clear_export_root() -> None:
    resolved = EXPORT_ROOT.resolve()
    expected_parent = (LAB_ROOT / "build").resolve()
    if resolved.parent != expected_parent or resolved.name != "windows":
        raise ToolchainError(f"refusing to clear unexpected export path: {resolved}")
    if resolved.exists():
        shutil.rmtree(resolved)


def _run_checked(command: list[str], cwd: Path, label: str) -> None:
    result = _run(command, cwd)
    if result.stdout:
        print(result.stdout, end="" if result.stdout.endswith("\n") else "\n")
    if result.stderr:
        print(result.stderr, file=sys.stderr, end="" if result.stderr.endswith("\n") else "\n")
    if result.returncode != 0:
        raise ToolchainError(f"{label} failed with exit code {result.returncode}")


def _run(
    command: list[str],
    cwd: Path,
    env: dict[str, str] | None = None,
    timeout: float | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        env=env,
        timeout=timeout,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _require_dictionary(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ToolchainError(f"{label} must be an object")
    return value


def _require_string(mapping: dict[str, Any], key: str) -> str:
    value = mapping.get(key)
    if not isinstance(value, str) or not value:
        raise ToolchainError(f"{key} must be a non-empty string")
    return value


def _relative(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT)).replace("\\", "/")
    except ValueError:
        return str(path.resolve())


if __name__ == "__main__":
    raise SystemExit(main())
