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
RELICS_JSON = ROOT / "client" / "data" / "relics.json"
GROWTH_CSV = ROOT / "client" / "data" / "growth.csv"
GROWTH_POOLS_JSON = ROOT / "client" / "data" / "growth_pools.json"
GAME_MODES_JSON = ROOT / "client" / "data" / "game_modes.json"
MVP_CONFIG = ROOT / "MinimumViableProduct" / "client" / "data" / "mvp_config.json"
PLACEHOLDER_RE = re.compile(r"\{[a-z0-9_]+\}")
LOCALE_KEY_RE = re.compile(r"^[a-z0-9_]+$")

INT_STATS = {"max_hp", "bullet_count", "pierce_count"}
NON_NEGATIVE_STATS = {"damage", "pickup_range", "luck", "armor", "lifesteal_ratio"}
POSITIVE_STATS = {"move_speed", "fire_rate", "bullet_speed", "bullet_range", "crit_mult"}
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
    _validate_enemies_csv(ctx)
    enemy_ids = _collect_enemy_ids(ctx)
    _validate_relics(ctx)
    relic_ids = _collect_relic_ids(ctx)
    _validate_characters(ctx, weapon_ids)
    character_ids = _collect_character_ids(ctx)
    _validate_meta_progression(ctx, character_ids)
    _validate_growth_csv(ctx)
    _validate_growth_pools(ctx)
    _validate_game_modes(ctx, character_ids, weapon_ids, enemy_ids, relic_ids)
    _validate_mvp_config(ctx)

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
    if MVP_CONFIG.exists():
        paths.append(MVP_CONFIG)
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


def _validate_characters(ctx: ValidationContext, weapon_ids: set[str]) -> None:
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
        starting_weapon_id = _require_non_empty_string(ctx, path, f"{field}.starting_weapon_id", character.get("starting_weapon_id"))
        if starting_weapon_id and starting_weapon_id not in weapon_ids:
            ctx.error(path, f"{field}.starting_weapon_id", f"weapon is not defined in weapons.json: {starting_weapon_id}")
        base_stats = character.get("base_stats")
        if not isinstance(base_stats, dict) or not base_stats:
            ctx.error(path, f"{field}.base_stats", "must be a non-empty object")
            continue
        for stat, value in base_stats.items():
            _validate_stat_value(ctx, path, f"{field}.base_stats.{stat}", stat, value)


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


def _validate_enemies_csv(ctx: ValidationContext) -> None:
    path = ENEMIES_CSV
    if not path.exists():
        ctx.error(path, "$", "missing enemies CSV")
        return

    required = {
        "id",
        "name_key",
        "tags",
        "pool_id",
        "max_hp",
        "move_speed",
        "contact_damage",
        "contact_damage_type",
        "exp_reward",
        "hit_radius",
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
            _parse_int(ctx, path, f"{field}.max_hp", row.get("max_hp"), minimum=1)
            _parse_float(ctx, path, f"{field}.move_speed", row.get("move_speed"), minimum=0, exclusive_minimum=True)
            _parse_int(ctx, path, f"{field}.contact_damage", row.get("contact_damage"), minimum=0)
            _require_registered(ctx, path, f"{field}.contact_damage_type", row.get("contact_damage_type"), "damage_types")
            _parse_int(ctx, path, f"{field}.exp_reward", row.get("exp_reward"), minimum=0)
            _parse_float(ctx, path, f"{field}.hit_radius", row.get("hit_radius"), minimum=0, exclusive_minimum=True)
        if row_count == 0:
            ctx.error(path, "rows", "must contain at least one enemy")


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


def _validate_meta_progression(ctx: ValidationContext, character_ids: set[str]) -> None:
    path = CLIENT_DATA / "meta_progression.json"
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=1)

    currencies = _require_list(ctx, path, "currencies", data.get("currencies"))
    currency_ids = _validate_currencies(ctx, path, currencies)
    _validate_run_rewards(ctx, path, data.get("run_rewards"), currency_ids)
    unlock_ids = _collect_unlock_ids(data.get("unlocks"))
    _validate_account_level(ctx, path, data.get("account_level"), unlock_ids)
    _validate_upgrade_tracks(ctx, path, data.get("upgrade_tracks"), currency_ids, unlock_ids)
    _validate_unlocks(ctx, path, data.get("unlocks"), character_ids)


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


