#!/usr/bin/env python3
"""Regression tests for tools/lint_semantic_rules.py."""

from __future__ import annotations

import tempfile
from pathlib import Path

import lint_semantic_rules


def main() -> int:
    tests = [
        ("golden semantic lint passes", _test_golden_semantic_lint_passes),
        ("special id branch warns", _test_special_id_branch_warns),
        ("business autoload bypass warns", _test_business_autoload_bypass_warns),
        ("direct audio playback warns but animation playback passes", _test_audio_playback_rule_is_scoped),
        ("editor tooling bypass passes", _test_editor_tooling_bypass_passes),
        ("direct pool and popup bypass warns", _test_direct_pool_and_popup_bypass_warns),
        ("registered pool factories and local nodes pass", _test_registered_pool_factories_and_local_nodes_pass),
        ("runtime node construction warns", _test_runtime_node_construction_warns),
        ("row template instantiation passes", _test_row_template_instantiation_passes),
        ("missing type signature warns", _test_missing_type_signature_warns),
        ("missing doc header warns", _test_missing_doc_header_warns),
        ("unknown contract constant warns", _test_unknown_contract_constant_warns),
        ("advisory main exits zero", _test_advisory_main_exits_zero),
    ]

    for name, test in tests:
        try:
            test()
        except AssertionError as exc:
            print(f"[semantic-lint-test] {name}: failed: {exc}")
            return 1
        print(f"[semantic-lint-test] {name}: passed")

    print("semantic lint tests passed")
    return 0


def _test_golden_semantic_lint_passes() -> None:
    with _temporary_project() as root:
        _write_contract(root, "CharacterIds", {"VALUES", "CHARACTER_DEFAULT"})
        _write_script(
            root,
            "autoload/example.gd",
            "\n".join(
                [
                    "# Doc: docs/代码/example.md",
                    "extends Node",
                    "",
                    'const CHARACTER_IDS := preload("res://scripts/contracts/character_ids.gd")',
                    "",
                    "func get_default_character_id() -> String:",
                    "\treturn CHARACTER_IDS.CHARACTER_DEFAULT",
                    "",
                ]
            ),
        )
        _with_project_root(root)
        assert not lint_semantic_rules.run_checks()


def _test_special_id_branch_warns() -> None:
    with _temporary_project() as root:
        _write_contract(root, "CharacterIds", {"VALUES", "CHARACTER_DEFAULT"})
        _write_script(
            root,
            "autoload/example.gd",
            "\n".join(
                [
                    "# Doc: docs/代码/example.md",
                    "extends Node",
                    "",
                    "func is_default(character_id: String) -> bool:",
                    '\tif character_id == "character_default":',
                    "\t\treturn true",
                    "\treturn false",
                    "",
                ]
            ),
        )
        _with_project_root(root)
        warnings = lint_semantic_rules.run_checks()
        assert any(warning.rule == "special-id-branch" for warning in warnings), _format(warnings)


def _test_business_autoload_bypass_warns() -> None:
    with _temporary_project() as root:
        _write_contract(root, "CharacterIds", {"VALUES", "CHARACTER_DEFAULT"})
        _write_script(
            root,
            "player/player.gd",
            "\n".join(
                [
                    "# Doc: docs/代码/player.md",
                    "extends Node",
                    "",
                    "func roll() -> int:",
                    "\treturn randi()",
                    "",
                ]
            ),
        )
        _with_project_root(root)
        warnings = lint_semantic_rules.run_checks()
        assert any(warning.rule == "autoload-bypass-rng" for warning in warnings), _format(warnings)


def _test_audio_playback_rule_is_scoped() -> None:
    with _temporary_project() as root:
        _write_contract(root, "CharacterIds", {"VALUES", "CHARACTER_DEFAULT"})
        _write_script(
            root,
            "gameplay/presentation.gd",
            "\n".join(
                [
                    "# Doc: docs/代码/presentation.md",
                    "extends Node",
                    "",
                    "func play_feedback(audio_player: AudioStreamPlayer, animation_player: AnimationPlayer) -> void:",
                    "\taudio_player.play()",
                    '\tanimation_player.play(&"hit")',
                    "",
                ]
            ),
        )
        _with_project_root(root)
        warnings = [
            warning
            for warning in lint_semantic_rules.run_checks()
            if warning.rule == "autoload-bypass-audio"
        ]
        assert len(warnings) == 1, _format(warnings)
        assert warnings[0].line_number == 5, _format(warnings)


