#!/usr/bin/env python3
"""Generate and patch Godot 4.7's Android Gradle template for EOSG."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
from pathlib import Path


LAB_ROOT = Path(__file__).resolve().parents[1]
BUILD_ROOT = LAB_ROOT / "android" / "build"
EOS_AAR = LAB_ROOT / "addons" / "epic-online-services-godot" / "bin" / "android" / "eossdk-StaticSTDC-release.aar"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", help="Godot 4.7 editor executable.")
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()

    if not EOS_AAR.is_file():
        raise SystemExit(f"missing EOS Android SDK AAR: {EOS_AAR}")
    if not args.verify_only and not (BUILD_ROOT / "build.gradle").is_file():
        godot = _find_godot(args.godot)
        result = subprocess.run(
            [str(godot), "--headless", "--path", str(LAB_ROOT), "--install-android-build-template", "--quit"],
            check=False,
        )
        if not (BUILD_ROOT / "build.gradle").is_file():
            raise SystemExit(f"Godot could not install the Android build template (exit {result.returncode})")

    if not args.verify_only:
        _patch_gradle()
        _patch_activity()
        _patch_manifest()
    _verify()
    print("[lowpoly-android-template] ALL PASS")
    return 0


def _find_godot(explicit: str | None) -> Path:
    candidates = [Path(explicit)] if explicit else []
    if os.environ.get("GODOT_PATH"):
        candidates.append(Path(os.environ["GODOT_PATH"]))
    for name in ("godot", "godot4"):
        found = shutil.which(name)
        if found:
            candidates.append(Path(found))
    candidates.extend((Path(r"G:\Godot\Godot.exe"), Path(r"E:\SteamLibrary\steamapps\common\Godot Engine\godot.exe")))
    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()
    raise SystemExit("Godot 4.7 editor not found; pass --godot or set GODOT_PATH")


def _replace_once(path: Path, marker: str, replacement: str) -> None:
    text = path.read_text(encoding="utf-8")
    if replacement in text:
        return
    if marker not in text:
        raise SystemExit(f"template marker changed in {path}: {marker!r}")
    path.write_text(text.replace(marker, replacement, 1), encoding="utf-8", newline="\n")


def _patch_gradle() -> None:
    path = BUILD_ROOT / "build.gradle"
    dependency_marker = '    implementation "androidx.documentfile:documentfile:$versions.documentfileVersion"'
    dependencies = dependency_marker + """

    // Epic Online Services Android SDK 1.19.1.2 (Device ID, Lobby and P2P only).
    implementation 'androidx.appcompat:appcompat:1.7.0'
    implementation 'androidx.constraintlayout:constraintlayout:2.2.1'
    implementation 'androidx.security:security-crypto:1.1.0-alpha06'
    implementation 'androidx.browser:browser:1.8.0'
    implementation 'androidx.webkit:webkit:1.12.1'
    implementation files('../../addons/epic-online-services-godot/bin/android/eossdk-StaticSTDC-release.aar')"""
    _replace_once(path, dependency_marker, dependencies)

    dimension_marker = "        missingDimensionStrategy 'products', 'template'"
    client_scheme = dimension_marker + """

        // Supply the real value through the export environment; never commit credentials.
        String eosClientId = System.getenv('LOWPOLY_EOS_CLIENT_ID') ?: 'local_device_id_only'
        resValue('string', 'eos_login_protocol_scheme', 'eos.' + eosClientId.toLowerCase())"""
    _replace_once(path, dimension_marker, client_scheme)


def _patch_activity() -> None:
    path = BUILD_ROOT / "src" / "main" / "java" / "com" / "godot" / "game" / "GodotApp.java"
    import_marker = "import org.godotengine.godot.GodotActivity;"
    _replace_once(path, import_marker, import_marker + "\nimport com.epicgames.mobile.eossdk.EOSSDK;")
    static_marker = "\tstatic {\n\t\t// .NET libraries."
    _replace_once(path, static_marker, "\tstatic {\n\t\tSystem.loadLibrary(\"EOSSDK\");\n\n\t\t// .NET libraries.")
    create_marker = "\tpublic void onCreate(Bundle savedInstanceState) {\n\t\tSplashScreen"
    _replace_once(path, create_marker, "\tpublic void onCreate(Bundle savedInstanceState) {\n\t\tEOSSDK.init(this);\n\t\tSplashScreen")


def _patch_manifest() -> None:
    path = BUILD_ROOT / "src" / "main" / "AndroidManifest.xml"
    marker = "    <supports-screens"
    permissions = """    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />

    <supports-screens"""
    _replace_once(path, marker, permissions)


def _verify() -> None:
    required = {
        BUILD_ROOT / "build.gradle": ("eossdk-StaticSTDC-release.aar", "LOWPOLY_EOS_CLIENT_ID"),
        BUILD_ROOT / "src" / "main" / "java" / "com" / "godot" / "game" / "GodotApp.java": (
            "System.loadLibrary(\"EOSSDK\")",
            "EOSSDK.init(this)",
        ),
        BUILD_ROOT / "src" / "main" / "AndroidManifest.xml": (
            "android.permission.INTERNET",
            "android.permission.ACCESS_NETWORK_STATE",
            "android.permission.ACCESS_WIFI_STATE",
        ),
    }
    for path, markers in required.items():
        if not path.is_file():
            raise SystemExit(f"missing generated template file: {path}")
        text = path.read_text(encoding="utf-8")
        for marker in markers:
            if marker not in text:
                raise SystemExit(f"missing EOS marker {marker!r} in {path}")
    config = (BUILD_ROOT / "config.gradle").read_text(encoding="utf-8")
    if "minSdk             : 24" not in config:
        raise SystemExit("Godot Android template must use minSdk 24 or newer")


if __name__ == "__main__":
    raise SystemExit(main())
