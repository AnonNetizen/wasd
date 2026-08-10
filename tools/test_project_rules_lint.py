#!/usr/bin/env python3
"""Regression tests for tools/lint_project_rules.py."""

from __future__ import annotations

import json
import tempfile
from pathlib import Path

import lint_project_rules


def main() -> int:
    tests = [
        ("golden project rules pass", _test_golden_project_rules_pass),
        ("undocumented data field fails", _test_undocumented_data_field_fails),
        ("missing locale translation fails", _test_missing_locale_translation_fails),
        ("release preset dev tools fail", _test_release_preset_dev_tools_fail),
        ("release preset missing debug excludes fails", _test_release_preset_missing_debug_excludes_fails),
        ("release preset missing GUT excludes fails", _test_release_preset_missing_gut_excludes_fails),
        ("enabled GUT editor plugin fails", _test_enabled_gut_editor_plugin_fails),
        ("formal arena coupling fails", _test_formal_arena_coupling_fails),
        ("InputService UIManager dependency fails", _test_input_service_ui_dependency_fails),
        ("RunLoop presentation node access fails", _test_runloop_presentation_node_access_fails),
        ("default smoke user environment fails", _test_default_smoke_user_environment_fails),
        ("malformed smoke catalog fails closed", _test_malformed_smoke_catalog_fails_closed),
        ("unisolated GUT runner fails", _test_unisolated_gut_runner_fails),
        ("reassigned GUT environment fails", _test_reassigned_gut_environment_fails),
        ("unrelated GUT temporary directory fails", _test_unrelated_gut_temporary_directory_fails),
        ("direct smoke process runner fails", _test_direct_smoke_process_runner_fails),
        ("runtime workflow command bypass fails", _test_runtime_workflow_command_bypass_fails),
        ("folded runtime workflow bypass fails", _test_folded_runtime_workflow_bypass_fails),
    ]

    for name, test in tests:
        try:
            test()
        except AssertionError as exc:
            print(f"[project-rules-lint-test] {name}: failed: {exc}")
            return 1
        print(f"[project-rules-lint-test] {name}: passed")

    print("project rules lint tests passed")
    return 0


def _test_golden_project_rules_pass() -> None:
    with _temporary_project() as root:
        _write_minimal_project(root)
        _with_project_root(root)
        assert not lint_project_rules._check_data_fields_documented()
        assert not lint_project_rules._check_locale_bilingual()
        assert not lint_project_rules._check_release_presets()
        assert not lint_project_rules._check_gut_editor_plugin_disabled()
        assert not lint_project_rules._check_architecture_boundaries()


def _test_undocumented_data_field_fails() -> None:
    with _temporary_project() as root:
        _write_minimal_project(root, item={"id": "item_a", "rarity": "rare"})
        _with_project_root(root)
        errors = lint_project_rules._check_data_fields_documented()
        assert any(error.field == "items[].rarity" for error in errors), [error.format() for error in errors]


def _test_missing_locale_translation_fails() -> None:
    with _temporary_project() as root:
        _write_minimal_project(root, locale_en="")
        _with_project_root(root)
        errors = lint_project_rules._check_locale_bilingual()
        assert any("missing en translation" in error.message for error in errors), [error.format() for error in errors]


def _test_release_preset_dev_tools_fail() -> None:
    with _temporary_project() as root:
        _write_minimal_project(root)
        (root / "client" / "export_presets.cfg").write_text(
            "\n".join(
                [
                    "[preset.0]",
                    'name="Windows"',
                    'export_path="build/windows/wasd.exe"',
                    'custom_features="dev_tools"',
                    "",
                ]
            ),
            encoding="utf-8",
        )
        _with_project_root(root)
        errors = lint_project_rules._check_release_presets()
        assert any(error.rule == "release-debug-assets" for error in errors), [error.format() for error in errors]


def _test_release_preset_missing_debug_excludes_fails() -> None:
    with _temporary_project() as root:
        _write_minimal_project(root)
        (root / "client" / "export_presets.cfg").write_text(
            "\n".join(
                [
                    "[preset.0]",
                    'name="Windows"',
                    'export_path="build/windows/wasd.exe"',
                    'custom_features=""',
                    'exclude_filter="scripts/editor/*"',
                    "",
                ]
            ),
            encoding="utf-8",
        )
        _with_project_root(root)
        errors = lint_project_rules._check_release_presets()
        assert any(
            "test-arena resources" in error.message
            for error in errors
        ), [error.format() for error in errors]


