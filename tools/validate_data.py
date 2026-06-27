#!/usr/bin/env python3
"""Validate project data, locale CSV, and generated contracts."""

from __future__ import annotations

import csv
import json
import re
import sys
from pathlib import Path
from typing import Any

from sync_contracts import CONTRACTS_JSON, ROOT, extract_contracts


CLIENT_DATA = ROOT / "client" / "data"
LOCALE_CSV = ROOT / "client" / "locale" / "strings.csv"
CHARACTERS_JSON = ROOT / "client" / "data" / "characters.json"
WEAPONS_JSON = ROOT / "client" / "data" / "weapons.json"
ENEMIES_CSV = ROOT / "client" / "data" / "enemies.csv"
ENEMY_AI_PROFILES_JSON = ROOT / "client" / "data" / "enemy_ai_profiles.json"
HAZARDS_CSV = ROOT / "client" / "data" / "hazards.csv"
SPAWN_WAVES_CSV = ROOT / "client" / "data" / "spawn_waves.csv"
RELICS_JSON = ROOT / "client" / "data" / "relics.json"
ACTIVE_ITEMS_JSON = ROOT / "client" / "data" / "active_items.json"
CONSUMABLES_JSON = ROOT / "client" / "data" / "consumables.json"
SKILLS_JSON = ROOT / "client" / "data" / "skills.json"
CREDITS_JSON = ROOT / "client" / "data" / "credits.json"
GROWTH_CSV = ROOT / "client" / "data" / "growth.csv"
GROWTH_POOLS_JSON = ROOT / "client" / "data" / "growth_pools.json"
GAME_MODES_JSON = ROOT / "client" / "data" / "game_modes.json"
MAP_LAYOUTS_JSON = ROOT / "client" / "data" / "map_layouts.json"
WARZONE_DIRECTORS_JSON = ROOT / "client" / "data" / "warzone_directors.json"
GEAR_MODS_JSON = ROOT / "client" / "data" / "gear_mods.json"
GEAR_MOD_DROP_TABLES_CSV = ROOT / "client" / "data" / "gear_mod_drop_tables.csv"
GEAR_MOD_FUSION_COSTS_CSV = ROOT / "client" / "data" / "gear_mod_fusion_costs.csv"
PLACEHOLDER_RE = re.compile(r"\{[a-z0-9_]+\}")
LOCALE_KEY_RE = re.compile(r"^[a-z0-9_]+$")
HTML_COLOR_RE = re.compile(r"^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$")

INT_STATS = {"bullet_count", "pierce_count"}
NON_NEGATIVE_STATS = {
    "damage",
    "damage_invulnerability_duration",
    "health_regen",
    "player_separation_radius",
    "pickup_range",
    "luck",
    "armor",
    "lifesteal_ratio",
}
POSITIVE_STATS = {"max_hp", "move_speed", "fire_rate", "bullet_speed", "bullet_range", "pickup_orb_speed", "crit_mult"}
RATIO_STATS = {"crit_chance", "resist_fire", "resist_poison", "resist_lightning", "lifesteal_ratio"}
WEAPON_STATS = {"damage", "fire_rate", "bullet_speed", "bullet_range", "bullet_count", "pierce_count", "crit_chance", "crit_mult"}
REQUIRED_WEAPON_STATS = {"damage", "fire_rate", "bullet_speed", "bullet_range", "bullet_count"}


class ValidationContext:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.locale_keys: set[str] = set()
        self.contracts = _load_contracts()

    def error(self, path: Path, field: str, message: str) -> None:
        self.errors.append(f"{_rel(path)}:{field}: {message}")


def main() -> int:
    ctx = ValidationContext()

    _validate_contracts_file(ctx)
    _validate_all_json(ctx)
    _validate_locale_csv(ctx)
    _validate_player_json(ctx)
    _validate_weapons(ctx)
    weapon_ids = _collect_weapon_ids(ctx)
    _validate_enemy_ai_profiles(ctx)
    enemy_ai_profile_ids = _collect_enemy_ai_profile_ids(ctx)
    _validate_enemies_csv(ctx, enemy_ai_profile_ids)
    enemy_ids = _collect_enemy_ids(ctx)
    _validate_gear_mods(ctx)
    gear_mod_ids = _collect_gear_mod_ids(ctx)
    gear_mod_rarity_max_ranks = _collect_gear_mod_rarity_max_ranks(ctx)
    _validate_gear_mod_drop_tables(ctx, enemy_ids, gear_mod_ids)
    _validate_gear_mod_fusion_costs(ctx, gear_mod_rarity_max_ranks)
    _validate_hazards_csv(ctx)
    hazard_ids = _collect_hazard_ids(ctx)
    _validate_relics(ctx)
    relic_ids = _collect_relic_ids(ctx)
    _validate_active_items(ctx)
    active_item_ids = _collect_active_item_ids(ctx)
    _validate_consumables(ctx)
    consumable_ids = _collect_consumable_ids(ctx)
    _validate_skills(ctx)
    skill_ids = _collect_skill_ids(ctx)
    _validate_credits(ctx)
    _validate_characters(ctx, weapon_ids, active_item_ids, consumable_ids, skill_ids)
    character_ids = _collect_character_ids(ctx)
    _validate_growth_csv(ctx)
    _validate_growth_pools(ctx)
    _validate_game_modes(ctx, character_ids, weapon_ids, enemy_ids, hazard_ids, relic_ids, active_item_ids, consumable_ids, skill_ids)
    game_mode_ids = _collect_game_mode_ids(ctx)
    _validate_map_layouts(ctx, hazard_ids, game_mode_ids)
    _validate_spawn_waves_csv(ctx, enemy_ids, hazard_ids, game_mode_ids)
    _validate_warzone_directors(ctx, game_mode_ids, _collect_spawn_wave_ids_by_mode(ctx), hazard_ids, _collect_map_layout_ids(ctx), gear_mod_ids)

    if ctx.errors:
        for error in ctx.errors:
            print(f"[validate-data] {error}")
        return 1

    print("data validation passed")
    return 0


def _load_contracts() -> dict[str, list[str]]:
    if CONTRACTS_JSON.exists():
        payload = json.loads(CONTRACTS_JSON.read_text(encoding="utf-8"))
        contracts = payload.get("contracts")
        if isinstance(contracts, dict):
            return {key: list(value) for key, value in contracts.items() if isinstance(value, list)}
    return extract_contracts()


def _validate_contracts_file(ctx: ValidationContext) -> None:
    expected = extract_contracts()
    if not CONTRACTS_JSON.exists():
        ctx.error(CONTRACTS_JSON, "$", "missing generated contracts; run python tools/sync_contracts.py")
        return
    payload = _load_json(CONTRACTS_JSON, ctx)
    if not isinstance(payload, dict):
        return
    if payload.get("schema_version") != 1:
        ctx.error(CONTRACTS_JSON, "schema_version", "must be 1")
    if payload.get("contracts") != expected:
        ctx.error(CONTRACTS_JSON, "contracts", "out of date with docs/词表与契约.md; run python tools/sync_contracts.py")


def _validate_all_json(ctx: ValidationContext) -> None:
    paths = sorted(CLIENT_DATA.glob("*.json"))
    for path in paths:
        _load_json(path, ctx)


def _validate_locale_csv(ctx: ValidationContext) -> None:
    if not LOCALE_CSV.exists():
        ctx.error(LOCALE_CSV, "$", "missing locale CSV")
        return

    required = {"keys", "zh_CN", "en"}
    with LOCALE_CSV.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        fieldnames = reader.fieldnames or []
        missing = required.difference(fieldnames)
        if missing:
            ctx.error(LOCALE_CSV, "header", f"missing required columns {sorted(missing)}")
            return

        locale_columns = [column for column in fieldnames if column != "keys"]
        for line_number, row in enumerate(reader, start=2):
            key = row.get("keys", "")
            if not key:
                ctx.error(LOCALE_CSV, f"line {line_number}", "empty key")
                continue
            if key in ctx.locale_keys:
                ctx.error(LOCALE_CSV, f"line {line_number}", f"duplicate key {key}")
            ctx.locale_keys.add(key)
            if not LOCALE_KEY_RE.match(key):
                ctx.error(LOCALE_CSV, f"line {line_number}", f"invalid key format {key}")
            if not any(key.startswith(prefix) for prefix in ctx.contracts["locale_prefixes"]):
                ctx.error(LOCALE_CSV, f"line {line_number}", f"key prefix is not registered: {key}")

            placeholder_sets = []
            for locale in locale_columns:
                text = row.get(locale, "")
                if locale in required and not text:
                    ctx.error(LOCALE_CSV, f"line {line_number}", f"missing {locale} translation for {key}")
                placeholder_sets.append((locale, set(PLACEHOLDER_RE.findall(text))))
            if placeholder_sets:
                baseline = placeholder_sets[0][1]
                for locale, placeholders in placeholder_sets[1:]:
                    if placeholders != baseline:
                        ctx.error(LOCALE_CSV, f"line {line_number}", f"placeholder mismatch for {key}: {locale}")


def _validate_player_json(ctx: ValidationContext) -> None:
    path = CLIENT_DATA / "player.json"
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=1)
    base_stats = data.get("base_stats")
    if not isinstance(base_stats, dict) or not base_stats:
        ctx.error(path, "base_stats", "must be a non-empty object")
        return
    for stat, value in base_stats.items():
        _validate_stat_value(ctx, path, f"base_stats.{stat}", stat, value)


def _validate_characters(ctx: ValidationContext, weapon_ids: set[str], active_item_ids: set[str], consumable_ids: set[str], skill_ids: set[str]) -> None:
    path = CHARACTERS_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=1)
    characters = _require_list(ctx, path, "characters", data.get("characters"))
    if not characters:
        ctx.error(path, "characters", "must be a non-empty array")
    seen: set[str] = set()
    for index, character in enumerate(characters):
        field = f"characters[{index}]"
        if not isinstance(character, dict):
            ctx.error(path, field, "must be an object")
            continue
        character_id = _require_registered(ctx, path, f"{field}.id", character.get("id"), "character_ids")
        if character_id:
            if character_id in seen:
                ctx.error(path, f"{field}.id", f"duplicate character id {character_id}")
            seen.add(character_id)
        _require_locale_key(ctx, path, f"{field}.name_key", character.get("name_key"))
        _require_locale_key(ctx, path, f"{field}.desc_key", character.get("desc_key"))
        _require_bool(ctx, path, f"{field}.default_unlocked", character.get("default_unlocked"))
        tags = _validate_registered_string_list(ctx, path, f"{field}.tags", character.get("tags"), "content_tags", allow_empty=False)
        if "tag_character" not in tags:
            ctx.error(path, f"{field}.tags", "must include tag_character")
        _validate_registered_string_list(ctx, path, f"{field}.capabilities", character.get("capabilities", []), "capabilities", allow_empty=True)
        _require_non_empty_string(ctx, path, f"{field}.control_profile", character.get("control_profile"))
        _validate_character_starting_loadout(ctx, path, f"{field}.starting_loadout", character.get("starting_loadout"), weapon_ids, active_item_ids, consumable_ids, skill_ids)
        _validate_character_skill_resources(ctx, path, f"{field}.skill_resources", character.get("skill_resources", []))
        base_stats = character.get("base_stats")
        if not isinstance(base_stats, dict) or not base_stats:
            ctx.error(path, f"{field}.base_stats", "must be a non-empty object")
            continue
        for stat, value in base_stats.items():
            _validate_stat_value(ctx, path, f"{field}.base_stats.{stat}", stat, value)


def _validate_character_starting_loadout(ctx: ValidationContext, path: Path, field: str, data: Any, weapon_ids: set[str], active_item_ids: set[str], consumable_ids: set[str], skill_ids: set[str]) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    weapon_id = _require_non_empty_string(ctx, path, f"{field}.weapon_id", data.get("weapon_id"))
    if weapon_id and weapon_id not in weapon_ids:
        ctx.error(path, f"{field}.weapon_id", f"weapon is not defined in weapons.json: {weapon_id}")
    active_item_id = _require_non_empty_string(ctx, path, f"{field}.active_item_id", data.get("active_item_id"))
    if active_item_id and active_item_id not in active_item_ids:
        ctx.error(path, f"{field}.active_item_id", f"active item is not defined in active_items.json: {active_item_id}")
    starting_consumables = _require_list(ctx, path, f"{field}.consumable_ids", data.get("consumable_ids"))
    seen: set[str] = set()
    for index, consumable in enumerate(starting_consumables):
        item_field = f"{field}.consumable_ids[{index}]"
        consumable_id = _require_non_empty_string(ctx, path, item_field, consumable)
        if not consumable_id:
            continue
        if consumable_id in seen:
            ctx.error(path, item_field, f"duplicate consumable id {consumable_id}")
        seen.add(consumable_id)
        if consumable_id not in consumable_ids:
            ctx.error(path, item_field, f"consumable is not defined in consumables.json: {consumable_id}")
    starting_skills = _require_list(ctx, path, f"{field}.skill_ids", data.get("skill_ids", []))
    seen_skills: set[str] = set()
    for index, skill in enumerate(starting_skills):
        item_field = f"{field}.skill_ids[{index}]"
        skill_id = _require_registered(ctx, path, item_field, skill, "skill_ids")
        if not skill_id:
            continue
        if skill_id in seen_skills:
            ctx.error(path, item_field, f"duplicate skill id {skill_id}")
        seen_skills.add(skill_id)
        if skill_id not in skill_ids:
            ctx.error(path, item_field, f"skill is not defined in skills.json: {skill_id}")


