#!/usr/bin/env python3
"""Regression tests for DataLoader-facing project data schema validation."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from collections.abc import Callable
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]


JsonMutator = Callable[[dict[str, Any]], None]
RepoMutator = Callable[[Path], None]


def main() -> int:
    cases: list[tuple[str, RepoMutator | None, list[str]]] = [
        ("golden data passes", None, []),
        (
            "unknown character id fails",
            _mutate_json("client/data/characters.json", _set_character_id("character_unregistered")),
            [
                "client/data/characters.json:characters[0].id",
                "unknown id character_unregistered; expected one of character_ids",
            ],
        ),
        (
            "missing character locale key fails",
            _mutate_json("client/data/characters.json", _set_character_name_key("character_missing_name")),
            [
                "client/data/characters.json:characters[0].name_key",
                "locale key is missing from client/locale/strings.csv: character_missing_name",
            ],
        ),
        (
            "wrong stat type fails",
            _mutate_json("client/data/characters.json", _set_character_stat("max_hp", "six")),
            [
                "client/data/characters.json:characters[0].base_stats.max_hp",
                "must be int",
            ],
        ),
        (
            "invalid stat range fails",
            _mutate_json("client/data/characters.json", _set_character_stat("move_speed", 0)),
            [
                "client/data/characters.json:characters[0].base_stats.move_speed",
                "must be > 0",
            ],
        ),
        (
            "mode character reference must exist",
            _mutate_json("client/data/characters.json", _clear_characters),
            [
                "client/data/game_modes.json:modes[0].resource_pools.characters[0].id",
                "character is not defined in characters.json: character_default",
            ],
        ),
        (
            "meta unlock character target must exist",
            _mutate_json("client/data/meta_progression.json", _set_meta_character_target("character_missing")),
            [
                "client/data/meta_progression.json:unlocks[0].target_id",
                "character is not defined in characters.json: character_missing",
            ],
        ),
        (
            "unknown game mode id fails",
            _mutate_json("client/data/game_modes.json", _set_game_mode_id("mode_unregistered")),
            [
                "client/data/game_modes.json:modes[0].id",
                "unknown id mode_unregistered; expected one of game_modes",
            ],
        ),
        (
            "missing growth pool reference fails",
            _mutate_json("client/data/game_modes.json", _set_mode_growth_pool("missing_pool")),
            [
                "client/data/game_modes.json:modes[0].resource_pools.growth_pools[0].id",
                "pool is not defined in growth_pools.json: missing_pool",
            ],
        ),
        (
            "unknown weapon damage type fails",
            _mutate_json("client/data/weapons.json", _set_weapon_damage_type("arcane")),
            [
                "client/data/weapons.json:weapons[0].projectile.damage_type",
                "unknown id arcane; expected one of damage_types",
            ],
        ),
        (
            "invalid weapon pierce count fails",
            _mutate_json("client/data/weapons.json", _set_weapon_stat("pierce_count", -1)),
            [
                "client/data/weapons.json:weapons[0].base_stats.pierce_count",
                "must be >= 0",
            ],
        ),
        (
            "character starting weapon reference must exist",
            _mutate_json("client/data/characters.json", _set_character_starting_weapon("weapon_missing")),
            [
                "client/data/characters.json:characters[0].starting_weapon_id",
                "weapon is not defined in weapons.json: weapon_missing",
            ],
        ),
        (
            "mode weapon reference must exist",
            _mutate_json("client/data/game_modes.json", _set_mode_weapon("weapon_missing")),
            [
                "client/data/game_modes.json:modes[0].resource_pools.weapons[0].id",
                "weapon is not defined in weapons.json: weapon_missing",
            ],
        ),
    ]

    failures: list[str] = []
    for name, mutator, expected_fragments in cases:
        failure = _run_case(name, mutator, expected_fragments)
        if failure:
            failures.append(failure)
        else:
            print(f"[data-loader-schema-test] {name}: passed")

    if failures:
        for failure in failures:
            print(failure)
        return 1

    print("data loader schema tests passed")
    return 0


def _run_case(name: str, mutator: RepoMutator | None, expected_fragments: list[str]) -> str | None:
    with tempfile.TemporaryDirectory(prefix="wasd-data-schema-") as temp_dir:
        temp_root = Path(temp_dir)
        _copy_test_repo(temp_root)
        if mutator is not None:
            mutator(temp_root)

        result = subprocess.run(
            [sys.executable, "tools/validate_data.py"],
            cwd=temp_root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        output = result.stdout

    if not expected_fragments:
        if result.returncode != 0:
            return _format_failure(name, output, "expected validation to pass")
        return None

    if result.returncode == 0:
        return _format_failure(name, output, "expected validation to fail")

    missing = [fragment for fragment in expected_fragments if fragment not in output]
    if missing:
        return _format_failure(name, output, f"missing expected output fragments: {missing}")

    return None


def _copy_test_repo(temp_root: Path) -> None:
    _copy_tree(ROOT / "client" / "data", temp_root / "client" / "data")
    _copy_tree(ROOT / "client" / "locale", temp_root / "client" / "locale")
    _copy_python_tools(temp_root / "tools")
    _copy_file(ROOT / "docs" / "词表与契约.md", temp_root / "docs" / "词表与契约.md")

    mvp_config = ROOT / "MinimumViableProduct" / "client" / "data" / "mvp_config.json"
    if mvp_config.exists():
        _copy_file(mvp_config, temp_root / "MinimumViableProduct" / "client" / "data" / "mvp_config.json")


def _copy_tree(source: Path, target: Path, *, include: list[str] | None = None) -> None:
    if include is None:
        shutil.copytree(source, target)
        return

    target.mkdir(parents=True, exist_ok=True)
    for name in include:
        _copy_file(source / name, target / name)


def _copy_python_tools(target: Path) -> None:
    target.mkdir(parents=True, exist_ok=True)
    for source in (ROOT / "tools").glob("*.py"):
        _copy_file(source, target / source.name)


def _copy_file(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def _mutate_json(relative_path: str, mutator: JsonMutator) -> RepoMutator:
    def mutate_repo(root: Path) -> None:
        path = root / relative_path
        payload = json.loads(path.read_text(encoding="utf-8"))
        mutator(payload)
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")

    return mutate_repo


def _set_character_id(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["characters"][0]["id"] = value

    return mutate


def _set_character_name_key(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["characters"][0]["name_key"] = value

    return mutate


def _set_character_stat(stat: str, value: object) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["characters"][0]["base_stats"][stat] = value

    return mutate


def _clear_characters(payload: dict[str, Any]) -> None:
    payload["characters"] = []


def _set_meta_character_target(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["unlocks"][0]["target_id"] = value

    return mutate


def _set_game_mode_id(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["modes"][0]["id"] = value

    return mutate


def _set_mode_growth_pool(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["modes"][0]["resource_pools"]["growth_pools"][0]["id"] = value

    return mutate


def _set_weapon_damage_type(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["weapons"][0]["projectile"]["damage_type"] = value

    return mutate


def _set_weapon_stat(stat: str, value: object) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["weapons"][0]["base_stats"][stat] = value

    return mutate


def _set_character_starting_weapon(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["characters"][0]["starting_weapon_id"] = value

    return mutate


def _set_mode_weapon(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["modes"][0]["resource_pools"]["weapons"][0]["id"] = value

    return mutate


def _format_failure(name: str, output: str, reason: str) -> str:
    return f"[data-loader-schema-test] {name}: failed; {reason}\n{output.rstrip()}"


if __name__ == "__main__":
    sys.exit(main())
