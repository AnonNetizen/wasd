#!/usr/bin/env python3
"""Regression tests for the Steamworks Slime Lab dependency tool."""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import steamworks_lab_toolchain as toolchain


class SteamworksLabToolchainTests(unittest.TestCase):
    def test_repository_keeps_development_steam_appid(self) -> None:
        self.assertEqual(toolchain._verify_development_app_id().decode("utf-8-sig").strip(), "4955670")

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

    def test_windows_smoke_prefers_console_sibling(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            editor = root / "Godot.exe"
            console = root / "Godot_console.exe"
            editor.touch()
            console.touch()
            with mock.patch.object(toolchain.os, "name", "nt"):
                self.assertEqual(toolchain._godot_cli_executable(editor), console.resolve())

    def test_isolated_smoke_environment_redirects_every_user_root(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory) / "isolated"
            environment = toolchain._isolated_smoke_environment(root)
            for key in [
                "APPDATA",
                "LOCALAPPDATA",
                "HOME",
                "XDG_DATA_HOME",
                "XDG_CONFIG_HOME",
                "XDG_CACHE_HOME",
            ]:
                isolated_path = Path(environment[key])
                self.assertTrue(isolated_path.is_dir())
                self.assertTrue(isolated_path.is_relative_to(root))

    def test_smoke_result_requires_exact_success_marker(self) -> None:
        result = subprocess.CompletedProcess(["godot"], 0, "[suite] PASS close enough\n", "")
        with self.assertRaisesRegex(toolchain.ToolchainError, "missing exact success marker"):
            toolchain._validate_smoke_result("fixture", result, "[suite] ALL PASS")

    def test_smoke_result_rejects_nonzero_and_script_error(self) -> None:
        result = subprocess.CompletedProcess(
            ["godot"],
            1,
            "[suite] ALL PASS\nSCRIPT ERROR: fixture failed\n",
            "",
        )
        with self.assertRaisesRegex(toolchain.ToolchainError, "exit code 1"):
            toolchain._validate_smoke_result("fixture", result, "[suite] ALL PASS")

    def test_enet_smoke_result_rejects_mtu_warning(self) -> None:
        result = subprocess.CompletedProcess(
            ["godot"],
            0,
            "[net-host-smoke] ALL PASS\npacket above the MTU\n",
            "",
        )
        with self.assertRaisesRegex(toolchain.ToolchainError, "above the MTU"):
            toolchain._validate_smoke_result(
                "ENet host",
                result,
                "[net-host-smoke] ALL PASS",
                forbidden_markers=["above the MTU"],
            )

    def test_lightweight_client_copy_excludes_addons_build_and_cache(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            lab_root = root / "source"
            destination = root / "client"
            lab_root.mkdir()
            (lab_root / "project.godot").write_text("[application]\n", encoding="utf-8")
            for directory_name in ["scenes", "scripts", "tests", "addons", "build", ".godot"]:
                directory = lab_root / directory_name
                directory.mkdir()
                (directory / "fixture.txt").write_text(directory_name, encoding="utf-8")
            with mock.patch.object(toolchain, "LAB_ROOT", lab_root):
                toolchain._copy_lightweight_lab_project(destination)
            for included in ["project.godot", "scenes", "scripts", "tests"]:
                self.assertTrue((destination / included).exists())
            for excluded in ["addons", "build", ".godot"]:
                self.assertFalse((destination / excluded).exists())

    def test_protected_file_snapshot_detects_source_or_player_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            app_id = root / "steam_appid.txt"
            user_root = root / "user"
            user_root.mkdir()
            save_path = user_root / "save.cfg"
            app_id.write_text("4955670\n", encoding="utf-8")
            save_path.write_text("before", encoding="utf-8")
            with (
                mock.patch.object(toolchain, "STEAM_APP_ID_PATH", app_id),
                mock.patch.object(toolchain, "_default_godot_user_root", return_value=user_root),
            ):
                snapshot = toolchain._snapshot_protected_files()
                save_path.write_text("after", encoding="utf-8")
                with self.assertRaisesRegex(toolchain.ToolchainError, "protected player/source files"):
                    toolchain._assert_protected_files_unchanged(snapshot)

    def test_missing_development_app_id_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            missing = Path(temporary_directory) / "steam_appid.txt"
            with mock.patch.object(toolchain, "STEAM_APP_ID_PATH", missing):
                with self.assertRaisesRegex(toolchain.ToolchainError, "steam_appid.txt is missing"):
                    toolchain._verify_development_app_id()

    def test_net_smoke_command_propagates_dynamic_port(self) -> None:
        command = toolchain._net_smoke_command(
            Path("godot_console.exe"),
            Path("client-project"),
            "res://tests/net_client_smoke.gd",
            31_337,
        )
        self.assertEqual(command[-2:], ["--net-smoke-port", "31337"])

    def test_timeout_path_terminates_running_process(self) -> None:
        class FakeProcess:
            def __init__(self) -> None:
                self.returncode: int | None = None
                self.terminated = False
                self.killed = False

            def poll(self) -> int | None:
                return self.returncode

            def terminate(self) -> None:
                self.terminated = True
                self.returncode = -15

            def kill(self) -> None:
                self.killed = True
                self.returncode = -9

            def wait(self, timeout: float | None = None) -> int:
                del timeout
                return int(self.returncode or 0)

        process = FakeProcess()
        with mock.patch.object(toolchain.time, "monotonic", side_effect=[0.0, 2.0, 2.0]):
            self.assertFalse(toolchain._wait_for_processes([process], 1.0))  # type: ignore[list-item]
        toolchain._terminate_processes([process])  # type: ignore[list-item]
        self.assertTrue(process.terminated)

    def test_single_process_timeout_reports_partial_output(self) -> None:
        timeout = subprocess.TimeoutExpired(
            ["godot", "--headless"],
            toolchain.SMOKE_TIMEOUT_SECONDS,
            output=b"partial stdout\n",
            stderr=b"partial stderr\n",
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            with (
                mock.patch.object(toolchain, "_run", side_effect=timeout),
                mock.patch.object(toolchain, "_print_failed_smoke_output") as print_output,
            ):
                with self.assertRaisesRegex(toolchain.ToolchainError, "timed out"):
                    toolchain._run_smoke_command(
                        ["godot", "--headless"],
                        Path(temporary_directory),
                        "fixture",
                        "[fixture] ALL PASS",
                        Path(temporary_directory) / "isolated",
                    )
        print_output.assert_called_once_with("fixture", "partial stdout\npartial stderr")


if __name__ == "__main__":
    unittest.main()
