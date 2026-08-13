#!/usr/bin/env python3
"""Run isolated headless checks for Lowpoly Survivors Lab."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


LAB_ROOT = Path(__file__).resolve().parents[1]
SMOKE_SCRIPT = "res://tests/gameplay_smoke.gd"
SUCCESS_MARKER = "[lowpoly-survivors-smoke] ALL PASS"
FATAL_MARKERS = (
    "SCRIPT ERROR:",
    "Parse Error:",
    "Failed to load script",
    "Failed loading resource:",
    "Can't open dynamic library",
    "Error loading GDExtension",
    "Cannot open file",
)
TIMEOUT_SECONDS = 120.0
COMMON_GODOT_PATHS = (
    Path(r"E:\SteamLibrary\steamapps\common\Godot Engine\godot.exe"),
    Path(r"C:\Program Files\Godot\godot.exe"),
)


class SmokeError(RuntimeError):
    """Raised when a smoke gate fails."""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=None, help="Godot 4.7 executable path.")
    parser.add_argument(
        "--suite",
        choices=("boot", "gameplay", "all"),
        default="all",
        help="Smoke suite to run.",
    )
    args = parser.parse_args()

    try:
        godot = _resolve_godot(args.godot)
        _require_godot_47(godot)
        _verify_assets()
        _verify_eos_plugin()
        with tempfile.TemporaryDirectory(prefix="wasd-lowpoly-survivors-smoke-") as temporary:
            isolated_root = Path(temporary)
            _run_import_scan(godot, isolated_root / "import")
            if args.suite in {"boot", "all"}:
                _run_checked(
                    [str(godot), "--headless", "--path", str(LAB_ROOT), "--quit"],
                    "boot",
                    isolated_root / "boot",
                )
            if args.suite in {"gameplay", "all"}:
                _run_checked(
                    [
                        str(godot),
                        "--headless",
                        "--max-fps",
                        "60",
                        "--path",
                        str(LAB_ROOT),
                        "--script",
                        SMOKE_SCRIPT,
                    ],
                    "gameplay",
                    isolated_root / "gameplay",
                    SUCCESS_MARKER,
                )
    except (OSError, SmokeError, subprocess.TimeoutExpired) as error:
        print(f"[lowpoly-survivors-smoke] FAIL {error}", file=sys.stderr)
        return 1

    print("ALL PASS")
    return 0


def _resolve_godot(explicit: str | None) -> Path:
    candidates: list[Path] = []
    if explicit:
        candidates.append(Path(explicit))
    elif os.environ.get("GODOT_PATH"):
        candidates.append(Path(os.environ["GODOT_PATH"]))
    else:
        candidates.extend(COMMON_GODOT_PATHS)
        for name in ("godot", "godot4"):
            result = subprocess.run(
                ["where" if os.name == "nt" else "which", name],
                check=False,
                capture_output=True,
                text=True,
            )
            if result.returncode == 0 and result.stdout.splitlines():
                candidates.append(Path(result.stdout.splitlines()[0].strip()))

    for candidate in candidates:
        if candidate.is_file():
            resolved = candidate.resolve()
            if os.name == "nt" and not resolved.stem.lower().endswith("_console"):
                console = resolved.with_name(f"{resolved.stem}_console{resolved.suffix}")
                if console.is_file():
                    return console.resolve()
            return resolved
    raise SmokeError("Godot executable not found; pass --godot or set GODOT_PATH")


def _require_godot_47(godot: Path) -> None:
    result = subprocess.run(
        [str(godot), "--version"],
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    version = (result.stdout or result.stderr).strip()
    if result.returncode != 0 or not version.startswith("4.7"):
        raise SmokeError(f"Godot 4.7 required, got {version!r}")
    print(f"[lowpoly-survivors-smoke] Godot {version}")


def _verify_assets() -> None:
    manifest_path = LAB_ROOT / "asset_sources.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SmokeError(f"cannot read asset manifest: {error}") from error
    assets = manifest.get("assets") if isinstance(manifest, dict) else None
    if not isinstance(assets, list) or len(assets) != 15:
        raise SmokeError("asset manifest must contain exactly 15 entries")
    public_ids: set[str] = set()
    project_paths: set[str] = set()
    for entry in assets:
        if not isinstance(entry, dict):
            raise SmokeError("asset manifest entries must be objects")
        public_id = entry.get("public_id")
        project_path = entry.get("project_path")
        expected_hash = entry.get("sha256")
        if not all(isinstance(value, str) and value for value in (public_id, project_path, expected_hash)):
            raise SmokeError("asset manifest entry is missing identity or hash fields")
        if public_id in public_ids or project_path in project_paths:
            raise SmokeError(f"duplicate asset identity: {public_id}")
        public_ids.add(public_id)
        project_paths.add(project_path)
        if not project_path.startswith("res://"):
            raise SmokeError(f"invalid project path for {public_id}: {project_path}")
        asset_path = LAB_ROOT / project_path.removeprefix("res://")
        try:
            payload = asset_path.read_bytes()
        except OSError as error:
            raise SmokeError(f"cannot read asset {public_id}: {error}") from error
        if len(payload) < 12 or payload[:4] != b"glTF" or int.from_bytes(payload[4:8], "little") != 2:
            raise SmokeError(f"asset {public_id} is not a GLB v2 file")
        if int.from_bytes(payload[8:12], "little") != len(payload):
            raise SmokeError(f"asset {public_id} has an invalid declared length")
        actual_hash = hashlib.sha256(payload).hexdigest()
        if actual_hash != expected_hash:
            raise SmokeError(f"asset {public_id} SHA-256 mismatch")
        if entry.get("author") != "Quaternius" or entry.get("license") != "CC0 1.0":
            raise SmokeError(f"asset {public_id} has unexpected author or license metadata")
    print("[lowpoly-survivors-smoke] PASS 15 GLB assets and SHA-256 manifest")


def _verify_eos_plugin() -> None:
    manifest_path = LAB_ROOT / "config" / "eos_plugin_manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SmokeError(f"cannot read EOSG manifest: {error}") from error
    if manifest.get("version") != "2.3.0" or manifest.get("eos_sdk") != "1.19.1.2":
        raise SmokeError("EOSG/EOS SDK version pin is invalid")
    if manifest.get("commit") != "e84320567a3a17d305478f5796707e69d2bdac4f":
        raise SmokeError("EOSG source commit pin is invalid")
    release_hashes = {
        entry.get("platform"): entry.get("sha256")
        for entry in manifest.get("release_archives", [])
        if isinstance(entry, dict)
    }
    if release_hashes != {
        "windows-x86_64": "f8fb24b8c92cd89ce810a4052afaaa267c9d22d165407c6f908456d185baa750",
        "android-arm64": "3919360f2e26d33c55b11e0ba6bf4dd3bd04ea3e609b07b2a027c3026a68baf3",
    }:
        raise SmokeError("EOSG release archive hashes are invalid")
    installed = manifest.get("installed_files")
    if not isinstance(installed, list) or len(installed) != 8:
        raise SmokeError("EOSG manifest must audit eight installed binary/license files")
    for entry in installed:
        if not isinstance(entry, dict):
            raise SmokeError("EOSG installed file entry must be an object")
        project_path = entry.get("path")
        if not isinstance(project_path, str) or not project_path.startswith("res://"):
            raise SmokeError("EOSG installed file has invalid project path")
        path = LAB_ROOT / project_path.removeprefix("res://")
        try:
            payload = path.read_bytes()
        except OSError as error:
            raise SmokeError(f"cannot read EOSG file {project_path}: {error}") from error
        if len(payload) != entry.get("bytes") or hashlib.sha256(payload).hexdigest() != entry.get("sha256"):
            raise SmokeError(f"EOSG installed file audit mismatch: {project_path}")
    extension = (LAB_ROOT / "addons" / "epic-online-services-godot" / "eosg.gdextension").read_text(encoding="utf-8")
    forbidden_targets = ("linux.", "macos.", "ios.", "android.debug.x86", "android.release.x86")
    if any(target in extension for target in forbidden_targets):
        raise SmokeError("EOSG descriptor includes an out-of-scope native target")
    addon_root = LAB_ROOT / "addons" / "epic-online-services-godot"
    source_files = sorted(
        path
        for path in addon_root.rglob("*")
        if path.is_file() and "bin" not in path.parts and path.name != "LICENSE.md"
    )
    source_hash = hashlib.sha256()
    for path in source_files:
        relative = path.relative_to(addon_root).as_posix()
        source_hash.update(relative.encode("utf-8"))
        source_hash.update(b"\0")
        source_hash.update(path.read_bytes())
        source_hash.update(b"\0")
    if len(source_files) != manifest.get("installed_source_file_count"):
        raise SmokeError("EOSG installed source file count is invalid")
    if source_hash.hexdigest() != manifest.get("installed_source_tree_sha256"):
        raise SmokeError("EOSG installed source tree SHA-256 mismatch")
    print("[lowpoly-survivors-smoke] PASS EOSG 2.3.0 / EOS SDK 1.19.1.2 audit")


def _run_import_scan(godot: Path, isolated_root: Path) -> None:
    _run_checked(
        [
            str(godot),
            "--headless",
            "--editor",
            "--path",
            str(LAB_ROOT),
            "--quit-after",
            "300",
        ],
        "import",
        isolated_root,
    )


def _run_checked(
    command: list[str],
    label: str,
    isolated_root: Path,
    success_marker: str | None = None,
) -> None:
    environment = _isolated_environment(isolated_root)
    try:
        result = subprocess.run(
            command,
            cwd=LAB_ROOT,
            env=environment,
            check=False,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as error:
        raise SmokeError(f"{label} timed out after {TIMEOUT_SECONDS:.0f}s") from error

    output = "\n".join(part for part in (result.stdout, result.stderr) if part)
    failures: list[str] = []
    if result.returncode != 0:
        failures.append(f"exit code {result.returncode}")
    if success_marker is not None and success_marker not in output.splitlines():
        failures.append(f"missing exact marker {success_marker}")
    for marker in FATAL_MARKERS:
        if marker in output:
            failures.append(f"forbidden marker {marker}")
    if failures:
        print(output[-8_000:], file=sys.stderr)
        raise SmokeError(f"{label} failed: {', '.join(failures)}")
    print(f"[lowpoly-survivors-smoke] PASS {label}")


def _isolated_environment(root: Path) -> dict[str, str]:
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


if __name__ == "__main__":
    raise SystemExit(main())
