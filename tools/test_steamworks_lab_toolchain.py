#!/usr/bin/env python3
"""Regression tests for the Steamworks Slime Lab dependency tool."""

from __future__ import annotations

import os
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import steamworks_lab_toolchain as toolchain


class SteamworksLabToolchainTests(unittest.TestCase):
    def test_explicit_godot_path_takes_priority_over_environment(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            explicit = root / "explicit.exe"
            environment = root / "environment.exe"
            explicit.touch()
            environment.touch()
            with mock.patch.dict(os.environ, {"GODOT_PATH": str(environment)}):
                resolved = toolchain._resolve_source_godot(str(explicit))
            self.assertEqual(resolved, explicit.resolve())

    def test_environment_godot_path_takes_priority_over_discovery(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            environment = Path(temporary_directory) / "environment.exe"
            environment.touch()
            with (
                mock.patch.dict(os.environ, {"GODOT_PATH": str(environment)}),
                mock.patch.object(shutil, "which", return_value="ignored.exe"),
            ):
                resolved = toolchain._resolve_source_godot(None)
            self.assertEqual(resolved, environment.resolve())

    def test_invalid_explicit_godot_path_does_not_fall_back(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            environment = root / "environment.exe"
            environment.touch()
            with mock.patch.dict(os.environ, {"GODOT_PATH": str(environment)}):
                with self.assertRaisesRegex(toolchain.ToolchainError, "--godot does not point"):
                    toolchain._resolve_source_godot(str(root))

    def test_editor_with_adjacent_steam_api_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            godot = root / "Godot.exe"
            godot.touch()
            (root / "steam_api64.dll").touch()
            with self.assertRaisesRegex(toolchain.ToolchainError, "conflicts with GodotSteam"):
                toolchain._reject_conflicting_steam_editor(godot)

    def test_setup_installs_from_temporary_directory_without_toolchain(self) -> None:
        lock = {
            "godot_version": "4.7",
            "godotsteam_version": "4.20",
            "steamworks_sdk_version": "1.64",
            "install_dir": "addons/godotsteam",
            "assets": [{"file_name": "plugin.zip"}],
            "required_files": {"extension": "godotsteam.gdextension"},
        }
        temporary_download_root: Path | None = None

        def fake_download(_asset: dict[str, object], archive: Path) -> None:
            nonlocal temporary_download_root
            temporary_download_root = archive.parent
            archive.write_bytes(b"fixture")

        def fake_extract(_archive: Path, destination: Path) -> None:
            package_root = destination / "addons" / "godotsteam"
            package_root.mkdir(parents=True)
            (package_root / "godotsteam.gdextension").write_text("fixture", encoding="utf-8")

        with tempfile.TemporaryDirectory() as temporary_directory:
            lab_root = Path(temporary_directory) / "steamworks_lab"
            lab_root.mkdir()
            godot = Path(temporary_directory) / "Godot.exe"
            godot.touch()
            legacy_root = lab_root / ".toolchain"
            legacy_root.mkdir()
            (legacy_root / "legacy.bin").touch()
            with (
                mock.patch.object(toolchain, "LAB_ROOT", lab_root),
                mock.patch.object(toolchain, "LEGACY_TOOLCHAIN_ROOT", legacy_root),
                mock.patch.object(toolchain, "_validate_normal_godot", return_value="4.7.1.stable.official"),
                mock.patch.object(toolchain, "_ensure_download", side_effect=fake_download),
                mock.patch.object(toolchain, "_extract_zip", side_effect=fake_extract),
            ):
                toolchain._setup(lock, godot)

            self.assertTrue((lab_root / "addons" / "godotsteam" / "godotsteam.gdextension").is_file())
            self.assertFalse(legacy_root.exists())
            self.assertFalse((lab_root / "addons" / "godotsteam.tmp").exists())
            self.assertFalse((lab_root / "addons" / "godotsteam.bak").exists())

        self.assertIsNotNone(temporary_download_root)
        self.assertFalse(temporary_download_root.exists())

    def test_install_restores_existing_plugin_when_replacement_fails(self) -> None:
        lock = {
            "install_dir": "addons/godotsteam",
            "required_files": {"extension": "godotsteam.gdextension"},
        }
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            lab_root = root / "steamworks_lab"
            install_root = lab_root / "addons" / "godotsteam"
            install_root.mkdir(parents=True)
            (install_root / "old.marker").write_text("old", encoding="utf-8")
            package_root = root / "package"
            package_root.mkdir()
            (package_root / "godotsteam.gdextension").write_text("new", encoding="utf-8")
            staging_root = install_root.with_name("godotsteam.tmp")
            backup_root = install_root.with_name("godotsteam.bak")
            original_replace = os.replace
            replace_calls: list[tuple[Path, Path]] = []

            def fail_staging_replace(source: str | os.PathLike[str], target: str | os.PathLike[str]) -> None:
                replace_calls.append((Path(source), Path(target)))
                if len(replace_calls) == 2:
                    raise OSError("forced replacement failure")
                original_replace(source, target)

            with (
                mock.patch.object(toolchain, "LAB_ROOT", lab_root),
                mock.patch.object(os, "replace", new=fail_staging_replace),
            ):
                with self.assertRaisesRegex(OSError, "forced replacement failure"):
                    toolchain._install_package(lock, package_root)

            self.assertEqual((install_root / "old.marker").read_text(encoding="utf-8"), "old")
            self.assertFalse((install_root / "godotsteam.gdextension").exists())
            self.assertFalse(staging_root.exists())
            self.assertFalse(backup_root.exists())
            self.assertEqual(
                [(source.name, target.name) for source, target in replace_calls],
                [
                    ("godotsteam", "godotsteam.bak"),
                    ("godotsteam.tmp", "godotsteam"),
                    ("godotsteam.bak", "godotsteam"),
                ],
            )

    def test_template_lookup_uses_exact_editor_version_in_user_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            appdata = Path(temporary_directory)
            template_root = appdata / "Godot" / "export_templates" / "4.7.1.stable"
            template_root.mkdir(parents=True)
            for file_name in toolchain.STANDARD_TEMPLATE_NAMES:
                (template_root / file_name).touch()
            with mock.patch.dict(os.environ, {"APPDATA": str(appdata)}):
                resolved = toolchain._find_standard_template_root("4.7.1.stable.official.a13da4feb")
            self.assertEqual(resolved, template_root.resolve())

    def test_template_lookup_reports_exact_missing_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            appdata = Path(temporary_directory)
            expected = appdata / "Godot" / "export_templates" / "4.7.1.stable"
            with mock.patch.dict(os.environ, {"APPDATA": str(appdata)}):
                with self.assertRaisesRegex(toolchain.ToolchainError, str(expected).replace("\\", "\\\\")):
                    toolchain._find_standard_template_root("4.7.1.stable.official.a13da4feb")

    def test_export_preset_no_longer_requires_toolchain_exclusion(self) -> None:
        preset_text = "\n".join(
            [
                '[preset.0]',
                'name="Windows Desktop"',
                'exclude_filter="steam_appid.txt, tests/*, addons/godotsteam/editor/*, addons/godotsteam/plugin.cfg, addons/godotsteam/godotsteam_plugin.gd"',
                'custom_template/debug=""',
                'custom_template/release=""',
            ]
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            preset_path = Path(temporary_directory) / "export_presets.cfg"
            preset_path.write_text(preset_text, encoding="utf-8")
            with mock.patch.object(toolchain, "EXPORT_PRESET_PATH", preset_path):
                self.assertEqual(toolchain._verified_export_preset_text(), preset_text)


if __name__ == "__main__":
    unittest.main()