def _test_editor_tooling_bypass_passes() -> None:
    with _temporary_project() as root:
        _write_contract(root, "CharacterIds", {"VALUES", "CHARACTER_DEFAULT"})
        _write_script(
            root,
            "editor/baker.gd",
            "\n".join(
                [
                    "# Doc: docs/代码/module_authoring_pipeline.md",
                    "@tool",
                    "extends RefCounted",
                    "",
                    "func write_generated_file(path: String) -> void:",
                    "\tvar file: FileAccess = FileAccess.open(path, FileAccess.WRITE)",
                    "\tfile.store_string(\"generated\")",
                    "",
                ]
            ),
        )
        _with_project_root(root)
        warnings = lint_semantic_rules.run_checks()
        assert not any(warning.rule == "autoload-bypass-save-data" for warning in warnings), _format(warnings)


def _test_direct_pool_and_popup_bypass_warns() -> None:
    with _temporary_project() as root:
        _write_contract(root, "CharacterIds", {"VALUES", "CHARACTER_DEFAULT"})
        _write_script(
            root,
            "gameplay/spawner.gd",
            "\n".join(
                [
                    "# Doc: docs/代码/spawner.md",
                    "extends Node",
                    "",
                    "const ENEMY_SCENE: PackedScene = preload(\"res://enemy.tscn\")",
                    "",
                    "func spawn_enemy() -> void:",
                    "\tvar enemy: Node = ENEMY_SCENE.instantiate()",
                    "\tadd_child(enemy)",
                    "\tenemy.queue_free()",
                    "",
                    "func show_pause_menu(pause_menu: Control) -> void:",
                    "\tadd_child(pause_menu)",
                    "",
                ]
            ),
        )
        _with_project_root(root)
        warnings = [
            warning
            for warning in lint_semantic_rules.run_checks()
            if warning.rule == "autoload-bypass-pool-ui"
        ]
        assert len(warnings) == 4, _format(warnings)


def _test_registered_pool_factories_and_local_nodes_pass() -> None:
    with _temporary_project() as root:
        _write_contract(root, "CharacterIds", {"VALUES", "CHARACTER_DEFAULT"})
        _write_script(
            root,
            "gameplay/spawner.gd",
            "\n".join(
                [
                    "# Doc: docs/代码/spawner.md",
                    "extends Node",
                    "",
                    "const BULLET_SCENE: PackedScene = preload(\"res://bullet.tscn\")",
                    "const ENEMY_SCENE: PackedScene = preload(\"res://enemy.tscn\")",
                    "const INTEREST_POINT_SCENE: PackedScene = preload(\"res://interest_point.tscn\")",
                    "",
                    "func configure() -> void:",
                    "\tPoolManager.register_pool(\"bullet\", Callable(self, \"_create_bullet_node\"), 16)",
                    "\tPoolManager.register_pool(\"enemy\", _create_enemy_node, 8)",
                    "\tvar target: Node = INTEREST_POINT_SCENE.instantiate()",
                    "\tadd_child(target)",
                    "\ttarget.queue_free()",
                    "\tvar row: Label = Label.new()",
                    "\tadd_child(row)",
                    "\trow.queue_free()",
                    "",
                    "func _create_enemy_node() -> Node:",
                    "\treturn ENEMY_SCENE.instantiate()",
                    "",
                    "func _create_bullet_node() -> Node:",
                    "\treturn BULLET_SCENE.instantiate()",
                    "",
                ]
            ),
        )
        _with_project_root(root)
        warnings = lint_semantic_rules.run_checks()
        assert not any(warning.rule == "autoload-bypass-pool-ui" for warning in warnings), _format(warnings)


def _test_runtime_node_construction_warns() -> None:
    with _temporary_project() as root:
        _write_contract(root, "CharacterIds", {"VALUES", "CHARACTER_DEFAULT"})
        _write_script(
            root,
            "gameplay/runtime_ui.gd",
            "\n".join(
                [
                    "# Doc: docs/代码/runtime_ui.md",
                    "extends Node",
                    "",
                    'const PANEL_SCRIPT: Script = preload("res://panel.gd")',
                    "var _panel: Control",
                    "",
                    "func build_panel() -> void:",
                    "\tvar label: Label = Label.new()",
                    "\tadd_child(label)",
                    "\t_panel = PANEL_SCRIPT.new()",
                    "\tadd_child(_panel)",
                    "",
                ]
            ),
        )
        _with_project_root(root)
        warnings = lint_semantic_rules.run_checks()
        runtime_warnings = [warning for warning in warnings if warning.rule == "runtime-node-construction"]
        assert len(runtime_warnings) == 2, _format(warnings)