def _test_release_preset_missing_gut_excludes_fails() -> None:
    with _temporary_project() as root:
        _write_minimal_project(root)
        (root / "client" / "export_presets.cfg").write_text(
            "\n".join(
                [
                    "[preset.0]",
                    'name="Windows"',
                    'export_path="build/windows/wasd.exe"',
                    'custom_features=""',
                    (
                        'exclude_filter="scenes/debug/*,scripts/debug/*,'
                        'tools/debug_test_arena_smoke.gd,'
                        'tools/debug_tools_smoke.gd"'
                    ),
                    "",
                ]
            ),
            encoding="utf-8",
        )
        _with_project_root(root)
        errors = lint_project_rules._check_release_presets()
        assert any(
            error.rule == "release-test-assets"
            and "addons/gut/*" in error.message
            and "tests/*" in error.message
            for error in errors
        ), [error.format() for error in errors]


def _test_enabled_gut_editor_plugin_fails() -> None:
    with _temporary_project() as root:
        _write_minimal_project(root)
        (root / "client" / "project.godot").write_text(
            "\n".join(
                [
                    "[editor_plugins]",
                    (
                        'enabled=PackedStringArray('
                        '"res://addons/gut/plugin.cfg")'
                    ),
                    "",
                ]
            ),
            encoding="utf-8",
        )
        _with_project_root(root)
        errors = lint_project_rules._check_gut_editor_plugin_disabled()
        assert any(
            error.rule == "gut-editor-plugin-offline"
            for error in errors
        ), [error.format() for error in errors]


def _test_formal_arena_coupling_fails() -> None:
    with _temporary_project() as root:
        _write_minimal_project(root)
        boot = (
            root
            / "client"
            / "scripts"
            / "boot"
            / "formal_client_boot.gd"
        )
        boot.write_text(
            'const DEBUG_TEST_ARENA_SCENE = "res://debug.tscn"\n',
            encoding="utf-8",
        )
        _with_project_root(root)
        errors = lint_project_rules._check_debug_test_arena_standalone()
        assert any(
            error.rule == "standalone-debug-test-arena"
            for error in errors
        ), [error.format() for error in errors]


def _test_input_service_ui_dependency_fails() -> None:
    with _temporary_project() as root:
        _write_minimal_project(root)
        _with_project_root(root)
        lint_project_rules.INPUT_SERVICE_SCRIPT.write_text(
            "extends Node\nvar active := UIManager.active_count()\n",
            encoding="utf-8",
        )
        errors = lint_project_rules._check_architecture_boundaries()
        assert any(
            error.rule == "input-service-ui-one-way"
            for error in errors
        ), [error.format() for error in errors]


def _test_runloop_presentation_node_access_fails() -> None:
    with _temporary_project() as root:
        _write_minimal_project(root)
        _with_project_root(root)
        lint_project_rules.GAMEPLAY_RUN_LOOP_SCRIPT.write_text(
            "\n".join([
                "extends Node",
                'var visual := actor.get_node_or_null("Player/Visual")',
                "var presentation := $Presentation",
                'var nested := actor.get_node(NodePath("Visual/Body"))',
                "",
            ]),
            encoding="utf-8",
        )
        errors = lint_project_rules._check_architecture_boundaries()
        presentation_errors = [
            error for error in errors
            if error.rule == "runloop-presentation-facade"
        ]
        assert len(presentation_errors) == 3, [
            error.format() for error in errors
        ]


def _test_default_smoke_user_environment_fails() -> None:
    with _temporary_project() as root:
        _write_minimal_project(root)
        _with_project_root(root)
        lint_project_rules.SMOKE_COMMAND_CATALOG.write_text(
            json.dumps({
                "schema_version": 1,
                "commands": [{
                    "id": "bad-smoke",
                    "isolation": "default_user_environment",
                }],
            }),
            encoding="utf-8",
        )
        errors = lint_project_rules._check_architecture_boundaries()
        assert any(
            error.rule == "test-user-environment-isolation"
            and "commands[0].isolation" in error.field
            for error in errors
        ), [error.format() for error in errors]