def _validate_character_skill_resources(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    resources = _require_list(ctx, path, field, data)
    seen: set[str] = set()
    for index, resource in enumerate(resources):
        item_field = f"{field}[{index}]"
        if not isinstance(resource, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        resource_id = _require_registered(ctx, path, f"{item_field}.id", resource.get("id"), "skill_resources")
        if resource_id:
            if resource_id in seen:
                ctx.error(path, f"{item_field}.id", f"duplicate resource id {resource_id}")
            seen.add(resource_id)
        max_value = _require_number(ctx, path, f"{item_field}.max", resource.get("max"), minimum=0, exclusive_minimum=True)
        start_value = _require_number(ctx, path, f"{item_field}.start", resource.get("start"), minimum=0)
        _require_number(ctx, path, f"{item_field}.regen_per_second", resource.get("regen_per_second"), minimum=0)
        if isinstance(max_value, float) and isinstance(start_value, float) and start_value > max_value:
            ctx.error(path, f"{item_field}.start", "must be <= max")


def _validate_weapons(ctx: ValidationContext) -> None:
    path = WEAPONS_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=1)
    weapons = _require_list(ctx, path, "weapons", data.get("weapons"))
    if not weapons:
        ctx.error(path, "weapons", "must be a non-empty array")
    seen: set[str] = set()
    for index, weapon in enumerate(weapons):
        field = f"weapons[{index}]"
        if not isinstance(weapon, dict):
            ctx.error(path, field, "must be an object")
            continue
        weapon_id = _require_non_empty_string(ctx, path, f"{field}.id", weapon.get("id"))
        if weapon_id:
            if weapon_id in seen:
                ctx.error(path, f"{field}.id", f"duplicate weapon id {weapon_id}")
            seen.add(weapon_id)
        _require_locale_key(ctx, path, f"{field}.name_key", weapon.get("name_key"))
        _require_locale_key(ctx, path, f"{field}.desc_key", weapon.get("desc_key"))
        _require_bool(ctx, path, f"{field}.default_unlocked", weapon.get("default_unlocked"))
        _require_non_empty_string(ctx, path, f"{field}.fire_mode", weapon.get("fire_mode"))
        if "fire_audio_id" in weapon:
            _require_audio_id(ctx, path, f"{field}.fire_audio_id", weapon.get("fire_audio_id"))
        _validate_weapon_stats(ctx, path, f"{field}.base_stats", weapon.get("base_stats"))
        _validate_weapon_projectile(ctx, path, f"{field}.projectile", weapon.get("projectile"))


def _validate_weapon_stats(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    if not isinstance(data, dict) or not data:
        ctx.error(path, field, "must be a non-empty object")
        return
    for stat in sorted(REQUIRED_WEAPON_STATS):
        if stat not in data:
            ctx.error(path, f"{field}.{stat}", "is required")
    for stat, value in data.items():
        if stat not in WEAPON_STATS:
            ctx.error(path, f"{field}.{stat}", "unsupported weapon stat")
            continue
        if stat == "pierce_count":
            _require_int(ctx, path, f"{field}.{stat}", value, minimum=0)
        else:
            _validate_stat_value(ctx, path, f"{field}.{stat}", stat, value)


def _validate_weapon_projectile(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    _require_registered(ctx, path, f"{field}.pool_id", data.get("pool_id"), "pool_ids")
    _require_registered(ctx, path, f"{field}.damage_type", data.get("damage_type"), "damage_types")
    _require_number(ctx, path, f"{field}.hit_radius", data.get("hit_radius"), minimum=0, exclusive_minimum=True)
    _require_number(ctx, path, f"{field}.muzzle_distance", data.get("muzzle_distance"), minimum=0, exclusive_minimum=True)
    _require_number(ctx, path, f"{field}.lifetime", data.get("lifetime"), minimum=0, exclusive_minimum=True)


def _validate_enemy_ai_profiles(ctx: ValidationContext) -> None:
    path = ENEMY_AI_PROFILES_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=1)
    profiles = _require_list(ctx, path, "profiles", data.get("profiles"))
    if not profiles:
        ctx.error(path, "profiles", "must be a non-empty array")
    seen: set[str] = set()
    for index, profile in enumerate(profiles):
        field = f"profiles[{index}]"
        if not isinstance(profile, dict):
            ctx.error(path, field, "must be an object")
            continue
        profile_id = _require_non_empty_string(ctx, path, f"{field}.id", profile.get("id"))
        if profile_id:
            if profile_id in seen:
                ctx.error(path, f"{field}.id", f"duplicate profile id {profile_id}")
            seen.add(profile_id)
        _require_number(ctx, path, f"{field}.sense_radius", profile.get("sense_radius"), minimum=0, exclusive_minimum=True)
        _require_number(ctx, path, f"{field}.decision_interval", profile.get("decision_interval"), minimum=0, exclusive_minimum=True)
        _require_number(ctx, path, f"{field}.contact_interval", profile.get("contact_interval"), minimum=0)
        _validate_enemy_ai_targeting(ctx, path, f"{field}.targeting", profile.get("targeting"))
        _validate_enemy_ai_movement(ctx, path, f"{field}.movement", profile.get("movement"))
        _validate_enemy_ai_actions(ctx, path, f"{field}.actions", profile.get("actions"))


def _validate_enemy_ai_targeting(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    _require_number(ctx, path, f"{field}.player_weight", data.get("player_weight"), minimum=0)
    _validate_enemy_ai_tag_weights(ctx, path, f"{field}.hunt_tags", data.get("hunt_tags"))
    _validate_enemy_ai_tag_weights(ctx, path, f"{field}.flee_tags", data.get("flee_tags"))
    _require_number(ctx, path, f"{field}.territory_radius", data.get("territory_radius"), minimum=0)
    _require_number(ctx, path, f"{field}.territory_weight", data.get("territory_weight"), minimum=0)


def _validate_enemy_ai_tag_weights(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    entries = _require_list(ctx, path, field, data)
    seen: set[str] = set()
    for index, entry in enumerate(entries):
        item_field = f"{field}[{index}]"
        if not isinstance(entry, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        tag = _require_registered(ctx, path, f"{item_field}.tag", entry.get("tag"), "content_tags")
        if tag:
            if tag in seen:
                ctx.error(path, f"{item_field}.tag", f"duplicate tag {tag}")
            seen.add(tag)
        _require_number(ctx, path, f"{item_field}.weight", entry.get("weight"), minimum=0)


def _validate_enemy_ai_movement(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    _require_number(ctx, path, f"{field}.orbit_radius", data.get("orbit_radius"), minimum=0)
    _require_number(ctx, path, f"{field}.flee_distance", data.get("flee_distance"), minimum=0, exclusive_minimum=True)
    _require_number(ctx, path, f"{field}.charge_range", data.get("charge_range"), minimum=0)
    _require_number(ctx, path, f"{field}.charge_windup", data.get("charge_windup"), minimum=0)
    _require_number(ctx, path, f"{field}.charge_duration", data.get("charge_duration"), minimum=0)
    _require_number(ctx, path, f"{field}.charge_cooldown", data.get("charge_cooldown"), minimum=0)
    _require_number(ctx, path, f"{field}.charge_speed_scale", data.get("charge_speed_scale"), minimum=0, exclusive_minimum=True)


def _validate_enemy_ai_actions(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    actions = _require_list(ctx, path, field, data)
    if not actions:
        ctx.error(path, field, "must be a non-empty array")
    seen: set[str] = set()
    for index, action in enumerate(actions):
        item_field = f"{field}[{index}]"
        if not isinstance(action, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        action_id = _require_registered(ctx, path, f"{item_field}.id", action.get("id"), "enemy_ai_actions")
        if action_id:
            if action_id in seen:
                ctx.error(path, f"{item_field}.id", f"duplicate action id {action_id}")
            seen.add(action_id)
        _require_number(ctx, path, f"{item_field}.base_score", action.get("base_score"), minimum=0)
        _require_number(ctx, path, f"{item_field}.speed_scale", action.get("speed_scale"), minimum=0, exclusive_minimum=True)


def _validate_enemies_csv(ctx: ValidationContext, enemy_ai_profile_ids: set[str]) -> None:
    path = ENEMIES_CSV
    if not path.exists():
        ctx.error(path, "$", "missing enemies CSV")
        return

    required = {
        "id",
        "name_key",
        "tags",
        "pool_id",
        "ai_profile_id",
        "max_hp",
        "move_speed",
        "contact_damage",
        "contact_damage_type",
        "exp_reward",
        "hit_radius",
        "separation_radius",
        "visual_color",
    }
    seen: set[str] = set()
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        fieldnames = reader.fieldnames or []
        missing = required.difference(fieldnames)
        if missing:
            ctx.error(path, "header", f"missing required columns {sorted(missing)}")
            return
        row_count = 0
        for line_number, row in enumerate(reader, start=2):
            row_count += 1
            field = f"line {line_number}"
            enemy_id = _require_non_empty_string(ctx, path, f"{field}.id", row.get("id"))
            if enemy_id:
                if enemy_id in seen:
                    ctx.error(path, f"{field}.id", f"duplicate enemy id {enemy_id}")
                seen.add(enemy_id)
            _require_locale_key(ctx, path, f"{field}.name_key", row.get("name_key"))
            tags = _validate_registered_string_list(ctx, path, f"{field}.tags", _parse_pipe_list(row.get("tags")), "content_tags", allow_empty=False)
            if "tag_enemy" not in tags:
                ctx.error(path, f"{field}.tags", "must include tag_enemy")
            _require_registered(ctx, path, f"{field}.pool_id", row.get("pool_id"), "pool_ids")
            ai_profile_id = _require_non_empty_string(ctx, path, f"{field}.ai_profile_id", row.get("ai_profile_id"))
            if ai_profile_id and ai_profile_id not in enemy_ai_profile_ids:
                ctx.error(path, f"{field}.ai_profile_id", f"profile is not defined in enemy_ai_profiles.json: {ai_profile_id}")
            _parse_int(ctx, path, f"{field}.max_hp", row.get("max_hp"), minimum=1)
            _parse_float(ctx, path, f"{field}.move_speed", row.get("move_speed"), minimum=0, exclusive_minimum=True)
            _parse_int(ctx, path, f"{field}.contact_damage", row.get("contact_damage"), minimum=0)
            _require_registered(ctx, path, f"{field}.contact_damage_type", row.get("contact_damage_type"), "damage_types")
            _parse_int(ctx, path, f"{field}.exp_reward", row.get("exp_reward"), minimum=0)
            _parse_float(ctx, path, f"{field}.hit_radius", row.get("hit_radius"), minimum=0, exclusive_minimum=True)
            _parse_float(ctx, path, f"{field}.separation_radius", row.get("separation_radius"), minimum=0)
            _require_html_color(ctx, path, f"{field}.visual_color", row.get("visual_color"))
        if row_count == 0:
            ctx.error(path, "rows", "must contain at least one enemy")


def _validate_hazards_csv(ctx: ValidationContext) -> None:
    path = HAZARDS_CSV
    if not path.exists():
        ctx.error(path, "$", "missing hazards CSV")
        return

    required = {
        "id",
        "name_key",
        "tags",
        "pool_id",
        "damage",
        "damage_type",
        "trigger_interval",
        "radius_tiles",
        "duration",
    }
    seen: set[str] = set()
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        fieldnames = reader.fieldnames or []
        missing = required.difference(fieldnames)
        if missing:
            ctx.error(path, "header", f"missing required columns {sorted(missing)}")
            return
        row_count = 0
        for line_number, row in enumerate(reader, start=2):
            row_count += 1
            field = f"line {line_number}"
            hazard_id = _require_non_empty_string(ctx, path, f"{field}.id", row.get("id"))
            if hazard_id:
                if hazard_id in seen:
                    ctx.error(path, f"{field}.id", f"duplicate hazard id {hazard_id}")
                seen.add(hazard_id)
            _require_locale_key(ctx, path, f"{field}.name_key", row.get("name_key"))
            tags = _validate_registered_string_list(ctx, path, f"{field}.tags", _parse_pipe_list(row.get("tags")), "content_tags", allow_empty=False)
            if "tag_hazard" not in tags:
                ctx.error(path, f"{field}.tags", "must include tag_hazard")
            _require_registered(ctx, path, f"{field}.pool_id", row.get("pool_id"), "pool_ids")
            _parse_int(ctx, path, f"{field}.damage", row.get("damage"), minimum=0)
            _require_registered(ctx, path, f"{field}.damage_type", row.get("damage_type"), "damage_types")
            _parse_float(ctx, path, f"{field}.trigger_interval", row.get("trigger_interval"), minimum=0, exclusive_minimum=True)
            _parse_int(ctx, path, f"{field}.radius_tiles", row.get("radius_tiles"), minimum=1)
            _parse_float(ctx, path, f"{field}.duration", row.get("duration"), minimum=0)
        if row_count == 0:
            ctx.error(path, "rows", "must contain at least one hazard")


def _validate_spawn_waves_csv(ctx: ValidationContext, enemy_ids: set[str], hazard_ids: set[str], game_mode_ids: set[str]) -> None:
    path = SPAWN_WAVES_CSV
    if not path.exists():
        ctx.error(path, "$", "missing spawn waves CSV")
        return

    required = {
        "id",
        "mode_id",
        "wave_index",
        "start_time",
        "end_time",
        "enemy_id",
        "enemy_weight",
        "spawn_interval",
        "max_alive",
        "spawn_budget",
        "hazard_id",
        "hazard_weight",
    }
    seen_ids: set[str] = set()
    seen_mode_waves: set[tuple[str, int]] = set()
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        fieldnames = reader.fieldnames or []
        missing = required.difference(fieldnames)
        if missing:
            ctx.error(path, "header", f"missing required columns {sorted(missing)}")
            return
        row_count = 0
        for line_number, row in enumerate(reader, start=2):
            row_count += 1
            field = f"line {line_number}"
            wave_id = _require_non_empty_string(ctx, path, f"{field}.id", row.get("id"))
            if wave_id:
                if wave_id in seen_ids:
                    ctx.error(path, f"{field}.id", f"duplicate wave id {wave_id}")
                seen_ids.add(wave_id)
            mode_id = _require_registered(ctx, path, f"{field}.mode_id", row.get("mode_id"), "game_modes")
            if mode_id and mode_id not in game_mode_ids:
                ctx.error(path, f"{field}.mode_id", f"mode is not defined in game_modes.json: {mode_id}")
            wave_index = _parse_int(ctx, path, f"{field}.wave_index", row.get("wave_index"), minimum=1)
            if mode_id and isinstance(wave_index, int):
                mode_wave = (mode_id, wave_index)
                if mode_wave in seen_mode_waves:
                    ctx.error(path, f"{field}.wave_index", f"duplicate wave_index {wave_index} for mode {mode_id}")
                seen_mode_waves.add(mode_wave)
            start_time = _parse_float(ctx, path, f"{field}.start_time", row.get("start_time"), minimum=0)
            end_time = _parse_float(ctx, path, f"{field}.end_time", row.get("end_time"), minimum=0, exclusive_minimum=True)
            if isinstance(start_time, float) and isinstance(end_time, float) and end_time <= start_time:
                ctx.error(path, f"{field}.end_time", "must be greater than start_time")
            enemy_id = _require_non_empty_string(ctx, path, f"{field}.enemy_id", row.get("enemy_id"))
            if enemy_id and enemy_id not in enemy_ids:
                ctx.error(path, f"{field}.enemy_id", f"enemy is not defined in enemies.csv: {enemy_id}")
            _parse_int(ctx, path, f"{field}.enemy_weight", row.get("enemy_weight"), minimum=1)
            _parse_float(ctx, path, f"{field}.spawn_interval", row.get("spawn_interval"), minimum=0, exclusive_minimum=True)
            _parse_int(ctx, path, f"{field}.max_alive", row.get("max_alive"), minimum=1)
            _parse_int(ctx, path, f"{field}.spawn_budget", row.get("spawn_budget"), minimum=0)
            hazard_id = row.get("hazard_id") or ""
            if hazard_id and hazard_id not in hazard_ids:
                ctx.error(path, f"{field}.hazard_id", f"hazard is not defined in hazards.csv: {hazard_id}")
            hazard_weight = _parse_int(ctx, path, f"{field}.hazard_weight", row.get("hazard_weight"), minimum=0)
            if not hazard_id and isinstance(hazard_weight, int) and hazard_weight > 0:
                ctx.error(path, f"{field}.hazard_id", "must be non-empty when hazard_weight > 0")
        if row_count == 0:
            ctx.error(path, "rows", "must contain at least one spawn wave")


def _validate_relics(ctx: ValidationContext) -> None:
    path = RELICS_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=1)
    relics = _require_list(ctx, path, "relics", data.get("relics"))
    if not relics:
        ctx.error(path, "relics", "must be a non-empty array")
    seen: set[str] = set()
    for index, relic in enumerate(relics):
        field = f"relics[{index}]"
        if not isinstance(relic, dict):
            ctx.error(path, field, "must be an object")
            continue
        relic_id = _require_non_empty_string(ctx, path, f"{field}.id", relic.get("id"))
        if relic_id:
            if relic_id in seen:
                ctx.error(path, f"{field}.id", f"duplicate relic id {relic_id}")
            seen.add(relic_id)
        _require_locale_key(ctx, path, f"{field}.name_key", relic.get("name_key"))
        _require_locale_key(ctx, path, f"{field}.desc_key", relic.get("desc_key"))
        _require_bool(ctx, path, f"{field}.default_unlocked", relic.get("default_unlocked"))
        tags = _validate_registered_string_list(ctx, path, f"{field}.tags", relic.get("tags"), "content_tags", allow_empty=False)
        if "tag_relic" not in tags:
            ctx.error(path, f"{field}.tags", "must include tag_relic")
        modifiers = _require_list(ctx, path, f"{field}.modifiers", relic.get("modifiers"))
        behaviors = _require_list(ctx, path, f"{field}.behaviors", relic.get("behaviors"))
        _validate_modifiers(ctx, path, f"{field}.modifiers", modifiers, require_value_per_level=False)
        _validate_behaviors(ctx, path, f"{field}.behaviors", behaviors)
        if not modifiers and not behaviors:
            ctx.error(path, field, "must contain at least one modifier or behavior")


def _validate_active_items(ctx: ValidationContext) -> None:
    path = ACTIVE_ITEMS_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=1)
    active_items = _require_list(ctx, path, "active_items", data.get("active_items"))
    if not active_items:
        ctx.error(path, "active_items", "must be a non-empty array")
    seen: set[str] = set()
    for index, active_item in enumerate(active_items):
        field = f"active_items[{index}]"
        if not isinstance(active_item, dict):
            ctx.error(path, field, "must be an object")
            continue
        active_item_id = _require_non_empty_string(ctx, path, f"{field}.id", active_item.get("id"))
        if active_item_id:
            if active_item_id in seen:
                ctx.error(path, f"{field}.id", f"duplicate active item id {active_item_id}")
            seen.add(active_item_id)
        _require_locale_key(ctx, path, f"{field}.name_key", active_item.get("name_key"))
        _require_locale_key(ctx, path, f"{field}.desc_key", active_item.get("desc_key"))
        _require_bool(ctx, path, f"{field}.default_unlocked", active_item.get("default_unlocked"))
        tags = _validate_registered_string_list(ctx, path, f"{field}.tags", active_item.get("tags"), "content_tags", allow_empty=False)
        if "tag_active_item" not in tags:
            ctx.error(path, f"{field}.tags", "must include tag_active_item")
        _validate_active_item_charge(ctx, path, f"{field}.charge", active_item.get("charge"))
        _validate_active_item_use_effects(ctx, path, f"{field}.use_effects", active_item.get("use_effects"))


def _validate_active_item_charge(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    mode = _require_non_empty_string(ctx, path, f"{field}.mode", data.get("mode"))
    if mode and mode != "cooldown":
        ctx.error(path, f"{field}.mode", "must be cooldown")
    _require_number(ctx, path, f"{field}.cooldown", data.get("cooldown"), minimum=0, exclusive_minimum=True)
    max_charges = _require_int(ctx, path, f"{field}.max_charges", data.get("max_charges"), minimum=1)
    start_charges = _require_int(ctx, path, f"{field}.start_charges", data.get("start_charges"), minimum=0)
    if isinstance(max_charges, int) and isinstance(start_charges, int) and start_charges > max_charges:
        ctx.error(path, f"{field}.start_charges", "must be <= max_charges")


def _validate_active_item_use_effects(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    effects = _require_list(ctx, path, field, data)
    if not effects:
        ctx.error(path, field, "must be a non-empty array")
    for index, effect in enumerate(effects):
        item_field = f"{field}[{index}]"
        if not isinstance(effect, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        _require_registered(ctx, path, f"{item_field}.effect", effect.get("effect"), "effects")
        if not isinstance(effect.get("params"), dict):
            ctx.error(path, f"{item_field}.params", "must be an object")


def _validate_skills(ctx: ValidationContext) -> None:
    path = SKILLS_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=1)
    skills = _require_list(ctx, path, "skills", data.get("skills"))
    if not skills:
        ctx.error(path, "skills", "must be a non-empty array")
    seen: set[str] = set()
    for index, skill in enumerate(skills):
        field = f"skills[{index}]"
        if not isinstance(skill, dict):
            ctx.error(path, field, "must be an object")
            continue
        skill_id = _require_registered(ctx, path, f"{field}.id", skill.get("id"), "skill_ids")
        if skill_id:
            if skill_id in seen:
                ctx.error(path, f"{field}.id", f"duplicate skill id {skill_id}")
            seen.add(skill_id)
        _require_locale_key(ctx, path, f"{field}.name_key", skill.get("name_key"))
        _require_locale_key(ctx, path, f"{field}.desc_key", skill.get("desc_key"))
        _require_bool(ctx, path, f"{field}.default_unlocked", skill.get("default_unlocked"))
        tags = _validate_registered_string_list(ctx, path, f"{field}.tags", skill.get("tags"), "content_tags", allow_empty=False)
        if "tag_skill" not in tags:
            ctx.error(path, f"{field}.tags", "must include tag_skill")
        _validate_registered_string_list(ctx, path, f"{field}.ability_tags", skill.get("ability_tags"), "ability_tags", allow_empty=False)
        _validate_skill_activation(ctx, path, f"{field}.activation", skill.get("activation"))
        _require_number(ctx, path, f"{field}.cooldown", skill.get("cooldown"), minimum=0)
        _validate_skill_costs(ctx, path, f"{field}.costs", skill.get("costs"))
        _validate_skill_targeting(ctx, path, f"{field}.targeting", skill.get("targeting"))
        _validate_skill_effects(ctx, path, f"{field}.effects", skill.get("effects"))


def _validate_skill_activation(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    _validate_registered_string_list(ctx, path, f"{field}.required_tags", data.get("required_tags"), "ability_tags", allow_empty=True)
    _validate_registered_string_list(ctx, path, f"{field}.blocked_tags", data.get("blocked_tags"), "ability_tags", allow_empty=True)
    _validate_registered_string_list(ctx, path, f"{field}.granted_tags", data.get("granted_tags"), "ability_tags", allow_empty=True)


def _validate_skill_costs(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    costs = _require_list(ctx, path, field, data)
    seen: set[str] = set()
    for index, cost in enumerate(costs):
        item_field = f"{field}[{index}]"
        if not isinstance(cost, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        resource_id = _require_registered(ctx, path, f"{item_field}.resource", cost.get("resource"), "skill_resources")
        if resource_id:
            if resource_id in seen:
                ctx.error(path, f"{item_field}.resource", f"duplicate resource id {resource_id}")
            seen.add(resource_id)
        _require_number(ctx, path, f"{item_field}.amount", cost.get("amount"), minimum=0)


def _validate_skill_targeting(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    targeting_type = _require_registered(ctx, path, f"{field}.type", data.get("type"), "skill_targeting")
    if targeting_type == "aoe_enemies_around_caster":
        _require_number(ctx, path, f"{field}.radius", data.get("radius"), minimum=0, exclusive_minimum=True)
    if "max_targets" in data:
        _require_int(ctx, path, f"{field}.max_targets", data.get("max_targets"), minimum=0)


def _validate_skill_effects(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    effects = _require_list(ctx, path, field, data)
    if not effects:
        ctx.error(path, field, "must be a non-empty array")
    for index, effect in enumerate(effects):
        item_field = f"{field}[{index}]"
        if not isinstance(effect, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        effect_id = _require_registered(ctx, path, f"{item_field}.effect", effect.get("effect"), "skill_effects")
        params = effect.get("params")
        if not isinstance(params, dict):
            ctx.error(path, f"{item_field}.params", "must be an object")
            continue
        if effect_id == "skill_effect_damage":
            _require_number(ctx, path, f"{item_field}.params.amount", params.get("amount"), minimum=0, exclusive_minimum=True)
            _require_registered(ctx, path, f"{item_field}.params.damage_type", params.get("damage_type"), "damage_types")
        if effect_id == "skill_effect_apply_status":
            _require_registered(ctx, path, f"{item_field}.params.status", params.get("status"), "status_effects")
            _require_number(ctx, path, f"{item_field}.params.duration", params.get("duration"), minimum=0, exclusive_minimum=True)
            _require_registered(ctx, path, f"{item_field}.params.stack_rule", params.get("stack_rule"), "status_stack_rules")
            _validate_registered_string_list(ctx, path, f"{item_field}.params.granted_ability_tags", params.get("granted_ability_tags"), "ability_tags", allow_empty=True)
            if "magnitude" in params:
                _require_number(ctx, path, f"{item_field}.params.magnitude", params.get("magnitude"))
            if "tick_interval" in params:
                _require_number(ctx, path, f"{item_field}.params.tick_interval", params.get("tick_interval"), minimum=0)
            if "damage_type" in params:
                _require_registered(ctx, path, f"{item_field}.params.damage_type", params.get("damage_type"), "damage_types")
            elif _status_params_has_damage_tick(params):
                ctx.error(path, f"{item_field}.params.damage_type", "is required when magnitude and tick_interval are positive")
        if effect_id == "skill_effect_weapon_modifiers":
            _require_number(ctx, path, f"{item_field}.params.duration", params.get("duration"), minimum=0, exclusive_minimum=True)
            _validate_modifiers(ctx, path, f"{item_field}.params.modifiers", params.get("modifiers"), require_value_per_level=False)


def _validate_gear_mods(ctx: ValidationContext) -> None:
    path = GEAR_MODS_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=1)
    mods = _require_list(ctx, path, "mods", data.get("mods"))
    if not mods:
        ctx.error(path, "mods", "must be a non-empty array")
    seen: set[str] = set()
    for index, mod in enumerate(mods):
        field = f"mods[{index}]"
        if not isinstance(mod, dict):
            ctx.error(path, field, "must be an object")
            continue
        mod_id = _require_registered(ctx, path, f"{field}.id", mod.get("id"), "gear_mod_ids")
        if mod_id:
            if mod_id in seen:
                ctx.error(path, f"{field}.id", f"duplicate gear mod id {mod_id}")
            seen.add(mod_id)
        _require_locale_key(ctx, path, f"{field}.name_key", mod.get("name_key"))
        _require_locale_key(ctx, path, f"{field}.desc_key", mod.get("desc_key"))
        _require_registered(ctx, path, f"{field}.slot", mod.get("slot"), "gear_mod_slots")
        _require_registered(ctx, path, f"{field}.rarity", mod.get("rarity"), "gear_mod_rarities")
        _require_int(ctx, path, f"{field}.max_rank", mod.get("max_rank"), minimum=0)
        _require_int(ctx, path, f"{field}.base_drain", mod.get("base_drain"), minimum=0)
        _require_int(ctx, path, f"{field}.drain_per_rank", mod.get("drain_per_rank"), minimum=0)
        _validate_gear_mod_rank_modifiers(ctx, path, f"{field}.rank_modifiers", mod.get("rank_modifiers"))
        _require_registered(ctx, path, f"{field}.stack_rule", mod.get("stack_rule"), "gear_mod_stack_rules")
        _validate_gear_mod_dismantle(ctx, path, f"{field}.dismantle", mod.get("dismantle"))


def _validate_gear_mod_rank_modifiers(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    modifiers = _require_list(ctx, path, field, data)
    if not modifiers:
        ctx.error(path, field, "must be a non-empty array")
    for index, modifier in enumerate(modifiers):
        item_field = f"{field}[{index}]"
        if not isinstance(modifier, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        _require_registered(ctx, path, f"{item_field}.stat", modifier.get("stat"), "stats")
        if modifier.get("type") not in {"add", "mult"}:
            ctx.error(path, f"{item_field}.type", "must be add or mult")
        _require_number(ctx, path, f"{item_field}.base_value", modifier.get("base_value"))
        _require_number(ctx, path, f"{item_field}.value_per_rank", modifier.get("value_per_rank"))


def _validate_gear_mod_dismantle(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    _require_registered(ctx, path, f"{field}.resource_id", data.get("resource_id"), "gear_mod_resources")
    _require_int(ctx, path, f"{field}.amount", data.get("amount"), minimum=0)


def _validate_gear_mod_drop_tables(ctx: ValidationContext, enemy_ids: set[str], gear_mod_ids: set[str]) -> None:
    path = GEAR_MOD_DROP_TABLES_CSV
    if not path.exists():
        ctx.error(path, "$", "missing gear mod drop table CSV")
        return

    required = {"source_enemy_id", "mod_id", "drop_chance", "min_enemy_level", "max_enemy_level"}
    seen: set[tuple[str, str, int, int]] = set()
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        fieldnames = reader.fieldnames or []
        missing = required.difference(fieldnames)
        if missing:
            ctx.error(path, "header", f"missing required columns {sorted(missing)}")
            return
        row_count = 0
        for line_number, row in enumerate(reader, start=2):
            row_count += 1
            field = f"line {line_number}"
            source_enemy_id = _require_non_empty_string(ctx, path, f"{field}.source_enemy_id", row.get("source_enemy_id"))
            if source_enemy_id and source_enemy_id not in enemy_ids:
                ctx.error(path, f"{field}.source_enemy_id", f"enemy is not defined in enemies.csv: {source_enemy_id}")
            mod_id = _require_non_empty_string(ctx, path, f"{field}.mod_id", row.get("mod_id"))
            if mod_id and mod_id not in gear_mod_ids:
                ctx.error(path, f"{field}.mod_id", f"gear mod is not defined in gear_mods.json: {mod_id}")
            _parse_float(ctx, path, f"{field}.drop_chance", row.get("drop_chance"), minimum=0.0, maximum=1.0)
            min_level = _parse_int(ctx, path, f"{field}.min_enemy_level", row.get("min_enemy_level"), minimum=1)
            max_level = _parse_int(ctx, path, f"{field}.max_enemy_level", row.get("max_enemy_level"), minimum=1)
            if min_level is not None and max_level is not None:
                if max_level < min_level:
                    ctx.error(path, f"{field}.max_enemy_level", "must be >= min_enemy_level")
                if source_enemy_id and mod_id:
                    key = (source_enemy_id, mod_id, min_level, max_level)
                    if key in seen:
                        ctx.error(path, field, f"duplicate drop row {source_enemy_id}/{mod_id}/{min_level}-{max_level}")
                    seen.add(key)
        if row_count == 0:
            ctx.error(path, "rows", "must contain at least one gear mod drop row")


def _validate_gear_mod_fusion_costs(ctx: ValidationContext, rarity_max_ranks: dict[str, int]) -> None:
    path = GEAR_MOD_FUSION_COSTS_CSV
    if not path.exists():
        ctx.error(path, "$", "missing gear mod fusion costs CSV")
        return

    required = {"rarity", "rank", "resource_id", "cost"}
    costs_by_rarity: dict[str, set[int]] = {}
    seen: set[tuple[str, int]] = set()
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        fieldnames = reader.fieldnames or []
        missing = required.difference(fieldnames)
        if missing:
            ctx.error(path, "header", f"missing required columns {sorted(missing)}")
            return
        row_count = 0
        for line_number, row in enumerate(reader, start=2):
            row_count += 1
            field = f"line {line_number}"
            rarity = _require_registered(ctx, path, f"{field}.rarity", row.get("rarity"), "gear_mod_rarities")
            rank = _parse_int(ctx, path, f"{field}.rank", row.get("rank"), minimum=1)
            _require_registered(ctx, path, f"{field}.resource_id", row.get("resource_id"), "gear_mod_resources")
            _parse_int(ctx, path, f"{field}.cost", row.get("cost"), minimum=0)
            if rarity and rank is not None:
                key = (rarity, rank)
                if key in seen:
                    ctx.error(path, field, f"duplicate fusion cost for {rarity} rank {rank}")
                seen.add(key)
                costs_by_rarity.setdefault(rarity, set()).add(rank)
        if row_count == 0:
            ctx.error(path, "rows", "must contain at least one gear mod fusion cost row")

    for rarity, max_rank in rarity_max_ranks.items():
        covered = costs_by_rarity.get(rarity, set())
        for rank in range(1, max_rank + 1):
            if rank not in covered:
                ctx.error(path, f"{rarity}.rank_{rank}", "missing fusion cost for gear mod rarity/rank")


def _status_params_has_damage_tick(params: dict[str, Any]) -> bool:
    magnitude = params.get("magnitude", 0.0)
    tick_interval = params.get("tick_interval", 0.0)
    if not isinstance(magnitude, (int, float)) or isinstance(magnitude, bool):
        return False
    if not isinstance(tick_interval, (int, float)) or isinstance(tick_interval, bool):
        return False
    return float(magnitude) > 0.0 and float(tick_interval) > 0.0


def _validate_consumables(ctx: ValidationContext) -> None:
    path = CONSUMABLES_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=1)
    consumables = _require_list(ctx, path, "consumables", data.get("consumables"))
    if not consumables:
        ctx.error(path, "consumables", "must be a non-empty array")
    seen: set[str] = set()
    for index, consumable in enumerate(consumables):
        field = f"consumables[{index}]"
        if not isinstance(consumable, dict):
            ctx.error(path, field, "must be an object")
            continue
        consumable_id = _require_non_empty_string(ctx, path, f"{field}.id", consumable.get("id"))
        if consumable_id:
            if consumable_id in seen:
                ctx.error(path, f"{field}.id", f"duplicate consumable id {consumable_id}")
            seen.add(consumable_id)
        _require_locale_key(ctx, path, f"{field}.name_key", consumable.get("name_key"))
        _require_locale_key(ctx, path, f"{field}.desc_key", consumable.get("desc_key"))
        _require_bool(ctx, path, f"{field}.default_unlocked", consumable.get("default_unlocked"))
        tags = _validate_registered_string_list(ctx, path, f"{field}.tags", consumable.get("tags"), "content_tags", allow_empty=False)
        if "tag_consumable" not in tags:
            ctx.error(path, f"{field}.tags", "must include tag_consumable")
        _validate_consumable_stack(ctx, path, f"{field}.stack", consumable.get("stack"))
        _validate_consumable_use_effects(ctx, path, f"{field}.use_effects", consumable.get("use_effects"))


def _validate_consumable_stack(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    max_stack = _require_int(ctx, path, f"{field}.max_stack", data.get("max_stack"), minimum=1)
    start_count = _require_int(ctx, path, f"{field}.start_count", data.get("start_count"), minimum=0)
    pickup_count = _require_int(ctx, path, f"{field}.pickup_count", data.get("pickup_count"), minimum=1)
    if isinstance(max_stack, int) and isinstance(start_count, int) and start_count > max_stack:
        ctx.error(path, f"{field}.start_count", "must be <= max_stack")
    if isinstance(max_stack, int) and isinstance(pickup_count, int) and pickup_count > max_stack:
        ctx.error(path, f"{field}.pickup_count", "must be <= max_stack")


def _validate_consumable_use_effects(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    effects = _require_list(ctx, path, field, data)
    if not effects:
        ctx.error(path, field, "must be a non-empty array")
    for index, effect in enumerate(effects):
        item_field = f"{field}[{index}]"
        if not isinstance(effect, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        _require_registered(ctx, path, f"{item_field}.effect", effect.get("effect"), "effects")
        if not isinstance(effect.get("params"), dict):
            ctx.error(path, f"{item_field}.params", "must be an object")


def _validate_credits(ctx: ValidationContext) -> None:
    path = CREDITS_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=1)
    sections = _require_list(ctx, path, "sections", data.get("sections"))
    if not sections:
        ctx.error(path, "sections", "must be a non-empty array")
    seen_sections: set[str] = set()
    for section_index, section in enumerate(sections):
        section_field = f"sections[{section_index}]"
        if not isinstance(section, dict):
            ctx.error(path, section_field, "must be an object")
            continue
        section_id = _require_non_empty_string(ctx, path, f"{section_field}.id", section.get("id"))
        if section_id:
            if section_id in seen_sections:
                ctx.error(path, f"{section_field}.id", f"duplicate section id {section_id}")
            seen_sections.add(section_id)
        _require_locale_key(ctx, path, f"{section_field}.title_key", section.get("title_key"))
        entries = _require_list(ctx, path, f"{section_field}.entries", section.get("entries"))
        if not entries:
            ctx.error(path, f"{section_field}.entries", "must be a non-empty array")
        for entry_index, entry in enumerate(entries):
            _validate_credit_entry(ctx, path, f"{section_field}.entries[{entry_index}]", entry)


def _validate_credit_entry(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    kind = data.get("kind")
    if kind not in {"staff", "external_resource", "external_library", "external_tool"}:
        ctx.error(path, f"{field}.kind", "must be staff, external_resource, external_library, or external_tool")
    _require_non_empty_string(ctx, path, f"{field}.name", data.get("name"))
    _require_locale_key(ctx, path, f"{field}.role_key", data.get("role_key"))
    if isinstance(kind, str) and kind.startswith("external_"):
        _require_non_empty_string(ctx, path, f"{field}.url", data.get("url"))
        _require_non_empty_string(ctx, path, f"{field}.license", data.get("license"))
        _require_bool(ctx, path, f"{field}.included_in_build", data.get("included_in_build"))
        _require_bool(ctx, path, f"{field}.requires_notice", data.get("requires_notice"))
        _require_bool(ctx, path, f"{field}.review_required", data.get("review_required"))
    if "copyright" in data:
        _require_non_empty_string(ctx, path, f"{field}.copyright", data.get("copyright"))


def _validate_growth_csv(ctx: ValidationContext) -> None:
    if not GROWTH_CSV.exists():
        ctx.error(GROWTH_CSV, "$", "missing growth curve CSV")
        return

    required = {
        "level",
        "total_xp_required",
        "candidate_count",
        "bonus_candidate_chance_per_luck",
        "bonus_candidate_chance_cap",
    }
    previous_level = 0
    previous_xp = -1
    with GROWTH_CSV.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        fieldnames = reader.fieldnames or []
        missing = required.difference(fieldnames)
        if missing:
            ctx.error(GROWTH_CSV, "header", f"missing required columns {sorted(missing)}")
            return
        for line_number, row in enumerate(reader, start=2):
            level = _parse_int(ctx, GROWTH_CSV, f"line {line_number}.level", row.get("level"))
            total_xp = _parse_int(ctx, GROWTH_CSV, f"line {line_number}.total_xp_required", row.get("total_xp_required"))
            candidate_count = _parse_int(ctx, GROWTH_CSV, f"line {line_number}.candidate_count", row.get("candidate_count"))
            chance_per_luck = _parse_float(
                ctx,
                GROWTH_CSV,
                f"line {line_number}.bonus_candidate_chance_per_luck",
                row.get("bonus_candidate_chance_per_luck"),
            )
            chance_cap = _parse_float(ctx, GROWTH_CSV, f"line {line_number}.bonus_candidate_chance_cap", row.get("bonus_candidate_chance_cap"))
            if isinstance(level, int) and level < 1:
                ctx.error(GROWTH_CSV, f"line {line_number}.level", "must be >= 1")
            if isinstance(level, int):
                if level <= previous_level:
                    ctx.error(GROWTH_CSV, f"line {line_number}.level", "must be strictly increasing")
                previous_level = level
            if isinstance(total_xp, int):
                if total_xp < 0:
                    ctx.error(GROWTH_CSV, f"line {line_number}.total_xp_required", "must be >= 0")
                if total_xp <= previous_xp:
                    ctx.error(GROWTH_CSV, f"line {line_number}.total_xp_required", "must be strictly increasing")
                previous_xp = total_xp
            if isinstance(candidate_count, int) and candidate_count < 1:
                ctx.error(GROWTH_CSV, f"line {line_number}.candidate_count", "must be >= 1")
            if isinstance(chance_per_luck, float) and not 0 <= chance_per_luck <= 1:
                ctx.error(GROWTH_CSV, f"line {line_number}.bonus_candidate_chance_per_luck", "must be between 0 and 1")
            if isinstance(chance_cap, float) and not 0 <= chance_cap <= 1:
                ctx.error(GROWTH_CSV, f"line {line_number}.bonus_candidate_chance_cap", "must be between 0 and 1")


def _validate_growth_pools(ctx: ValidationContext) -> None:
    path = GROWTH_POOLS_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=1)
    pools = _require_list(ctx, path, "pools", data.get("pools"))
    pool_ids: set[str] = set()
    for pool_index, pool in enumerate(pools):
        pool_field = f"pools[{pool_index}]"
        if not isinstance(pool, dict):
            ctx.error(path, pool_field, "must be an object")
            continue
        pool_id = _require_non_empty_string(ctx, path, f"{pool_field}.id", pool.get("id"))
        if pool_id:
            if pool_id in pool_ids:
                ctx.error(path, f"{pool_field}.id", f"duplicate pool id {pool_id}")
            pool_ids.add(pool_id)
        entries = _require_list(ctx, path, f"{pool_field}.entries", pool.get("entries"))
        entry_ids: set[str] = set()
        for entry_index, entry in enumerate(entries):
            entry_field = f"{pool_field}.entries[{entry_index}]"
            if not isinstance(entry, dict):
                ctx.error(path, entry_field, "must be an object")
                continue
            entry_id = _require_non_empty_string(ctx, path, f"{entry_field}.id", entry.get("id"))
            _require_locale_key(ctx, path, f"{entry_field}.name_key", entry.get("name_key"))
            _require_locale_key(ctx, path, f"{entry_field}.desc_key", entry.get("desc_key"))
            if entry_id:
                if entry_id in entry_ids:
                    ctx.error(path, f"{entry_field}.id", f"duplicate entry id {entry_id}")
                entry_ids.add(entry_id)
            _require_non_empty_string(ctx, path, f"{entry_field}.kind", entry.get("kind"))
            _require_int(ctx, path, f"{entry_field}.weight", entry.get("weight"), minimum=0)
            if "min_level" in entry:
                _require_int(ctx, path, f"{entry_field}.min_level", entry.get("min_level"), minimum=1)
            if "modifiers" in entry:
                _validate_modifiers(ctx, path, f"{entry_field}.modifiers", entry.get("modifiers"), require_value_per_level=False)


def _validate_game_modes(
    ctx: ValidationContext,
    character_ids: set[str],
    weapon_ids: set[str],
    enemy_ids: set[str],
    hazard_ids: set[str],
    relic_ids: set[str],
    active_item_ids: set[str],
    consumable_ids: set[str],
    skill_ids: set[str],
) -> None:
    path = GAME_MODES_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=1)
    modes = _require_list(ctx, path, "modes", data.get("modes"))
    if not modes:
        ctx.error(path, "modes", "must be a non-empty array")
    seen_modes: set[str] = set()
    growth_pool_ids = _collect_growth_pool_ids(ctx)
    for mode_index, mode in enumerate(modes):
        mode_field = f"modes[{mode_index}]"
        if not isinstance(mode, dict):
            ctx.error(path, mode_field, "must be an object")
            continue
        mode_id = _require_registered(ctx, path, f"{mode_field}.id", mode.get("id"), "game_modes")
        if mode_id:
            if mode_id in seen_modes:
                ctx.error(path, f"{mode_field}.id", f"duplicate game mode id {mode_id}")
            seen_modes.add(mode_id)
        _require_locale_key(ctx, path, f"{mode_field}.name_key", mode.get("name_key"))
        _require_locale_key(ctx, path, f"{mode_field}.desc_key", mode.get("desc_key"))
        _require_bool(ctx, path, f"{mode_field}.default_unlocked", mode.get("default_unlocked"))
        team_ids = _validate_mode_teams(ctx, path, mode_field, mode.get("teams"))
        _validate_mode_participants(ctx, path, mode_field, mode.get("participants"), team_ids)
        _validate_mode_resource_pools(ctx, path, mode_field, mode.get("resource_pools"), growth_pool_ids, character_ids, weapon_ids, enemy_ids, hazard_ids, relic_ids, active_item_ids, consumable_ids, skill_ids)
        if "blocklists" in mode:
            _validate_mode_blocklists(ctx, path, f"{mode_field}.blocklists", mode.get("blocklists"))
        if "overrides" in mode:
            _validate_mode_overrides(ctx, path, f"{mode_field}.overrides", mode.get("overrides"))


def _validate_map_layouts(ctx: ValidationContext, hazard_ids: set[str], game_mode_ids: set[str]) -> None:
    path = MAP_LAYOUTS_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=1)
    layouts = _require_list(ctx, path, "layouts", data.get("layouts"))
    if not layouts:
        ctx.error(path, "layouts", "must be a non-empty array")
    seen_layouts: set[str] = set()
    for layout_index, layout in enumerate(layouts):
        layout_field = f"layouts[{layout_index}]"
        if not isinstance(layout, dict):
            ctx.error(path, layout_field, "must be an object")
            continue
        layout_id = _require_non_empty_string(ctx, path, f"{layout_field}.id", layout.get("id"))
        if layout_id:
            if layout_id in seen_layouts:
                ctx.error(path, f"{layout_field}.id", f"duplicate map layout id {layout_id}")
            seen_layouts.add(layout_id)
        mode_id = _require_registered(ctx, path, f"{layout_field}.mode_id", layout.get("mode_id"), "game_modes")
        if mode_id and mode_id not in game_mode_ids:
            ctx.error(path, f"{layout_field}.mode_id", f"mode is not defined in game_modes.json: {mode_id}")
        _validate_map_bounds(ctx, path, f"{layout_field}.bounds", layout.get("bounds"))
        _validate_map_grid(ctx, path, f"{layout_field}.grid", layout.get("grid"))
        _validate_map_bounds_grid_alignment(ctx, path, layout_field, layout.get("bounds"), layout.get("grid"))
        _validate_map_point(ctx, path, f"{layout_field}.player_start", layout.get("player_start"))
        _validate_map_point_on_grid(ctx, path, f"{layout_field}.player_start", layout.get("player_start"), layout.get("grid"))
        _require_number(ctx, path, f"{layout_field}.safe_radius", layout.get("safe_radius"), minimum=0)
        _require_number(ctx, path, f"{layout_field}.enemy_spawn_margin", layout.get("enemy_spawn_margin"), minimum=0)
        _validate_map_pcg(ctx, path, f"{layout_field}.pcg", layout.get("pcg", {}), hazard_ids)
        _validate_map_manual_hazards(ctx, path, f"{layout_field}.manual_hazards", layout.get("manual_hazards", []), hazard_ids, layout.get("grid"))


def _validate_warzone_directors(
    ctx: ValidationContext,
    game_mode_ids: set[str],
    wave_ids_by_mode: dict[str, set[str]],
    hazard_ids: dict[str, int],
    map_layout_ids: set[str],
    gear_mod_ids: set[str],
) -> None:
    path = WARZONE_DIRECTORS_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=1)
    directors = _require_list(ctx, path, "directors", data.get("directors"))
    if not directors:
        ctx.error(path, "directors", "must be a non-empty array")
    seen_directors: set[str] = set()
    seen_modes: set[str] = set()
    for director_index, director in enumerate(directors):
        director_field = f"directors[{director_index}]"
        if not isinstance(director, dict):
            ctx.error(path, director_field, "must be an object")
            continue
        director_id = _require_non_empty_string(ctx, path, f"{director_field}.id", director.get("id"))
        if director_id:
            if director_id in seen_directors:
                ctx.error(path, f"{director_field}.id", f"duplicate director id {director_id}")
            seen_directors.add(director_id)
        mode_id = _require_registered(ctx, path, f"{director_field}.mode_id", director.get("mode_id"), "game_modes")
        if mode_id:
            if mode_id not in game_mode_ids:
                ctx.error(path, f"{director_field}.mode_id", f"mode is not defined in game_modes.json: {mode_id}")
            if mode_id in seen_modes:
                ctx.error(path, f"{director_field}.mode_id", f"duplicate director for mode {mode_id}")
            seen_modes.add(mode_id)
        _require_non_empty_string(ctx, path, f"{director_field}.mutation_id", director.get("mutation_id"))
        if "description" in director:
            _require_non_empty_string(ctx, path, f"{director_field}.description", director.get("description"))

        encounter_ids = _validate_warzone_encounters(ctx, path, f"{director_field}.encounters", director.get("encounters"))
        _validate_warzone_interest_points(ctx, path, f"{director_field}.interest_points", director.get("interest_points"), hazard_ids, map_layout_ids, gear_mod_ids)
        mode_wave_ids = wave_ids_by_mode.get(mode_id or "", set())
        referenced_waves = _validate_warzone_phases(ctx, path, director_field, director.get("phases"), mode_id or "", mode_wave_ids, encounter_ids)
        for wave_id in mode_wave_ids:
            if wave_id not in referenced_waves:
                ctx.error(path, f"{director_field}.phases", f"must reference wave {wave_id} at least once")


def _validate_warzone_phases(
    ctx: ValidationContext,
    path: Path,
    director_field: str,
    data: Any,
    mode_id: str,
    mode_wave_ids: set[str],
    encounter_ids: set[str],
) -> set[str]:
    phases = _require_list(ctx, path, f"{director_field}.phases", data)
    if not phases:
        ctx.error(path, f"{director_field}.phases", "must be a non-empty array")
    seen_phases: set[str] = set()
    referenced_waves: set[str] = set()
    previous_end: float | None = None
    for phase_index, phase in enumerate(phases):
        phase_field = f"{director_field}.phases[{phase_index}]"
        if not isinstance(phase, dict):
            ctx.error(path, phase_field, "must be an object")
            continue
        phase_id = _require_non_empty_string(ctx, path, f"{phase_field}.id", phase.get("id"))
        if phase_id:
            if phase_id in seen_phases:
                ctx.error(path, f"{phase_field}.id", f"duplicate phase id {phase_id}")
            seen_phases.add(phase_id)
        start_time = _require_number(ctx, path, f"{phase_field}.start_time", phase.get("start_time"), minimum=0)
        end_time = _require_number(ctx, path, f"{phase_field}.end_time", phase.get("end_time"), minimum=0, exclusive_minimum=True)
        if start_time is not None and end_time is not None:
            if end_time <= start_time:
                ctx.error(path, f"{phase_field}.end_time", "must be greater than start_time")
            if previous_end is not None and start_time < previous_end:
                ctx.error(path, f"{phase_field}.start_time", "must be an ascending non-overlapping time window")
            previous_end = end_time
        _require_non_empty_string(ctx, path, f"{phase_field}.pressure_tag", phase.get("pressure_tag"))

        wave_ids = _require_list(ctx, path, f"{phase_field}.wave_ids", phase.get("wave_ids"))
        if not wave_ids:
            ctx.error(path, f"{phase_field}.wave_ids", "must be a non-empty array")
        seen_wave_ids: set[str] = set()
        for wave_index, wave in enumerate(wave_ids):
            wave_field = f"{phase_field}.wave_ids[{wave_index}]"
            wave_id = _require_non_empty_string(ctx, path, wave_field, wave)
            if not wave_id:
                continue
            if wave_id in seen_wave_ids:
                ctx.error(path, wave_field, f"duplicate wave id {wave_id}")
            seen_wave_ids.add(wave_id)
            if wave_id not in mode_wave_ids:
                ctx.error(path, wave_field, f"wave is not defined in spawn_waves.csv for mode {mode_id}: {wave_id}")
            referenced_waves.add(wave_id)

        phase_encounters = _require_list(ctx, path, f"{phase_field}.encounter_ids", phase.get("encounter_ids"))
        if not phase_encounters:
            ctx.error(path, f"{phase_field}.encounter_ids", "must be a non-empty array")
        seen_encounter_ids: set[str] = set()
        for encounter_index, encounter in enumerate(phase_encounters):
            encounter_field = f"{phase_field}.encounter_ids[{encounter_index}]"
            encounter_id = _require_non_empty_string(ctx, path, encounter_field, encounter)
            if not encounter_id:
                continue
            if encounter_id in seen_encounter_ids:
                ctx.error(path, encounter_field, f"duplicate encounter id {encounter_id}")
            seen_encounter_ids.add(encounter_id)
            if encounter_id not in encounter_ids:
                ctx.error(path, encounter_field, f"encounter is not defined in encounters: {encounter_id}")
    return referenced_waves


def _validate_warzone_encounters(ctx: ValidationContext, path: Path, field: str, data: Any) -> set[str]:
    encounters = _require_list(ctx, path, field, data)
    if not encounters:
        ctx.error(path, field, "must be a non-empty array")
    seen: set[str] = set()
    for index, encounter in enumerate(encounters):
        item_field = f"{field}[{index}]"
        if not isinstance(encounter, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        encounter_id = _require_non_empty_string(ctx, path, f"{item_field}.id", encounter.get("id"))
        if encounter_id:
            if encounter_id in seen:
                ctx.error(path, f"{item_field}.id", f"duplicate encounter id {encounter_id}")
            seen.add(encounter_id)
        _require_non_empty_string(ctx, path, f"{item_field}.kind", encounter.get("kind"))
        _validate_registered_string_list(ctx, path, f"{item_field}.enemy_tags", encounter.get("enemy_tags"), "content_tags", allow_empty=False)
        if "notes" in encounter:
            _require_non_empty_string(ctx, path, f"{item_field}.notes", encounter.get("notes"))
    return seen


def _validate_warzone_interest_points(
    ctx: ValidationContext,
    path: Path,
    field: str,
    data: Any,
    hazard_ids: dict[str, int],
    map_layout_ids: set[str],
    gear_mod_ids: set[str],
) -> None:
    points = _require_list(ctx, path, field, data)
    if not points:
        ctx.error(path, field, "must be a non-empty array")
    seen: set[str] = set()
    for index, point in enumerate(points):
        item_field = f"{field}[{index}]"
        if not isinstance(point, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        point_id = _require_non_empty_string(ctx, path, f"{item_field}.id", point.get("id"))
        if point_id:
            if point_id in seen:
                ctx.error(path, f"{item_field}.id", f"duplicate interest point id {point_id}")
            seen.add(point_id)
        _require_non_empty_string(ctx, path, f"{item_field}.kind", point.get("kind"))
        point_hazards = _require_list(ctx, path, f"{item_field}.hazard_ids", point.get("hazard_ids", []))
        if not point_hazards:
            ctx.error(path, f"{item_field}.hazard_ids", "must be a non-empty array")
        for hazard_index, hazard in enumerate(point_hazards):
            hazard_field = f"{item_field}.hazard_ids[{hazard_index}]"
            hazard_id = _require_non_empty_string(ctx, path, hazard_field, hazard)
            if hazard_id and hazard_id not in hazard_ids:
                ctx.error(path, hazard_field, f"hazard is not defined in hazards.csv: {hazard_id}")
        if "map_layout_id" in point:
            map_layout_id = _require_non_empty_string(ctx, path, f"{item_field}.map_layout_id", point.get("map_layout_id"))
            if map_layout_id and map_layout_id not in map_layout_ids:
                ctx.error(path, f"{item_field}.map_layout_id", f"map layout is not defined in map_layouts.json: {map_layout_id}")
        if "min_distance_from_player" in point:
            _require_number(ctx, path, f"{item_field}.min_distance_from_player", point.get("min_distance_from_player"), minimum=0)
        if "min_spacing" in point:
            _require_number(ctx, path, f"{item_field}.min_spacing", point.get("min_spacing"), minimum=0)
        completes_run = bool(point.get("completes_run", False))
        has_reward_payload = "resource_rewards" in point or "gear_mod_rewards" in point or completes_run
        if "claim_radius" in point or has_reward_payload:
            _require_number(ctx, path, f"{item_field}.claim_radius", point.get("claim_radius"), minimum=0, exclusive_minimum=True)
        if "claim_start_time" in point:
            _require_number(ctx, path, f"{item_field}.claim_start_time", point.get("claim_start_time"), minimum=0)
        if "requires_interaction" in point:
            _require_bool(ctx, path, f"{item_field}.requires_interaction", point.get("requires_interaction"))
        if "completes_run" in point:
            _require_bool(ctx, path, f"{item_field}.completes_run", point.get("completes_run"))
        if "extraction_radius" in point or completes_run:
            _require_number(ctx, path, f"{item_field}.extraction_radius", point.get("extraction_radius"), minimum=0, exclusive_minimum=True)
        if "extraction_hold_time" in point or completes_run:
            _require_number(ctx, path, f"{item_field}.extraction_hold_time", point.get("extraction_hold_time"), minimum=0, exclusive_minimum=True)
        if "target_hp" in point:
            _require_number(ctx, path, f"{item_field}.target_hp", point.get("target_hp"), minimum=0, exclusive_minimum=True)
        if "target_hit_radius" in point:
            _require_number(ctx, path, f"{item_field}.target_hit_radius", point.get("target_hit_radius"), minimum=0, exclusive_minimum=True)
        if "resource_rewards" in point:
            _validate_warzone_resource_rewards(ctx, path, f"{item_field}.resource_rewards", point.get("resource_rewards"))
        if "gear_mod_rewards" in point:
            _validate_warzone_gear_mod_rewards(ctx, path, f"{item_field}.gear_mod_rewards", point.get("gear_mod_rewards"), gear_mod_ids)
        if "notes" in point:
            _require_non_empty_string(ctx, path, f"{item_field}.notes", point.get("notes"))


def _validate_warzone_resource_rewards(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    rewards = _require_list(ctx, path, field, data)
    if not rewards:
        ctx.error(path, field, "must be a non-empty array")
    for index, reward in enumerate(rewards):
        reward_field = f"{field}[{index}]"
        if not isinstance(reward, dict):
            ctx.error(path, reward_field, "must be an object")
            continue
        _require_registered(ctx, path, f"{reward_field}.resource_id", reward.get("resource_id"), "gear_mod_resources")
        _require_int(ctx, path, f"{reward_field}.amount", reward.get("amount"), minimum=1)


def _validate_warzone_gear_mod_rewards(ctx: ValidationContext, path: Path, field: str, data: Any, gear_mod_ids: set[str]) -> None:
    rewards = _require_list(ctx, path, field, data)
    if not rewards:
        ctx.error(path, field, "must be a non-empty array")
    for index, reward in enumerate(rewards):
        reward_field = f"{field}[{index}]"
        if not isinstance(reward, dict):
            ctx.error(path, reward_field, "must be an object")
            continue
        mod_id = _require_registered(ctx, path, f"{reward_field}.mod_id", reward.get("mod_id"), "gear_mod_ids")
        if mod_id and mod_id not in gear_mod_ids:
            ctx.error(path, f"{reward_field}.mod_id", f"mod is not defined in gear_mods.json: {mod_id}")
        _require_int(ctx, path, f"{reward_field}.count", reward.get("count"), minimum=1)


def _validate_map_bounds(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    _require_number(ctx, path, f"{field}.width", data.get("width"), minimum=0, exclusive_minimum=True)
    _require_number(ctx, path, f"{field}.height", data.get("height"), minimum=0, exclusive_minimum=True)


def _validate_map_grid(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    _require_number(ctx, path, f"{field}.cell_width", data.get("cell_width"), minimum=0, exclusive_minimum=True)
    _require_number(ctx, path, f"{field}.cell_height", data.get("cell_height"), minimum=0, exclusive_minimum=True)


def _validate_map_bounds_grid_alignment(ctx: ValidationContext, path: Path, field: str, bounds: Any, grid: Any) -> None:
    if not isinstance(bounds, dict) or not isinstance(grid, dict):
        return
    width = bounds.get("width")
    height = bounds.get("height")
    cell_width = grid.get("cell_width")
    cell_height = grid.get("cell_height")
    if isinstance(width, (int, float)) and isinstance(cell_width, (int, float)):
        if not _is_nearly_grid_multiple(float(width), float(cell_width)):
            ctx.error(path, f"{field}.bounds.width", "must be an integer multiple of grid.cell_width")
        elif float(cell_width) > 0 and round(float(width) / float(cell_width)) % 2 == 0:
            ctx.error(path, f"{field}.bounds.width", "must span an odd number of grid.cell_width cells so the boundary lands on diamond grid lines")
    if isinstance(height, (int, float)) and isinstance(cell_height, (int, float)):
        if not _is_nearly_grid_multiple(float(height), float(cell_height)):
            ctx.error(path, f"{field}.bounds.height", "must be an integer multiple of grid.cell_height")
        elif float(cell_height) > 0 and round(float(height) / float(cell_height)) % 2 == 0:
            ctx.error(path, f"{field}.bounds.height", "must span an odd number of grid.cell_height cells so the boundary lands on diamond grid lines")
    if (
        isinstance(width, (int, float))
        and isinstance(height, (int, float))
        and isinstance(cell_width, (int, float))
        and isinstance(cell_height, (int, float))
        and float(cell_width) > 0
        and float(cell_height) > 0
    ):
        expected_height = float(width) * float(cell_height) / float(cell_width)
        if abs(float(height) - expected_height) > 0.01:
            ctx.error(path, f"{field}.bounds", "must match the grid-aligned diamond aspect")


def _validate_map_point(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    _require_number(ctx, path, f"{field}.x", data.get("x"))
    _require_number(ctx, path, f"{field}.y", data.get("y"))


def _validate_map_point_on_grid(ctx: ValidationContext, path: Path, field: str, point: Any, grid: Any) -> None:
    if _is_map_point_on_grid_center(point, grid):
        return
    ctx.error(path, field, "must be a diamond grid center")


def _validate_map_point_on_hazard_anchor(
    ctx: ValidationContext,
    path: Path,
    field: str,
    point: Any,
    grid: Any,
    radius_tiles: int,
) -> None:
    if radius_tiles % 2 == 1:
        if _is_map_point_on_grid_center(point, grid):
            return
        ctx.error(path, field, "must be a diamond grid center for odd radius_tiles")
        return
    if _is_map_point_on_grid_vertex(point, grid):
        return
    ctx.error(path, field, "must be a diamond grid vertex for even radius_tiles")


def _is_map_point_on_grid_center(point: Any, grid: Any) -> bool:
    if not isinstance(point, dict) or not isinstance(grid, dict):
        return True
    x = point.get("x")
    y = point.get("y")
    cell_width = grid.get("cell_width")
    cell_height = grid.get("cell_height")
    if not isinstance(x, (int, float)) or not isinstance(y, (int, float)):
        return True
    if not isinstance(cell_width, (int, float)) or not isinstance(cell_height, (int, float)):
        return True
    half_width = max(float(cell_width) * 0.5, 1.0)
    half_height = max(float(cell_height) * 0.5, 1.0)
    u = float(x) / half_width
    v = float(y) / half_height
    column = (u + v) * 0.5
    row = (v - u) * 0.5
    return _is_nearly_integer(column) and _is_nearly_integer(row)


def _is_map_point_on_grid_vertex(point: Any, grid: Any) -> bool:
    if not isinstance(point, dict) or not isinstance(grid, dict):
        return True
    x = point.get("x")
    y = point.get("y")
    cell_width = grid.get("cell_width")
    cell_height = grid.get("cell_height")
    if not isinstance(x, (int, float)) or not isinstance(y, (int, float)):
        return True
    if not isinstance(cell_width, (int, float)) or not isinstance(cell_height, (int, float)):
        return True
    half_width = max(float(cell_width) * 0.5, 1.0)
    half_height = max(float(cell_height) * 0.5, 1.0)
    u = float(x) / half_width
    v = float(y) / half_height
    if not _is_nearly_integer(u) or not _is_nearly_integer(v):
        return False
    return (round(u) + round(v)) % 2 != 0


def _validate_map_pcg(ctx: ValidationContext, path: Path, field: str, data: Any, hazard_ids: dict[str, int]) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    hazards = _require_list(ctx, path, f"{field}.hazards", data.get("hazards", []))
    for index, hazard in enumerate(hazards):
        item_field = f"{field}.hazards[{index}]"
        if not isinstance(hazard, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        hazard_id = _require_non_empty_string(ctx, path, f"{item_field}.id", hazard.get("id"))
        if hazard_id and hazard_id not in hazard_ids:
            ctx.error(path, f"{item_field}.id", f"hazard is not defined in hazards.csv: {hazard_id}")
        _require_int(ctx, path, f"{item_field}.count", hazard.get("count"), minimum=0)
        _require_number(ctx, path, f"{item_field}.min_distance_from_player", hazard.get("min_distance_from_player"), minimum=0)
        _require_number(ctx, path, f"{item_field}.min_spacing", hazard.get("min_spacing"), minimum=0)


def _validate_map_manual_hazards(ctx: ValidationContext, path: Path, field: str, data: Any, hazard_ids: dict[str, int], grid: Any) -> None:
    hazards = _require_list(ctx, path, field, data)
    for index, hazard in enumerate(hazards):
        item_field = f"{field}[{index}]"
        if not isinstance(hazard, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        hazard_id = _require_non_empty_string(ctx, path, f"{item_field}.id", hazard.get("id"))
        if hazard_id and hazard_id not in hazard_ids:
            ctx.error(path, f"{item_field}.id", f"hazard is not defined in hazards.csv: {hazard_id}")
        _require_number(ctx, path, f"{item_field}.x", hazard.get("x"))
        _require_number(ctx, path, f"{item_field}.y", hazard.get("y"))
        _validate_map_point_on_hazard_anchor(ctx, path, item_field, hazard, grid, hazard_ids.get(hazard_id, 1))


def _validate_mode_teams(ctx: ValidationContext, path: Path, mode_field: str, data: Any) -> set[str]:
    teams = _require_list(ctx, path, f"{mode_field}.teams", data)
    if not teams:
        ctx.error(path, f"{mode_field}.teams", "must be a non-empty array")
    team_ids: set[str] = set()
    for index, team in enumerate(teams):
        field = f"{mode_field}.teams[{index}]"
        if not isinstance(team, dict):
            ctx.error(path, field, "must be an object")
            continue
        team_id = _require_non_empty_string(ctx, path, f"{field}.id", team.get("id"))
        if team_id:
            if team_id in team_ids:
                ctx.error(path, f"{field}.id", f"duplicate team id {team_id}")
            team_ids.add(team_id)
        _require_bool(ctx, path, f"{field}.friendly_fire", team.get("friendly_fire"))
    return team_ids


def _validate_mode_participants(ctx: ValidationContext, path: Path, mode_field: str, data: Any, team_ids: set[str]) -> None:
    participants = _require_list(ctx, path, f"{mode_field}.participants", data)
    if not participants:
        ctx.error(path, f"{mode_field}.participants", "must be a non-empty array")
    participant_ids: set[str] = set()
    for index, participant in enumerate(participants):
        field = f"{mode_field}.participants[{index}]"
        if not isinstance(participant, dict):
            ctx.error(path, field, "must be an object")
            continue
        participant_id = _require_non_empty_string(ctx, path, f"{field}.id", participant.get("id"))
        if participant_id:
            if participant_id in participant_ids:
                ctx.error(path, f"{field}.id", f"duplicate participant id {participant_id}")
            participant_ids.add(participant_id)
        _require_non_empty_string(ctx, path, f"{field}.kind", participant.get("kind"))
        team_id = _require_non_empty_string(ctx, path, f"{field}.team_id", participant.get("team_id"))
        if team_id and team_id not in team_ids:
            ctx.error(path, f"{field}.team_id", f"team is not defined in teams: {team_id}")
        if "control" in participant:
            _require_non_empty_string(ctx, path, f"{field}.control", participant.get("control"))


def _validate_mode_resource_pools(
    ctx: ValidationContext,
    path: Path,
    mode_field: str,
    data: Any,
    growth_pool_ids: set[str],
    character_ids: set[str],
    weapon_ids: set[str],
    enemy_ids: set[str],
    hazard_ids: set[str],
    relic_ids: set[str],
    active_item_ids: set[str],
    consumable_ids: set[str],
    skill_ids: set[str],
) -> None:
    field = f"{mode_field}.resource_pools"
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    if "characters" in data:
        _validate_weighted_character_entries(ctx, path, f"{field}.characters", data.get("characters"), character_ids)
    if "weapons" in data:
        _validate_weighted_weapon_entries(ctx, path, f"{field}.weapons", data.get("weapons"), weapon_ids)
    if "enemies" in data:
        _validate_weighted_enemy_entries(ctx, path, f"{field}.enemies", data.get("enemies"), enemy_ids)
    if "hazards" in data:
        _validate_weighted_hazard_entries(ctx, path, f"{field}.hazards", data.get("hazards"), hazard_ids)
    if "relics" in data:
        _validate_weighted_relic_entries(ctx, path, f"{field}.relics", data.get("relics"), relic_ids)
    if "active_items" in data:
        _validate_weighted_active_item_entries(ctx, path, f"{field}.active_items", data.get("active_items"), active_item_ids)
    if "skills" in data:
        _validate_weighted_skill_entries(ctx, path, f"{field}.skills", data.get("skills"), skill_ids)
    if "consumables" in data:
        _validate_weighted_consumable_entries(ctx, path, f"{field}.consumables", data.get("consumables"), consumable_ids)
    if "growth_pools" in data:
        _validate_weighted_growth_pool_entries(ctx, path, f"{field}.growth_pools", data.get("growth_pools"), growth_pool_ids)
    if "characters" not in data and "weapons" not in data and "enemies" not in data and "hazards" not in data and "relics" not in data and "active_items" not in data and "skills" not in data and "consumables" not in data and "growth_pools" not in data:
        ctx.error(path, field, "must contain at least one supported pool")


def _validate_weighted_character_entries(ctx: ValidationContext, path: Path, field: str, data: Any, character_ids: set[str]) -> None:
    entries = _require_list(ctx, path, field, data)
    if not entries:
        ctx.error(path, field, "must be a non-empty array")
    for index, entry in enumerate(entries):
        item_field = f"{field}[{index}]"
        if not isinstance(entry, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        character_id = _require_registered(ctx, path, f"{item_field}.id", entry.get("id"), "character_ids")
        if character_id and character_id not in character_ids:
            ctx.error(path, f"{item_field}.id", f"character is not defined in characters.json: {character_id}")
        _require_int(ctx, path, f"{item_field}.weight", entry.get("weight"), minimum=0)


def _validate_weighted_weapon_entries(ctx: ValidationContext, path: Path, field: str, data: Any, weapon_ids: set[str]) -> None:
    entries = _require_list(ctx, path, field, data)
    if not entries:
        ctx.error(path, field, "must be a non-empty array")
    for index, entry in enumerate(entries):
        item_field = f"{field}[{index}]"
        if not isinstance(entry, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        weapon_id = _require_non_empty_string(ctx, path, f"{item_field}.id", entry.get("id"))
        if weapon_id and weapon_id not in weapon_ids:
            ctx.error(path, f"{item_field}.id", f"weapon is not defined in weapons.json: {weapon_id}")
        _require_int(ctx, path, f"{item_field}.weight", entry.get("weight"), minimum=0)


def _validate_weighted_enemy_entries(ctx: ValidationContext, path: Path, field: str, data: Any, enemy_ids: set[str]) -> None:
    entries = _require_list(ctx, path, field, data)
    if not entries:
        ctx.error(path, field, "must be a non-empty array")
    for index, entry in enumerate(entries):
        item_field = f"{field}[{index}]"
        if not isinstance(entry, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        enemy_id = _require_non_empty_string(ctx, path, f"{item_field}.id", entry.get("id"))
        if enemy_id and enemy_id not in enemy_ids:
            ctx.error(path, f"{item_field}.id", f"enemy is not defined in enemies.csv: {enemy_id}")
        _require_int(ctx, path, f"{item_field}.weight", entry.get("weight"), minimum=0)


def _validate_weighted_hazard_entries(ctx: ValidationContext, path: Path, field: str, data: Any, hazard_ids: set[str]) -> None:
    entries = _require_list(ctx, path, field, data)
    if not entries:
        ctx.error(path, field, "must be a non-empty array")
    for index, entry in enumerate(entries):
        item_field = f"{field}[{index}]"
        if not isinstance(entry, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        hazard_id = _require_non_empty_string(ctx, path, f"{item_field}.id", entry.get("id"))
        if hazard_id and hazard_id not in hazard_ids:
            ctx.error(path, f"{item_field}.id", f"hazard is not defined in hazards.csv: {hazard_id}")
        _require_int(ctx, path, f"{item_field}.weight", entry.get("weight"), minimum=0)


def _validate_weighted_relic_entries(ctx: ValidationContext, path: Path, field: str, data: Any, relic_ids: set[str]) -> None:
    entries = _require_list(ctx, path, field, data)
    if not entries:
        ctx.error(path, field, "must be a non-empty array")
    for index, entry in enumerate(entries):
        item_field = f"{field}[{index}]"
        if not isinstance(entry, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        relic_id = _require_non_empty_string(ctx, path, f"{item_field}.id", entry.get("id"))
        if relic_id and relic_id not in relic_ids:
            ctx.error(path, f"{item_field}.id", f"relic is not defined in relics.json: {relic_id}")
        _require_int(ctx, path, f"{item_field}.weight", entry.get("weight"), minimum=0)


def _validate_weighted_active_item_entries(ctx: ValidationContext, path: Path, field: str, data: Any, active_item_ids: set[str]) -> None:
    entries = _require_list(ctx, path, field, data)
    if not entries:
        ctx.error(path, field, "must be a non-empty array")
    for index, entry in enumerate(entries):
        item_field = f"{field}[{index}]"
        if not isinstance(entry, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        active_item_id = _require_non_empty_string(ctx, path, f"{item_field}.id", entry.get("id"))
        if active_item_id and active_item_id not in active_item_ids:
            ctx.error(path, f"{item_field}.id", f"active item is not defined in active_items.json: {active_item_id}")
        _require_int(ctx, path, f"{item_field}.weight", entry.get("weight"), minimum=0)


def _validate_weighted_skill_entries(ctx: ValidationContext, path: Path, field: str, data: Any, skill_ids: set[str]) -> None:
    entries = _require_list(ctx, path, field, data)
    if not entries:
        ctx.error(path, field, "must be a non-empty array")
    for index, entry in enumerate(entries):
        item_field = f"{field}[{index}]"
        if not isinstance(entry, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        skill_id = _require_registered(ctx, path, f"{item_field}.id", entry.get("id"), "skill_ids")
        if skill_id and skill_id not in skill_ids:
            ctx.error(path, f"{item_field}.id", f"skill is not defined in skills.json: {skill_id}")
        _require_int(ctx, path, f"{item_field}.weight", entry.get("weight"), minimum=0)


def _validate_weighted_consumable_entries(ctx: ValidationContext, path: Path, field: str, data: Any, consumable_ids: set[str]) -> None:
    entries = _require_list(ctx, path, field, data)
    if not entries:
        ctx.error(path, field, "must be a non-empty array")
    for index, entry in enumerate(entries):
        item_field = f"{field}[{index}]"
        if not isinstance(entry, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        consumable_id = _require_non_empty_string(ctx, path, f"{item_field}.id", entry.get("id"))
        if consumable_id and consumable_id not in consumable_ids:
            ctx.error(path, f"{item_field}.id", f"consumable is not defined in consumables.json: {consumable_id}")
        _require_int(ctx, path, f"{item_field}.weight", entry.get("weight"), minimum=0)


def _validate_weighted_contract_entries(ctx: ValidationContext, path: Path, field: str, data: Any, contract_key: str) -> None:
    entries = _require_list(ctx, path, field, data)
    if not entries:
        ctx.error(path, field, "must be a non-empty array")
    for index, entry in enumerate(entries):
        item_field = f"{field}[{index}]"
        if not isinstance(entry, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        _require_registered(ctx, path, f"{item_field}.id", entry.get("id"), contract_key)
        _require_int(ctx, path, f"{item_field}.weight", entry.get("weight"), minimum=0)


def _validate_weighted_growth_pool_entries(ctx: ValidationContext, path: Path, field: str, data: Any, growth_pool_ids: set[str]) -> None:
    entries = _require_list(ctx, path, field, data)
    if not entries:
        ctx.error(path, field, "must be a non-empty array")
    for index, entry in enumerate(entries):
        item_field = f"{field}[{index}]"
        if not isinstance(entry, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        pool_id = _require_non_empty_string(ctx, path, f"{item_field}.id", entry.get("id"))
        if pool_id and pool_id not in growth_pool_ids:
            ctx.error(path, f"{item_field}.id", f"pool is not defined in growth_pools.json: {pool_id}")
        _require_int(ctx, path, f"{item_field}.weight", entry.get("weight"), minimum=0)


def _validate_mode_blocklists(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    if "content_tags" in data:
        tags = _require_list(ctx, path, f"{field}.content_tags", data.get("content_tags"))
        for index, tag in enumerate(tags):
            _require_registered(ctx, path, f"{field}.content_tags[{index}]", tag, "content_tags")


def _validate_mode_overrides(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    if "player_base_stats" in data:
        stats = data.get("player_base_stats")
        if not isinstance(stats, dict):
            ctx.error(path, f"{field}.player_base_stats", "must be an object")
            return
        for stat, value in stats.items():
            _validate_stat_value(ctx, path, f"{field}.player_base_stats.{stat}", stat, value)


def _validate_stat_value(ctx: ValidationContext, path: Path, field: str, stat: str, value: Any) -> None:
    if stat not in ctx.contracts["stats"]:
        ctx.error(path, field, f"unknown stat id {stat}")
        return
    if stat in INT_STATS:
        _require_int(ctx, path, field, value, minimum=1)
    elif stat in RATIO_STATS:
        _require_number(ctx, path, field, value, minimum=0, maximum=1)
    elif stat in POSITIVE_STATS:
        _require_number(ctx, path, field, value, minimum=0, exclusive_minimum=True)
    elif stat in NON_NEGATIVE_STATS:
        _require_number(ctx, path, field, value, minimum=0)
    else:
        _require_number(ctx, path, field, value)


def _validate_modifiers(ctx: ValidationContext, path: Path, field: str, data: Any, *, require_value_per_level: bool) -> None:
    modifiers = _require_list(ctx, path, field, data)
    for index, modifier in enumerate(modifiers):
        item_field = f"{field}[{index}]"
        if not isinstance(modifier, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        stat = _require_registered(ctx, path, f"{item_field}.stat", modifier.get("stat"), "stats")
        modifier_type = modifier.get("type")
        if modifier_type not in {"add", "mult"}:
            ctx.error(path, f"{item_field}.type", "must be add or mult")
        value_field = "value_per_level" if require_value_per_level else "value"
        value = modifier.get(value_field)
        if value is None:
            ctx.error(path, f"{item_field}.{value_field}", "is required")
        elif require_value_per_level:
            _require_number(ctx, path, f"{item_field}.{value_field}", value, minimum=0)
        elif stat:
            _validate_stat_value(ctx, path, f"{item_field}.{value_field}", stat, value)


def _validate_behaviors(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    behaviors = _require_list(ctx, path, field, data)
    for index, behavior in enumerate(behaviors):
        item_field = f"{field}[{index}]"
        if not isinstance(behavior, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        _require_registered(ctx, path, f"{item_field}.event", behavior.get("event"), "events")
        _require_registered(ctx, path, f"{item_field}.effect", behavior.get("effect"), "effects")
        if not isinstance(behavior.get("params"), dict):
            ctx.error(path, f"{item_field}.params", "must be an object")


def _validate_registered_string_list(
    ctx: ValidationContext,
    path: Path,
    field: str,
    data: Any,
    contract_key: str,
    *,
    allow_empty: bool,
) -> set[str]:
    values = _require_list(ctx, path, field, data)
    if not allow_empty and not values:
        ctx.error(path, field, "must be a non-empty array")
    seen: set[str] = set()
    for index, value in enumerate(values):
        item = _require_registered(ctx, path, f"{field}[{index}]", value, contract_key)
        if item:
            if item in seen:
                ctx.error(path, f"{field}[{index}]", f"duplicate id {item}")
            seen.add(item)
    return seen


def _collect_character_ids(ctx: ValidationContext) -> set[str]:
    data = _load_json(CHARACTERS_JSON, ctx)
    if not isinstance(data, dict):
        return set()
    characters = data.get("characters")
    if not isinstance(characters, list):
        return set()
    return {item.get("id") for item in characters if isinstance(item, dict) and isinstance(item.get("id"), str)}


def _collect_weapon_ids(ctx: ValidationContext) -> set[str]:
    data = _load_json(WEAPONS_JSON, ctx)
    if not isinstance(data, dict):
        return set()
    weapons = data.get("weapons")
    if not isinstance(weapons, list):
        return set()
    return {item.get("id") for item in weapons if isinstance(item, dict) and isinstance(item.get("id"), str)}


def _collect_enemy_ids(ctx: ValidationContext) -> set[str]:
    if not ENEMIES_CSV.exists():
        return set()
    ids: set[str] = set()
    with ENEMIES_CSV.open(encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            enemy_id = row.get("id")
            if isinstance(enemy_id, str) and enemy_id:
                ids.add(enemy_id)
    return ids


def _collect_enemy_ai_profile_ids(ctx: ValidationContext) -> set[str]:
    data = _load_json(ENEMY_AI_PROFILES_JSON, ctx)
    if not isinstance(data, dict):
        return set()
    profiles = data.get("profiles")
    if not isinstance(profiles, list):
        return set()
    return {item.get("id") for item in profiles if isinstance(item, dict) and isinstance(item.get("id"), str)}


def _collect_hazard_ids(ctx: ValidationContext) -> dict[str, int]:
    if not HAZARDS_CSV.exists():
        return {}
    ids: dict[str, int] = {}
    with HAZARDS_CSV.open(encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            hazard_id = row.get("id")
            if isinstance(hazard_id, str) and hazard_id:
                try:
                    radius_tiles = max(int(row.get("radius_tiles", "1")), 1)
                except ValueError:
                    radius_tiles = 1
                ids[hazard_id] = radius_tiles
    return ids


def _collect_relic_ids(ctx: ValidationContext) -> set[str]:
    data = _load_json(RELICS_JSON, ctx)
    if not isinstance(data, dict):
        return set()
    relics = data.get("relics")
    if not isinstance(relics, list):
        return set()
    return {item.get("id") for item in relics if isinstance(item, dict) and isinstance(item.get("id"), str)}


def _collect_active_item_ids(ctx: ValidationContext) -> set[str]:
    data = _load_json(ACTIVE_ITEMS_JSON, ctx)
    if not isinstance(data, dict):
        return set()
    active_items = data.get("active_items")
    if not isinstance(active_items, list):
        return set()
    return {item.get("id") for item in active_items if isinstance(item, dict) and isinstance(item.get("id"), str)}


def _collect_consumable_ids(ctx: ValidationContext) -> set[str]:
    data = _load_json(CONSUMABLES_JSON, ctx)
    if not isinstance(data, dict):
        return set()
    consumables = data.get("consumables")
    if not isinstance(consumables, list):
        return set()
    return {item.get("id") for item in consumables if isinstance(item, dict) and isinstance(item.get("id"), str)}


def _collect_skill_ids(ctx: ValidationContext) -> set[str]:
    data = _load_json(SKILLS_JSON, ctx)
    if not isinstance(data, dict):
        return set()
    skills = data.get("skills")
    if not isinstance(skills, list):
        return set()
    return {item.get("id") for item in skills if isinstance(item, dict) and isinstance(item.get("id"), str)}


def _collect_gear_mod_ids(ctx: ValidationContext) -> set[str]:
    data = _load_json(GEAR_MODS_JSON, ctx)
    if not isinstance(data, dict):
        return set()
    mods = data.get("mods")
    if not isinstance(mods, list):
        return set()
    return {item.get("id") for item in mods if isinstance(item, dict) and isinstance(item.get("id"), str)}


def _collect_gear_mod_rarity_max_ranks(ctx: ValidationContext) -> dict[str, int]:
    data = _load_json(GEAR_MODS_JSON, ctx)
    if not isinstance(data, dict):
        return {}
    mods = data.get("mods")
    if not isinstance(mods, list):
        return {}
    max_ranks: dict[str, int] = {}
    for item in mods:
        if not isinstance(item, dict):
            continue
        rarity = item.get("rarity")
        max_rank = item.get("max_rank")
        if isinstance(rarity, str) and isinstance(max_rank, int) and not isinstance(max_rank, bool):
            max_ranks[rarity] = max(max_ranks.get(rarity, 0), max_rank)
    return max_ranks


def _collect_growth_pool_ids(ctx: ValidationContext) -> set[str]:
    data = _load_json(GROWTH_POOLS_JSON, ctx)
    if not isinstance(data, dict):
        return set()
    pools = data.get("pools")
    if not isinstance(pools, list):
        return set()
    return {item.get("id") for item in pools if isinstance(item, dict) and isinstance(item.get("id"), str)}


def _collect_game_mode_ids(ctx: ValidationContext) -> set[str]:
    data = _load_json(GAME_MODES_JSON, ctx)
    if not isinstance(data, dict):
        return set()
    modes = data.get("modes")
    if not isinstance(modes, list):
        return set()
    return {item.get("id") for item in modes if isinstance(item, dict) and isinstance(item.get("id"), str)}


def _collect_map_layout_ids(ctx: ValidationContext) -> set[str]:
    data = _load_json(MAP_LAYOUTS_JSON, ctx)
    if not isinstance(data, dict):
        return set()
    layouts = data.get("layouts")
    if not isinstance(layouts, list):
        return set()
    return {item.get("id") for item in layouts if isinstance(item, dict) and isinstance(item.get("id"), str)}


def _collect_spawn_wave_ids_by_mode(ctx: ValidationContext) -> dict[str, set[str]]:
    if not SPAWN_WAVES_CSV.exists():
        return {}
    ids_by_mode: dict[str, set[str]] = {}
    with SPAWN_WAVES_CSV.open(encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            mode_id = row.get("mode_id")
            wave_id = row.get("id")
            if not isinstance(mode_id, str) or not mode_id:
                continue
            if not isinstance(wave_id, str) or not wave_id:
                continue
            ids_by_mode.setdefault(mode_id, set()).add(wave_id)
    return ids_by_mode


def _require_registered(ctx: ValidationContext, path: Path, field: str, value: Any, contract_key: str) -> str | None:
    if not isinstance(value, str) or not value:
        ctx.error(path, field, "must be a non-empty string")
        return None
    if value not in ctx.contracts.get(contract_key, []):
        ctx.error(path, field, f"unknown id {value}; expected one of {contract_key}")
        return None
    return value


def _require_non_empty_string(ctx: ValidationContext, path: Path, field: str, value: Any) -> str | None:
    if not isinstance(value, str) or not value:
        ctx.error(path, field, "must be a non-empty string")
        return None
    return value


def _require_bool(ctx: ValidationContext, path: Path, field: str, value: Any) -> bool | None:
    if not isinstance(value, bool):
        ctx.error(path, field, "must be bool")
        return None
    return value


def _require_html_color(ctx: ValidationContext, path: Path, field: str, value: Any) -> str | None:
    if not isinstance(value, str) or not HTML_COLOR_RE.match(value):
        ctx.error(path, field, "must be an HTML color like #ff6152")
        return None
    return value


def _require_audio_id(ctx: ValidationContext, path: Path, field: str, value: Any) -> None:
    if not isinstance(value, str) or not value:
        ctx.error(path, field, "must be a non-empty audio id")
        return
    if not any(value.startswith(prefix) for prefix in ctx.contracts["audio_prefixes"]):
        ctx.error(path, field, f"audio id prefix is not registered: {value}")


def _require_locale_key(ctx: ValidationContext, path: Path, field: str, value: Any) -> None:
    if not isinstance(value, str) or not value:
        ctx.error(path, field, "must be a non-empty locale key")
        return
    if not any(value.startswith(prefix) for prefix in ctx.contracts["locale_prefixes"]):
        ctx.error(path, field, f"locale key prefix is not registered: {value}")
    if ctx.locale_keys and value not in ctx.locale_keys:
        ctx.error(path, field, f"locale key is missing from client/locale/strings.csv: {value}")


def _require_list(ctx: ValidationContext, path: Path, field: str, value: Any) -> list[Any]:
    if not isinstance(value, list):
        ctx.error(path, field, "must be an array")
        return []
    return value


def _require_int(ctx: ValidationContext, path: Path, field: str, value: Any, *, minimum: int | None = None) -> int | None:
    if not isinstance(value, int) or isinstance(value, bool):
        ctx.error(path, field, "must be int")
        return None
    if minimum is not None and value < minimum:
        ctx.error(path, field, f"must be >= {minimum}")
    return value


def _require_number(
    ctx: ValidationContext,
    path: Path,
    field: str,
    value: Any,
    *,
    minimum: float | None = None,
    maximum: float | None = None,
    exclusive_minimum: bool = False,
) -> float | None:
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        ctx.error(path, field, "must be number")
        return None
    numeric = float(value)
    if minimum is not None:
        if exclusive_minimum and numeric <= minimum:
            ctx.error(path, field, f"must be > {minimum}")
        elif not exclusive_minimum and numeric < minimum:
            ctx.error(path, field, f"must be >= {minimum}")
    if maximum is not None and numeric > maximum:
        ctx.error(path, field, f"must be <= {maximum}")
    return numeric


def _is_nearly_grid_multiple(value: float, unit: float) -> bool:
    if unit <= 0.0:
        return True
    return _is_nearly_integer(value / unit)


def _is_nearly_integer(value: float) -> bool:
    return abs(value - round(value)) <= 0.001


def _parse_int(ctx: ValidationContext, path: Path, field: str, value: Any, *, minimum: int | None = None) -> int | None:
    if not isinstance(value, str) or not value:
        ctx.error(path, field, "must be int")
        return None
    try:
        parsed = int(value)
    except ValueError:
        ctx.error(path, field, "must be int")
        return None
    if minimum is not None and parsed < minimum:
        ctx.error(path, field, f"must be >= {minimum}")
    return parsed


def _parse_float(
    ctx: ValidationContext,
    path: Path,
    field: str,
    value: Any,
    *,
    minimum: float | None = None,
    maximum: float | None = None,
    exclusive_minimum: bool = False,
) -> float | None:
    if not isinstance(value, str) or not value:
        ctx.error(path, field, "must be number")
        return None
    try:
        parsed = float(value)
    except ValueError:
        ctx.error(path, field, "must be number")
        return None
    if minimum is not None:
        if exclusive_minimum and parsed <= minimum:
            ctx.error(path, field, f"must be > {minimum}")
        elif not exclusive_minimum and parsed < minimum:
            ctx.error(path, field, f"must be >= {minimum}")
    if maximum is not None and parsed > maximum:
        ctx.error(path, field, f"must be <= {maximum}")
    return parsed


def _parse_pipe_list(value: Any) -> list[str]:
    if not isinstance(value, str):
        return []
    return [item.strip() for item in value.split("|") if item.strip()]


def _load_json(path: Path, ctx: ValidationContext) -> Any:
    if not path.exists():
        ctx.error(path, "$", "file is missing")
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        ctx.error(path, "$", f"invalid JSON: {exc}")
        return None


def _nested(data: dict[str, Any], section: str, field: str) -> Any:
    value = data.get(section)
    if not isinstance(value, dict):
        return None
    return value.get(field)


def _rel(path: Path) -> str:
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return path.as_posix()


if __name__ == "__main__":
    sys.exit(main())