def _validate_game_modes(ctx: ValidationContext, character_ids: set[str], weapon_ids: set[str], enemy_ids: set[str], relic_ids: set[str]) -> None:
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
        _validate_mode_resource_pools(ctx, path, mode_field, mode.get("resource_pools"), growth_pool_ids, character_ids, weapon_ids, enemy_ids, relic_ids)
        if "blocklists" in mode:
            _validate_mode_blocklists(ctx, path, f"{mode_field}.blocklists", mode.get("blocklists"))
        if "overrides" in mode:
            _validate_mode_overrides(ctx, path, f"{mode_field}.overrides", mode.get("overrides"))


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
    relic_ids: set[str],
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
    if "relics" in data:
        _validate_weighted_relic_entries(ctx, path, f"{field}.relics", data.get("relics"), relic_ids)
    if "growth_pools" in data:
        _validate_weighted_growth_pool_entries(ctx, path, f"{field}.growth_pools", data.get("growth_pools"), growth_pool_ids)
    if "characters" not in data and "weapons" not in data and "enemies" not in data and "relics" not in data and "growth_pools" not in data:
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


def _validate_currencies(ctx: ValidationContext, path: Path, currencies: list[Any]) -> set[str]:
    seen: set[str] = set()
    for index, currency in enumerate(currencies):
        field = f"currencies[{index}]"
        if not isinstance(currency, dict):
            ctx.error(path, field, "must be an object")
            continue
        currency_id = _require_registered(ctx, path, f"{field}.id", currency.get("id"), "meta_currencies")
        if currency_id:
            if currency_id in seen:
                ctx.error(path, f"{field}.id", f"duplicate currency id {currency_id}")
            seen.add(currency_id)
        _require_locale_key(ctx, path, f"{field}.name_key", currency.get("name_key"))
        _require_int(ctx, path, f"{field}.default_amount", currency.get("default_amount"), minimum=0)
        max_amount = _require_int(ctx, path, f"{field}.max_amount", currency.get("max_amount"), minimum=1)
        default_amount = currency.get("default_amount")
        if isinstance(default_amount, int) and isinstance(max_amount, int) and max_amount <= default_amount:
            ctx.error(path, f"{field}.max_amount", "must be greater than default_amount")
    return seen


def _validate_run_rewards(ctx: ValidationContext, path: Path, data: Any, currency_ids: set[str]) -> None:
    if not isinstance(data, dict):
        ctx.error(path, "run_rewards", "must be an object")
        return
    currency_id = _require_registered(ctx, path, "run_rewards.currency_id", data.get("currency_id"), "meta_currencies")
    if currency_id and currency_id not in currency_ids:
        ctx.error(path, "run_rewards.currency_id", f"currency is not defined in currencies: {currency_id}")
    for field in ("base_amount", "per_minute_survived", "per_50_kills", "first_boss_bonus"):
        _require_int(ctx, path, f"run_rewards.{field}", data.get(field), minimum=0)
    _require_int(ctx, path, "run_rewards.max_amount_per_run", data.get("max_amount_per_run"), minimum=1)


def _validate_account_level(ctx: ValidationContext, path: Path, data: Any, unlock_ids: set[str]) -> None:
    if not isinstance(data, dict):
        ctx.error(path, "account_level", "must be an object")
        return
    _require_int(ctx, path, "account_level.xp_per_minute_survived", data.get("xp_per_minute_survived"), minimum=0)
    _require_int(ctx, path, "account_level.xp_per_50_kills", data.get("xp_per_50_kills"), minimum=0)
    thresholds = _require_list(ctx, path, "account_level.thresholds", data.get("thresholds"))
    previous = -1
    for index, value in enumerate(thresholds):
        current = _require_int(ctx, path, f"account_level.thresholds[{index}]", value, minimum=0)
        if isinstance(current, int) and current <= previous:
            ctx.error(path, f"account_level.thresholds[{index}]", "must be strictly increasing")
        if isinstance(current, int):
            previous = current
    level_rewards = _require_list(ctx, path, "account_level.level_rewards", data.get("level_rewards"))
    for index, reward in enumerate(level_rewards):
        field = f"account_level.level_rewards[{index}]"
        if not isinstance(reward, dict):
            ctx.error(path, field, "must be an object")
            continue
        level = _require_int(ctx, path, f"{field}.level", reward.get("level"), minimum=1)
        if isinstance(level, int) and thresholds and level > len(thresholds):
            ctx.error(path, f"{field}.level", "must not exceed threshold count")
        _validate_unlock_id_list(ctx, path, f"{field}.unlock_ids", reward.get("unlock_ids"), unlock_ids)


