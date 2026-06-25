#!/usr/bin/env python3
"""Generate contract artifacts from docs/词表与契约.md."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
CONTRACT_DOC = ROOT / "docs" / "词表与契约.md"
CONTRACTS_JSON = ROOT / "client" / "data" / "_contracts.json"
CONTRACTS_DIR = ROOT / "client" / "scripts" / "contracts"


@dataclass(frozen=True)
class ContractSection:
    key: str
    heading: str
    output_file: str | None = None
    class_name: str | None = None
    constant_array: str = "VALUES"
    prefix_values: bool = False


SECTIONS: tuple[ContractSection, ...] = (
    ContractSection("stats", "## 1. 属性 stat", "stats.gd", "Stats"),
    ContractSection("effects", "## 2. 效果原语 effect", "effects.gd", "Effects"),
    ContractSection("events", "## 3. 行为事件 behavior.event", "events.gd", "Events"),
    ContractSection("analytics_events", "## 4. 埋点事件 analytics event", "analytics_events.gd", "AnalyticsEvents"),
    ContractSection("settings_keys", "## 5. 设置 key", "settings_keys.gd", "SettingsKeys"),
    ContractSection("actions", "## 7. 输入动作 action", "actions.gd", "Actions"),
    ContractSection("pool_ids", "## 8. 对象池 id", "pool_ids.gd", "PoolIds"),
    ContractSection("damage_types", "## 9. 伤害类型 damage_type", "damage_types.gd", "DamageTypes"),
    ContractSection("status_effects", "## 9-A. 状态效果 status_effect", "status_effects.gd", "StatusEffects"),
    ContractSection("status_stack_rules", "## 9-B. 状态叠加规则 status_stack_rule", "status_stack_rules.gd", "StatusStackRules"),
    ContractSection("audio_prefixes", "## 10. 音频 id audio_id", "audio_ids.gd", "AudioIds", "PREFIXES", True),
    ContractSection("rng_streams", "## 11. RNG 子流 rng_stream", "rng_streams.gd", "RngStreams"),
    ContractSection("character_ids", "### 12.1 角色 id character_id", "character_ids.gd", "CharacterIds"),
    ContractSection("capabilities", "### 12.2 能力 capability_id", "capabilities.gd", "Capabilities"),
    ContractSection("content_tags", "### 12.3 内容标签 content_tag", "content_tags.gd", "ContentTags"),
    ContractSection("game_modes", "## 12-A. 游戏模式 id game_mode", "game_modes.gd", "GameModes"),
    ContractSection("enemy_ai_actions", "## 12-B. 敌人 AI 动作 enemy_ai_action", "enemy_ai_actions.gd", "EnemyAiActions"),
    ContractSection("skill_ids", "## 12-C. 技能 id skill_id", "skill_ids.gd", "SkillIds"),
    ContractSection("skill_resources", "## 12-D. 技能资源 skill_resource", "skill_resources.gd", "SkillResources"),
    ContractSection("skill_targeting", "## 12-E. 技能目标选择 skill_targeting", "skill_targeting.gd", "SkillTargeting"),
    ContractSection("skill_effects", "## 12-F. 技能效果 skill_effect", "skill_effects.gd", "SkillEffects"),
    ContractSection("ability_tags", "## 12-G. 能力标签 ability_tag", "ability_tags.gd", "AbilityTags"),
    ContractSection("gear_mod_ids", "## 13-A. 装备 Mod id gear_mod_id", "gear_mod_ids.gd", "GearModIds"),
    ContractSection("gear_mod_slots", "## 13-B. 装备 Mod 槽位 gear_mod_slot", "gear_mod_slots.gd", "GearModSlots"),
    ContractSection("gear_mod_rarities", "## 13-C. 装备 Mod 稀有度 gear_mod_rarity", "gear_mod_rarities.gd", "GearModRarities"),
    ContractSection("gear_mod_resources", "## 13-D. 装备 Mod 资源 gear_mod_resource", "gear_mod_resources.gd", "GearModResources"),
    ContractSection("gear_mod_stack_rules", "## 13-E. 装备 Mod 装配规则 gear_mod_stack_rule", "gear_mod_stack_rules.gd", "GearModStackRules"),
    ContractSection("save_kinds", "## 14. 存档种类 save_kind", "save_kinds.gd", "SaveKinds"),
)

LOCALE_PREFIXES_HEADING = "## 6. 本地化 key 命名规范"
RESERVED_CONSTANT_NAMES = {"TRUE", "FALSE", "NULL", "NAN", "INF"}


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate contract JSON and GDScript constants.")
    parser.add_argument("--check", action="store_true", help="Fail if generated artifacts are out of date.")
    args = parser.parse_args()

    try:
        artifacts = build_artifacts()
    except ContractError as exc:
        print(f"[sync-contracts] {exc}")
        return 1

    if args.check:
        return _check_artifacts(artifacts)

    _write_artifacts(artifacts)
    print("sync contracts passed")
    return 0


class ContractError(RuntimeError):
    pass


def extract_contracts() -> dict[str, list[str]]:
    text = _read_contract_doc()
    contracts: dict[str, list[str]] = {}

    for section in SECTIONS:
        section_text = _section_text(text, section.heading)
        values = _extract_first_column_ids(section_text, prefix_values=section.prefix_values)
        contracts[section.key] = values

    contracts["locale_prefixes"] = _extract_locale_prefixes(_section_text(text, LOCALE_PREFIXES_HEADING))
    return contracts


def build_artifacts() -> dict[Path, str]:
    contracts = extract_contracts()
    payload = {
        "schema_version": 1,
        "source": "docs/词表与契约.md",
        "generated_by": "tools/sync_contracts.py",
        "contracts": contracts,
    }

    artifacts: dict[Path, str] = {
        CONTRACTS_JSON: json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
    }

    for section in SECTIONS:
        if section.output_file is None or section.class_name is None:
            continue
        artifacts[CONTRACTS_DIR / section.output_file] = _render_gd_constants(
            section.class_name,
            section.constant_array,
            contracts[section.key],
            prefix_constants=section.prefix_values,
        )

    return artifacts


def _read_contract_doc() -> str:
    if not CONTRACT_DOC.exists():
        raise ContractError("missing docs/词表与契约.md")
    return CONTRACT_DOC.read_text(encoding="utf-8")


def _section_text(text: str, heading: str) -> str:
    start = text.find(heading)
    if start < 0:
        raise ContractError(f"missing heading: {heading}")
    next_heading = re.search(r"\n#{2,3} ", text[start + 1 :])
    if next_heading is None:
        return text[start:]
    return text[start : start + 1 + next_heading.start()]


def _extract_first_column_ids(section_text: str, *, prefix_values: bool = False) -> list[str]:
    values: list[str] = []
    for line in section_text.splitlines():
        stripped = line.strip()
        if not stripped.startswith("|") or set(stripped.replace("|", "").strip()) <= {"-", ":"}:
            continue
        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if not cells or "`" not in cells[0]:
            continue
        for raw in re.findall(r"`([^`]+)`", cells[0]):
            value = _normalize_contract_value(raw, prefix_value=prefix_values)
            if value not in values:
                values.append(value)
    if not values:
        raise ContractError("no contract ids found in section")
    return values


def _extract_locale_prefixes(section_text: str) -> list[str]:
    prefixes: list[str] = []
    for raw in re.findall(r"`([a-z0-9_]+_)`", section_text):
        if raw not in prefixes:
            prefixes.append(raw)
    if not prefixes:
        raise ContractError("no locale prefixes found")
    return prefixes


def _normalize_contract_value(raw: str, *, prefix_value: bool) -> str:
    value = raw.strip()
    if prefix_value and value.endswith("*"):
        value = value[:-1]
    return value


def _render_gd_constants(
    class_name: str,
    array_name: str,
    values: list[str],
    *,
    prefix_constants: bool = False,
) -> str:
    lines = [
        "# This file is generated by tools/sync_contracts.py. Do not edit by hand.",
        f"class_name {class_name}",
        "",
        f"const {array_name}: Array[String] = [",
    ]
    for value in values:
        lines.append(f'\t"{value}",')
    lines.extend(["]", ""])

    for value in values:
        constant_name = _constant_name(value, suffix="PREFIX" if prefix_constants else "")
        lines.append(f'const {constant_name}: String = "{value}"')

    return "\n".join(lines) + "\n"


def _constant_name(value: str, *, suffix: str = "") -> str:
    base = value.rstrip("_").replace(".", "_").replace("/", "_")
    base = re.sub(r"[^A-Za-z0-9]+", "_", base).strip("_").upper()
    if suffix:
        base = f"{base}_{suffix}"
    if base in RESERVED_CONSTANT_NAMES or not base:
        base = f"ID_{base}"
    return base


def _write_artifacts(artifacts: dict[Path, str]) -> None:
    for path, content in artifacts.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8", newline="\n")


def _check_artifacts(artifacts: dict[Path, str]) -> int:
    errors: list[str] = []
    for path, expected in artifacts.items():
        if not path.exists():
            errors.append(f"missing generated artifact: {_rel(path)}")
            continue
        actual = path.read_text(encoding="utf-8")
        if actual != expected:
            errors.append(f"outdated generated artifact: {_rel(path)}")

    if errors:
        for error in errors:
            print(f"[sync-contracts] {error}")
        print("[sync-contracts] run: python tools/sync_contracts.py")
        return 1

    print("sync contracts check passed")
    return 0


def _rel(path: Path) -> str:
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return path.as_posix()


if __name__ == "__main__":
    sys.exit(main())
