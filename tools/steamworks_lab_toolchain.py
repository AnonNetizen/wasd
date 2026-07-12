#!/usr/bin/env python3
"""Install, verify, and export the pinned Steamworks Slime Lab toolchain."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import urllib.request
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
LAB_ROOT = ROOT / "output" / "steamworks_lab"
LOCK_PATH = LAB_ROOT / "steam_toolchain.lock.json"
TOOLCHAIN_ROOT = LAB_ROOT / ".toolchain"
DOWNLOAD_ROOT = TOOLCHAIN_ROOT / "downloads"
EXPORT_PRESET_PATH = LAB_ROOT / "export_presets.cfg"
PRESENCE_SMOKE_PATH = LAB_ROOT / "tests" / "steam_runtime_presence_smoke.gd"
EXPORT_PRESET_NAME = "Windows Steam"
EXPORT_ROOT = LAB_ROOT / "build" / "windows"
EXPORT_EXE = EXPORT_ROOT / "SteamworksSlimeLab.exe"
THIRD_PARTY_NOTICES_PATH = LAB_ROOT / "THIRD_PARTY_NOTICES.txt"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("setup", help="Download, verify, and extract the pinned GodotSteam toolchain.")
    subparsers.add_parser("verify", help="Verify files and run the GodotSteam runtime-presence smoke.")
    subparsers.add_parser("export-release", help="Export and validate the Windows x64 Steam release build.")
    args = parser.parse_args()

    try:
        lock = _load_lock()
        if args.command == "setup":
            _setup(lock)
        elif args.command == "verify":
            _verify(lock, run_presence_smoke=True)
        elif args.command == "export-release":
            _export_release(lock)
        else:
            raise ToolchainError(f"unsupported command: {args.command}")
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError, tarfile.TarError) as error:
        print(f"[steamworks-lab-toolchain] ERROR {error}")
        return 1
    return 0


class ToolchainError(RuntimeError):
    """Expected setup, verification, or export failure."""


def _load_lock() -> dict[str, Any]:
    if not LOCK_PATH.is_file():
        raise ToolchainError(f"missing dependency lock: {_relative(LOCK_PATH)}")
    lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
    if int(lock.get("schema_version", 0)) != 1:
        raise ToolchainError("steam_toolchain.lock.json schema_version must be 1")
    if lock.get("platform") != "windows-x86_64":
        raise ToolchainError("only the pinned windows-x86_64 toolchain is supported")
    assets = lock.get("assets")
    if not isinstance(assets, list) or len(assets) != 2:
        raise ToolchainError("dependency lock must contain editor and templates assets")
    required_files = lock.get("required_files")
    if not isinstance(required_files, dict) or not required_files:
        raise ToolchainError("dependency lock required_files is missing")
    return lock


def _setup(lock: dict[str, Any]) -> None:
    if os.name != "nt":
        raise ToolchainError("Steamworks Slime Lab setup currently supports Windows only")
    DOWNLOAD_ROOT.mkdir(parents=True, exist_ok=True)
    archives: list[Path] = []
    for asset_data in lock["assets"]:
        asset = _require_dictionary(asset_data, "asset")
        archive = DOWNLOAD_ROOT / _require_string(asset, "file_name")
        _ensure_download(asset, archive)
        archives.append(archive)

    install_root = _install_root(lock)
    staging_root = TOOLCHAIN_ROOT / f".{install_root.name}.staging"
    if staging_root.exists():
        shutil.rmtree(staging_root)
    staging_root.mkdir(parents=True)
    try:
        for archive in archives:
            _extract_archive(archive, staging_root)
        (staging_root / ".gdignore").write_text("# Local GodotSteam binaries; managed by tools/steamworks_lab_toolchain.py.\n", encoding="utf-8")
        _verify_required_files(lock, staging_root)
        if install_root.exists():
            shutil.rmtree(install_root)
        staging_root.replace(install_root)
    finally:
        if staging_root.exists():
            shutil.rmtree(staging_root)

    print(
        "[steamworks-lab-toolchain] SETUP PASS "
        f"Godot {lock['godot_version']} / GodotSteam {lock['godotsteam_version']} / "
        f"Steamworks {lock['steamworks_sdk_version']}"
    )
    print(f"[steamworks-lab-toolchain] installed at {_relative(install_root)}")


def _verify(lock: dict[str, Any], run_presence_smoke: bool) -> None:
    install_root = _install_root(lock)
    _verify_required_files(lock, install_root)
    editor = _required_path(lock, "editor")
    version_result = _run([str(editor), "--version"], cwd=LAB_ROOT)
    version_output = (version_result.stdout + version_result.stderr).strip()
    expected_godot = str(lock["godot_version"])
    if expected_godot not in version_output:
        raise ToolchainError(f"GodotSteam editor version mismatch: {version_output or '<empty>'}")
    print(f"[steamworks-lab-toolchain] editor {version_output}")

    if run_presence_smoke:
        if not PRESENCE_SMOKE_PATH.is_file():
            raise ToolchainError(f"missing runtime-presence smoke: {_relative(PRESENCE_SMOKE_PATH)}")
        _run_checked(
            [
                str(editor),
                "--headless",
                "--path",
                str(LAB_ROOT),
                "--script",
                "res://tests/steam_runtime_presence_smoke.gd",
            ],
            cwd=LAB_ROOT,
            label="runtime-presence smoke",
        )
    print("[steamworks-lab-toolchain] VERIFY PASS")


def _export_release(lock: dict[str, Any]) -> None:
    _verify(lock, run_presence_smoke=True)
    if not EXPORT_PRESET_PATH.is_file():
        raise ToolchainError(f"missing export preset: {_relative(EXPORT_PRESET_PATH)}")
    preset_text = EXPORT_PRESET_PATH.read_text(encoding="utf-8")
    for excluded_path in ["steam_appid.txt", "tests/*", ".toolchain/*"]:
        if excluded_path not in preset_text:
            raise ToolchainError(f"export preset does not exclude {excluded_path}")

    _safe_clear_export_root()
    EXPORT_ROOT.mkdir(parents=True)
    editor = _required_path(lock, "editor")
    _run_checked(
        [
            str(editor),
            "--headless",
            "--path",
            str(LAB_ROOT),
            "--export-release",
            EXPORT_PRESET_NAME,
            str(EXPORT_EXE),
        ],
        cwd=LAB_ROOT,
        label="Windows release export",
    )

    steam_api_source = _required_path(lock, "template_steam_api")
    steam_api_destination = EXPORT_ROOT / "steam_api64.dll"
    shutil.copy2(steam_api_source, steam_api_destination)

    if not THIRD_PARTY_NOTICES_PATH.is_file():
        raise ToolchainError(f"missing release notices: {_relative(THIRD_PARTY_NOTICES_PATH)}")
    notices_destination = EXPORT_ROOT / THIRD_PARTY_NOTICES_PATH.name
    shutil.copy2(THIRD_PARTY_NOTICES_PATH, notices_destination)

    expected_outputs = [
        EXPORT_EXE,
        EXPORT_EXE.with_suffix(".pck"),
        steam_api_destination,
        notices_destination,
    ]
    missing = [_relative(path) for path in expected_outputs if not path.is_file()]
    if missing:
        raise ToolchainError(f"release output is incomplete: {', '.join(missing)}")
    forbidden_names = {"steam_appid.txt", ".toolchain", "tests"}
    leaked = [path for path in EXPORT_ROOT.rglob("*") if path.name in forbidden_names]
    if leaked:
        raise ToolchainError(f"forbidden release content: {', '.join(_relative(path) for path in leaked)}")

    _run_checked(
        [str(EXPORT_EXE), "--headless", "--quit", "--", "--disable-steam"],
        cwd=EXPORT_ROOT,
        label="exported offline boot",
    )
    print(f"[steamworks-lab-toolchain] EXPORT PASS {_relative(EXPORT_ROOT)}")


def _ensure_download(asset: dict[str, Any], archive: Path) -> None:
    expected_hash = _require_string(asset, "sha256").lower()
    expected_size = int(asset.get("size", 0))
    if archive.is_file() and _sha256(archive) == expected_hash and archive.stat().st_size == expected_size:
        print(f"[steamworks-lab-toolchain] cached {_relative(archive)}")
        return

    temporary = archive.with_suffix(archive.suffix + ".part")
    if temporary.exists():
        temporary.unlink()
    url = _require_string(asset, "url")
    print(f"[steamworks-lab-toolchain] downloading {url}")
    request = urllib.request.Request(url, headers={"User-Agent": "wasd-steamworks-lab-toolchain/1"})
    with urllib.request.urlopen(request, timeout=60) as response, temporary.open("wb") as output:
        shutil.copyfileobj(response, output, length=1024 * 1024)
    if temporary.stat().st_size != expected_size:
        temporary.unlink(missing_ok=True)
        raise ToolchainError(f"download size mismatch for {archive.name}")
    actual_hash = _sha256(temporary)
    if actual_hash != expected_hash:
        temporary.unlink(missing_ok=True)
        raise ToolchainError(f"download hash mismatch for {archive.name}: {actual_hash}")
    temporary.replace(archive)


def _extract_archive(archive: Path, destination: Path) -> None:
    destination_resolved = destination.resolve()
    with tarfile.open(archive, mode="r:xz") as package:
        for member in package.getmembers():
            target = (destination / member.name).resolve()
            if not target.is_relative_to(destination_resolved):
                raise ToolchainError(f"unsafe archive member in {archive.name}: {member.name}")
            if member.issym() or member.islnk():
                raise ToolchainError(f"archive links are not allowed in {archive.name}: {member.name}")
        package.extractall(destination, filter="data")


def _verify_required_files(lock: dict[str, Any], install_root: Path) -> None:
    if not install_root.is_dir():
        raise ToolchainError("GodotSteam toolchain is not installed; run the setup command first")
    missing: list[str] = []
    for relative_path in lock["required_files"].values():
        candidate = install_root / str(relative_path)
        if not candidate.is_file():
            missing.append(str(relative_path))
    if missing:
        raise ToolchainError(f"toolchain files are missing: {', '.join(missing)}")


def _required_path(lock: dict[str, Any], key: str) -> Path:
    required_files = _require_dictionary(lock["required_files"], "required_files")
    relative_path = _require_string(required_files, key)
    return _install_root(lock) / relative_path


def _install_root(lock: dict[str, Any]) -> Path:
    return TOOLCHAIN_ROOT / _require_string(lock, "install_dir")


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