def _test_row_template_instantiation_passes() -> None:
    with _temporary_project() as root:
        _write_contract(root, "CharacterIds", {"VALUES", "CHARACTER_DEFAULT"})
        _write_script(
            root,
            "ui/data_list.gd",
            "\n".join(
                [
                    "# Doc: docs/代码/data_list.md",
                    "extends Control",
                    "",
                    'const ROW_SCENE: PackedScene = preload("res://row.tscn")',
                    "",
                    "func rebuild() -> void:",
                    "\tvar row: Control = ROW_SCENE.instantiate() as Control",
                    "\tadd_child(row)",
                    "",
                ]
            ),
        )
        _with_project_root(root)
        warnings = lint_semantic_rules.run_checks()
        assert not any(
            warning.rule in {"runtime-node-construction", "autoload-bypass-pool-ui"}
            for warning in warnings
        ), _format(warnings)


def _test_missing_type_signature_warns() -> None:
    with _temporary_project() as root:
        _write_contract(root, "CharacterIds", {"VALUES", "CHARACTER_DEFAULT"})
        _write_script(
            root,
            "autoload/example.gd",
            "\n".join(
                [
                    "# Doc: docs/代码/example.md",
                    "extends Node",
                    "",
                    "func use_value(value):",
                    "\treturn value",
                    "",
                ]
            ),
        )
        _with_project_root(root)
        warnings = lint_semantic_rules.run_checks()
        assert any(warning.rule == "missing-param-type" for warning in warnings), _format(warnings)
        assert any(warning.rule == "missing-return-type" for warning in warnings), _format(warnings)


def _test_missing_doc_header_warns() -> None:
    with _temporary_project() as root:
        _write_contract(root, "CharacterIds", {"VALUES", "CHARACTER_DEFAULT"})
        _write_script(root, "autoload/example.gd", "extends Node\n\nfunc ready() -> void:\n\tpass\n")
        _with_project_root(root)
        warnings = lint_semantic_rules.run_checks()
        assert any(warning.rule == "missing-doc-header" for warning in warnings), _format(warnings)


def _test_unknown_contract_constant_warns() -> None:
    with _temporary_project() as root:
        _write_contract(root, "CharacterIds", {"VALUES", "CHARACTER_DEFAULT"})
        _write_script(
            root,
            "autoload/example.gd",
            "\n".join(
                [
                    "# Doc: docs/代码/example.md",
                    "extends Node",
                    "",
                    'const CHARACTER_IDS := preload("res://scripts/contracts/character_ids.gd")',
                    "",
                    "func broken() -> String:",
                    "\treturn CHARACTER_IDS.MISSING_CHARACTER",
                    "",
                ]
            ),
        )
        _with_project_root(root)
        warnings = lint_semantic_rules.run_checks()
        assert any(warning.rule == "unknown-contract-constant" for warning in warnings), _format(warnings)


def _test_advisory_main_exits_zero() -> None:
    with _temporary_project() as root:
        _write_contract(root, "CharacterIds", {"VALUES", "CHARACTER_DEFAULT"})
        _write_script(root, "autoload/example.gd", "extends Node\n\nfunc ready():\n\tpass\n")
        _with_project_root(root)
        assert lint_semantic_rules.main([]) == 0
        assert lint_semantic_rules.main(["--strict"]) == 1


def _write_contract(root: Path, class_name: str, constants: set[str]) -> None:
    contracts_dir = root / "client" / "scripts" / "contracts"
    contracts_dir.mkdir(parents=True, exist_ok=True)
    file_name = _class_to_file_name(class_name)
    lines = [f"class_name {class_name}", ""]
    for constant in sorted(constants):
        lines.append(f'const {constant}: String = "{constant.lower()}"')
    (contracts_dir / file_name).write_text("\n".join(lines) + "\n", encoding="utf-8")


def _write_script(root: Path, relative_path: str, content: str) -> None:
    path = root / "client" / "scripts" / relative_path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def _class_to_file_name(class_name: str) -> str:
    chars: list[str] = []
    for index, char in enumerate(class_name):
        if char.isupper() and index > 0:
            chars.append("_")
        chars.append(char.lower())
    return "".join(chars) + ".gd"


def _format(warnings: list[lint_semantic_rules.AdvisoryWarning]) -> list[str]:
    return [warning.format() for warning in warnings]


class _temporary_project:
    def __enter__(self) -> Path:
        self._directory = tempfile.TemporaryDirectory()
        return Path(self._directory.name)

    def __exit__(self, exc_type: object, exc_value: object, traceback: object) -> None:
        self._directory.cleanup()


def _with_project_root(root: Path) -> None:
    lint_semantic_rules.ROOT = root
    lint_semantic_rules.CLIENT_DIR = root / "client"
    lint_semantic_rules.SCRIPTS_DIR = root / "client" / "scripts"
    lint_semantic_rules.CONTRACTS_DIR = root / "client" / "scripts" / "contracts"


if __name__ == "__main__":
    raise SystemExit(main())