def _validate_upgrade_tracks(ctx: ValidationContext, path: Path, data: Any, currency_ids: set[str], unlock_ids: set[str]) -> None:
    tracks = _require_list(ctx, path, "upgrade_tracks", data)
    seen: set[str] = set()
    for index, track in enumerate(tracks):
        field = f"upgrade_tracks[{index}]"
        if not isinstance(track, dict):
            ctx.error(path, field, "must be an object")
            continue
        track_id = _require_registered(ctx, path, f"{field}.id", track.get("id"), "meta_upgrades")
        if track_id:
            if track_id in seen:
                ctx.error(path, f"{field}.id", f"duplicate upgrade id {track_id}")
            seen.add(track_id)
        _require_locale_key(ctx, path, f"{field}.name_key", track.get("name_key"))
        _require_locale_key(ctx, path, f"{field}.desc_key", track.get("desc_key"))
        currency_id = _require_registered(ctx, path, f"{field}.currency_id", track.get("currency_id"), "meta_currencies")
        if currency_id and currency_id not in currency_ids:
            ctx.error(path, f"{field}.currency_id", f"currency is not defined in currencies: {currency_id}")
        max_level = _require_int(ctx, path, f"{field}.max_level", track.get("max_level"), minimum=1)
        costs = _require_list(ctx, path, f"{field}.costs", track.get("costs"))
        if isinstance(max_level, int) and len(costs) != max_level:
            ctx.error(path, f"{field}.costs", "length must equal max_level")
        for cost_index, cost in enumerate(costs):
            _require_int(ctx, path, f"{field}.costs[{cost_index}]", cost, minimum=0)
        _validate_modifiers(ctx, path, f"{field}.modifiers", track.get("modifiers", []), require_value_per_level=True)
        if "unlock_ids_by_level" in track:
            by_level = _require_list(ctx, path, f"{field}.unlock_ids_by_level", track.get("unlock_ids_by_level"))
            if isinstance(max_level, int) and len(by_level) != max_level:
                ctx.error(path, f"{field}.unlock_ids_by_level", "length must equal max_level")
            for level_index, ids in enumerate(by_level):
                _validate_unlock_id_list(ctx, path, f"{field}.unlock_ids_by_level[{level_index}]", ids, unlock_ids)
        condition = track.get("unlock_condition")
        if condition is not None:
            if not isinstance(condition, dict):
                ctx.error(path, f"{field}.unlock_condition", "must be an object")
            elif "account_level" in condition:
                _require_int(ctx, path, f"{field}.unlock_condition.account_level", condition.get("account_level"), minimum=1)


def _validate_unlocks(ctx: ValidationContext, path: Path, data: Any, character_ids: set[str]) -> None:
    unlocks = _require_list(ctx, path, "unlocks", data)
    seen: set[str] = set()
    for index, unlock in enumerate(unlocks):
        field = f"unlocks[{index}]"
        if not isinstance(unlock, dict):
            ctx.error(path, field, "must be an object")
            continue
        unlock_id = _require_registered(ctx, path, f"{field}.id", unlock.get("id"), "meta_unlocks")
        if unlock_id:
            if unlock_id in seen:
                ctx.error(path, f"{field}.id", f"duplicate unlock id {unlock_id}")
            seen.add(unlock_id)
        _require_registered(ctx, path, f"{field}.kind", unlock.get("kind"), "meta_unlock_kinds")
        if "target_id" in unlock:
            target_id = unlock.get("target_id")
            if not isinstance(target_id, str) or not target_id:
                ctx.error(path, f"{field}.target_id", "must be a non-empty string")
            elif unlock.get("kind") == "character" and target_id not in character_ids:
                ctx.error(path, f"{field}.target_id", f"character is not defined in characters.json: {target_id}")
        if "name_key" in unlock:
            _require_locale_key(ctx, path, f"{field}.name_key", unlock.get("name_key"))
        if not isinstance(unlock.get("default_unlocked"), bool):
            ctx.error(path, f"{field}.default_unlocked", "must be bool")