def _test_malformed_smoke_catalog_fails_closed() -> None:
    with _temporary_project() as root:
        _write_minimal_project(root)
        _with_project_root(root)
        lint_project_rules.SMOKE_COMMAND_CATALOG.write_text(
            json.dumps({"schema_version": 1, "commands": {}}),
            encoding="utf-8",
        )
        errors = lint_project_rules._check_architecture_boundaries()
        assert any(
            error.rule == "test-user-environment-isolation"
            and error.field == "commands"
            for error in errors
        ), [error.format() for error in errors]


def _test_unisolated_gut_runner_fails() -> None:
    with _temporary_project() as root:
        _write_minimal_project(root)
        _with_project_root(root)
        unsafe_gut = "\n".join([
            "def _run_gut(godot, project):",
            "    # tempfile.TemporaryDirectory, _isolated_user_environment, env=isolated_env",
            "    with tempfile.TemporaryDirectory() as directory:",
            "        isolated_env = _isolated_user_environment(directory)",
            "        _run_command([], env=isolated_env)",
            "    return _run_command([])",
            "",
        ])
        lint_project_rules.GODOT_BRIDGE_SCRIPT.write_text(
            _replace_bridge_function(_safe_bridge_source(), "_run_gut", unsafe_gut),
            encoding="utf-8",
        )
        errors = lint_project_rules._check_architecture_boundaries()
        assert any(
            error.rule == "test-user-environment-isolation"
            and error.field == "_run_gut"
            for error in errors
        ), [error.format() for error in errors]


def _test_reassigned_gut_environment_fails() -> None:
    with _temporary_project() as root:
        _write_minimal_project(root)
        _with_project_root(root)
        unsafe_gut = "\n".join([
            "def _run_gut(godot, project):",
            "    with tempfile.TemporaryDirectory() as directory:",
            "        root = Path(directory)",
            "        isolated_env = _isolated_user_environment(root)",
            "        isolated_env = {}",
            "        return _run_command([], env=isolated_env)",
            "",
        ])
        lint_project_rules.GODOT_BRIDGE_SCRIPT.write_text(
            _replace_bridge_function(_safe_bridge_source(), "_run_gut", unsafe_gut),
            encoding="utf-8",
        )
        errors = lint_project_rules._check_architecture_boundaries()
        assert any(error.field == "_run_gut" for error in errors), [
            error.format() for error in errors
        ]


def _test_unrelated_gut_temporary_directory_fails() -> None:
    with _temporary_project() as root:
        _write_minimal_project(root)
        _with_project_root(root)
        unsafe_gut = "\n".join([
            "def _run_gut(godot, project):",
            "    isolated_env = _isolated_user_environment(Path('C:/real-user'))",
            "    with tempfile.TemporaryDirectory() as directory:",
            "        return _run_command([], env=isolated_env)",
            "",
        ])
        lint_project_rules.GODOT_BRIDGE_SCRIPT.write_text(
            _replace_bridge_function(_safe_bridge_source(), "_run_gut", unsafe_gut),
            encoding="utf-8",
        )
        errors = lint_project_rules._check_architecture_boundaries()
        assert any(error.field == "_run_gut" for error in errors), [
            error.format() for error in errors
        ]


def _test_direct_smoke_process_runner_fails() -> None:
    with _temporary_project() as root:
        _write_minimal_project(root)
        _with_project_root(root)
        unsafe_smoke = "\n".join([
            "def _run_smoke_command(command, project):",
            "    return _run_command(command, cwd=project)",
            "",
        ])
        lint_project_rules.GODOT_BRIDGE_SCRIPT.write_text(
            _replace_bridge_function(
                _safe_bridge_source(),
                "_run_smoke_command",
                unsafe_smoke,
            ),
            encoding="utf-8",
        )
        errors = lint_project_rules._check_architecture_boundaries()
        assert any(
            error.field == "_run_smoke_command"
            for error in errors
        ), [error.format() for error in errors]


def _test_runtime_workflow_command_bypass_fails() -> None:
    with _temporary_project() as root:
        _write_minimal_project(root)
        _with_project_root(root)
        lint_project_rules.GODOT_RUNTIME_WORKFLOW.write_text(
            "\n".join([
                "jobs:",
                "  runtime-tests:",
                "    name: python tools/godot_bridge.py --project client gut",
                "    steps:",
                "      - name: Unsafe runtime tests",
                "        run: python tools/unsafe_runner.py",
                "",
            ]),
            encoding="utf-8",
        )
        errors = lint_project_rules._check_architecture_boundaries()
        assert any(
            error.path == lint_project_rules.GODOT_RUNTIME_WORKFLOW
            and error.field == "runtime-tests"
            for error in errors
        ), [error.format() for error in errors]


