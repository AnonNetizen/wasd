#!/usr/bin/env python3
"""Install, verify, and export the pinned Steamworks Slime Lab integration."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
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
    args = parser.parse_args()

    try:
        lock = _load_lock()
        if args.command == "setup":
            _setup(lock, _resolve_source_godot(args.godot))
        elif args.command == "verify":
            _verify(lock, _resolve_source_godot(args.godot), run_presence_smoke=True)
        elif args.command == "export-release":
            _export_release(lock, _resolve_source_godot(args.godot))
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


def _run(command: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
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