def _validate_mvp_config(ctx: ValidationContext) -> None:
    path = MVP_CONFIG
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    required_sections = ["player", "input", "weapon", "enemy", "spawner", "background"]
    for section in required_sections:
        if not isinstance(data.get(section), dict):
            ctx.error(path, section, "must be an object")
    _require_int(ctx, path, "player.max_hp", _nested(data, "player", "max_hp"), minimum=1)
    _require_number(ctx, path, "player.damage_flash_seconds", _nested(data, "player", "damage_flash_seconds"), minimum=0)
    _require_number(ctx, path, "input.gamepad_deadzone", _nested(data, "input", "gamepad_deadzone"), minimum=0, maximum=1)
    for field in ("fire_interval", "bullet_speed", "bullet_lifetime", "bullet_hitbox_radius", "muzzle_distance"):
        _require_number(ctx, path, f"weapon.{field}", _nested(data, "weapon", field), minimum=0, exclusive_minimum=True)
    _require_int(ctx, path, "weapon.bullet_damage", _nested(data, "weapon", "bullet_damage"), minimum=1)
    _require_number(ctx, path, "enemy.move_speed", _nested(data, "enemy", "move_speed"), minimum=0, exclusive_minimum=True)
    _require_int(ctx, path, "enemy.hp", _nested(data, "enemy", "hp"), minimum=1)
    _require_int(ctx, path, "enemy.contact_damage", _nested(data, "enemy", "contact_damage"), minimum=0)
    for field in ("hit_radius", "collision_radius"):
        _require_number(ctx, path, f"enemy.{field}", _nested(data, "enemy", field), minimum=0, exclusive_minimum=True)
    for field in ("spawn_interval", "spawn_margin"):
        _require_number(ctx, path, f"spawner.{field}", _nested(data, "spawner", field), minimum=0, exclusive_minimum=True)
    _require_number(ctx, path, "spawner.initial_cooldown", _nested(data, "spawner", "initial_cooldown"), minimum=0)
    _require_int(ctx, path, "background.grid_size", _nested(data, "background", "grid_size"), minimum=1)
    for field in ("lane_width", "center_outer_radius", "center_inner_radius", "center_mark_inner", "center_mark_outer"):
        _require_number(ctx, path, f"background.{field}", _nested(data, "background", field), minimum=0, exclusive_minimum=True)


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


def _validate_unlock_id_list(ctx: ValidationContext, path: Path, field: str, data: Any, defined_unlock_ids: set[str]) -> None:
    unlock_ids = _require_list(ctx, path, field, data)
    for index, unlock_id in enumerate(unlock_ids):
        value = _require_registered(ctx, path, f"{field}[{index}]", unlock_id, "meta_unlocks")
        if value and value not in defined_unlock_ids:
            ctx.error(path, f"{field}[{index}]", f"unlock is not defined in unlocks: {value}")


def _collect_unlock_ids(data: Any) -> set[str]:
    if not isinstance(data, list):
        return set()
    return {item.get("id") for item in data if isinstance(item, dict) and isinstance(item.get("id"), str)}


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


def _collect_relic_ids(ctx: ValidationContext) -> set[str]:
    data = _load_json(RELICS_JSON, ctx)
    if not isinstance(data, dict):
        return set()
    relics = data.get("relics")
    if not isinstance(relics, list):
        return set()
    return {item.get("id") for item in relics if isinstance(item, dict) and isinstance(item.get("id"), str)}


def _collect_growth_pool_ids(ctx: ValidationContext) -> set[str]:
    data = _load_json(GROWTH_POOLS_JSON, ctx)
    if not isinstance(data, dict):
        return set()
    pools = data.get("pools")
    if not isinstance(pools, list):
        return set()
    return {item.get("id") for item in pools if isinstance(item, dict) and isinstance(item.get("id"), str)}


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