def _test_folded_runtime_workflow_bypass_fails() -> None:
    with _temporary_project() as root:
        _write_minimal_project(root)
        _with_project_root(root)
        lint_project_rules.GODOT_RUNTIME_WORKFLOW.write_text(
            "\n".join([
                "jobs:",
                "  runtime-tests:",
                "    steps:",
                "      - name: Unsafe folded step",
                "        run: >",
                "          echo",
                "          python tools/godot_bridge.py --project client gut",
                "",
            ]),
            encoding="utf-8",
        )
        errors = lint_project_rules._check_architecture_boundaries()
        assert any(
            error.path == lint_project_rules.GODOT_RUNTIME_WORKFLOW
            and error.field == "runtime-tests"
            for error in errors
        ), [error.format() for error in errors]

        lint_project_rules.GODOT_RUNTIME_WORKFLOW.write_text(
            "\n".join([
                "jobs:",
                "  runtime-tests:",
                "    steps:",
                "      - name: Safe folded step",
                "        run: >",
                "          python",
                "          tools/godot_bridge.py --project client gut",
                "",
            ]),
            encoding="utf-8",
        )
        errors = lint_project_rules._check_architecture_boundaries()
        assert not any(
            error.path == lint_project_rules.GODOT_RUNTIME_WORKFLOW
            for error in errors
        ), [error.format() for error in errors]


def _write_minimal_project(root: Path, *, item: dict[str, str] | None = None, locale_en: str = "Play") -> None:
    data_dir = root / "client" / "data"
    locale_dir = root / "client" / "locale"
    boot_dir = root / "client" / "scripts" / "boot"
    title_script_dir = root / "client" / "scripts" / "ui"
    title_scene_dir = root / "client" / "scenes" / "ui"
    input_service_dir = root / "client" / "scripts" / "autoload"
    gameplay_dir = root / "client" / "scripts" / "gameplay"
    tools_dir = root / "client" / "tools"
    root_tools_dir = root / "tools"
    workflow_dir = root / ".github" / "workflows"
    data_dir.mkdir(parents=True)
    locale_dir.mkdir(parents=True)
    boot_dir.mkdir(parents=True)
    title_script_dir.mkdir(parents=True)
    title_scene_dir.mkdir(parents=True)
    input_service_dir.mkdir(parents=True)
    gameplay_dir.mkdir(parents=True)
    tools_dir.mkdir(parents=True)
    root_tools_dir.mkdir(parents=True)
    workflow_dir.mkdir(parents=True)

    (data_dir / "README.md").write_text(
        "\n".join(
            [
                "# Data",
                "",
                "| 字段路径 | 说明 |",
                "|----------|------|",
                "| `items[].id` | item id |",
                "",
            ]
        ),
        encoding="utf-8",
    )
    (data_dir / "items.json").write_text(
        json.dumps({"schema_version": 1, "items": [item or {"id": "item_a"}]}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    (locale_dir / "strings.csv").write_text(f"keys,zh_CN,en\nui_play,开始,{locale_en}\n", encoding="utf-8")
    (root / "client" / "export_presets.cfg").write_text(
        "\n".join(
            [
                "[preset.0]",
                'name="Windows"',
                'export_path="build/windows/wasd.exe"',
                'custom_features=""',
                (
                    'exclude_filter="scenes/debug/*,scripts/debug/*,'
                    '.gutconfig.json,addons/gut/*,tests/*,'
                    'tools/debug_test_arena_smoke.gd,'
                    'tools/debug_tools_smoke.gd"'
                ),
                "",
            ]
        ),
        encoding="utf-8",
    )
    (root / "client" / "project.godot").write_text(
        "[editor_plugins]\nenabled=PackedStringArray()\n",
        encoding="utf-8",
    )
    (boot_dir / "formal_client_boot.gd").write_text(
        "extends Node\n",
        encoding="utf-8",
    )
    (title_script_dir / "title_menu.gd").write_text(
        "extends CanvasLayer\n",
        encoding="utf-8",
    )
    (title_scene_dir / "title_menu.tscn").write_text(
        "[gd_scene format=3]\n",
        encoding="utf-8",
    )
    (input_service_dir / "input_service.gd").write_text(
        "extends Node\n# UIManager is push-only and is not referenced by code.\n",
        encoding="utf-8",
    )
    (gameplay_dir / "gameplay_run_loop.gd").write_text(
        "extends Node\n",
        encoding="utf-8",
    )
    (tools_dir / "smoke_commands.json").write_text(
        json.dumps({
            "schema_version": 1,
            "commands": [{
                "id": "good-smoke",
                "isolation": "temporary_user_environment",
            }],
        }),
        encoding="utf-8",
    )
    (root_tools_dir / "godot_bridge.py").write_text(
        _safe_bridge_source(),
        encoding="utf-8",
    )
    (workflow_dir / "godot-runtime.yml").write_text(
        "\n".join([
            "jobs:",
            "  runtime-tests:",
            "    steps:",
            "      - name: Run GUT",
            "        run: python tools/godot_bridge.py --project client gut",
            "",
        ]),
        encoding="utf-8",
    )


def _safe_bridge_source() -> str:
    return "\n".join([
        "def _run_gut(godot, project):",
        "    with tempfile.TemporaryDirectory() as directory:",
        "        root = Path(directory)",
        "        isolated_env = _isolated_user_environment(root / 'user')",
        "        return _run_command([], env=isolated_env)",
        "",
        "def _run_isolated_command(command, cwd):",
        "    with tempfile.TemporaryDirectory() as directory:",
        "        root = Path(directory)",
        "        isolated_env = _isolated_user_environment(root)",
        "        return _run_command(command, cwd=cwd, env=isolated_env)",
        "",
        "def _verify_release_debug_resource_exclusion(godot, project):",
        "    with tempfile.TemporaryDirectory() as directory:",
        "        root = Path(directory)",
        "        isolated_env = _isolated_user_environment(root / 'user')",
        "        return _run_command([], cwd=project, env=isolated_env)",
        "",
        "def _run_smoke_command(command, project):",
        "    return _run_isolated_command(command, cwd=project)",
        "",
    ])


def _replace_bridge_function(source: str, name: str, replacement: str) -> str:
    start = source.index(f"def {name}(")
    next_function = source.find("\ndef ", start + 1)
    end = len(source) if next_function < 0 else next_function + 1
    return f"{source[:start]}{replacement}{source[end:]}"


class _temporary_project:
    def __enter__(self) -> Path:
        self._directory = tempfile.TemporaryDirectory()
        return Path(self._directory.name)

    def __exit__(self, exc_type: object, exc_value: object, traceback: object) -> None:
        self._directory.cleanup()


def _with_project_root(root: Path) -> None:
    lint_project_rules.ROOT = root
    lint_project_rules.CLIENT_DATA = root / "client" / "data"
    lint_project_rules.DATA_README = lint_project_rules.CLIENT_DATA / "README.md"
    lint_project_rules.LOCALE_CSV = root / "client" / "locale" / "strings.csv"
    lint_project_rules.EXPORT_PRESETS = root / "client" / "export_presets.cfg"
    lint_project_rules.PROJECT_GODOT = root / "client" / "project.godot"
    lint_project_rules.FORMAL_CLIENT_BOOT = (
        root / "client" / "scripts" / "boot" / "formal_client_boot.gd"
    )
    lint_project_rules.TITLE_MENU_SCRIPT = (
        root / "client" / "scripts" / "ui" / "title_menu.gd"
    )
    lint_project_rules.TITLE_MENU_SCENE = (
        root / "client" / "scenes" / "ui" / "title_menu.tscn"
    )
    lint_project_rules.INPUT_SERVICE_SCRIPT = (
        root / "client" / "scripts" / "autoload" / "input_service.gd"
    )
    lint_project_rules.GAMEPLAY_RUN_LOOP_SCRIPT = (
        root / "client" / "scripts" / "gameplay" / "gameplay_run_loop.gd"
    )
    lint_project_rules.SMOKE_COMMAND_CATALOG = (
        root / "client" / "tools" / "smoke_commands.json"
    )
    lint_project_rules.GODOT_BRIDGE_SCRIPT = root / "tools" / "godot_bridge.py"
    lint_project_rules.GODOT_RUNTIME_WORKFLOW = (
        root / ".github" / "workflows" / "godot-runtime.yml"
    )


if __name__ == "__main__":
    raise SystemExit(main())
