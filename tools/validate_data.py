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
MVP_CONFIG = ROOT / "MinimumViableProduct" / "client" / "data" / "mvp_config.json"
PLACEHOLDER_RE = re.compile(r"\{[a-z0-9_]+\}")
LOCALE_KEY_RE = re.compile(r"^[a-z0-9_]+$")

INT_STATS = {"max_hp", "bullet_count", "pierce_count"}
NON_NEGATIVE_STATS = {"damage", "pickup_range", "luck", "armor", "lifesteal_ratio"}
POSITIVE_STATS = {"move_speed", "fire_rate", "bullet_speed", "bullet_range", "crit_mult"}
RATIO_STATS = {"crit_chance", "resist_fire", "resist_poison", "resist_lightning", "lifesteal_ratio"}


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
    _validate_meta_progression(ctx)
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


def _validate_meta_progression(ctx: ValidationContext) -> None:
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
    _validate_unlocks(ctx, path, data.get("unlocks"))


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


def _validate_unlocks(ctx: ValidationContext, path: Path, data: Any) -> None:
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
            elif unlock.get("kind") == "character" and target_id not in ctx.contracts["character_ids"]:
                ctx.error(path, f"{field}.target_id", f"unknown character id {target_id}")
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


def _require_registered(ctx: ValidationContext, path: Path, field: str, value: Any, contract_key: str) -> str | None:
    if not isinstance(value, str) or not value:
        ctx.error(path, field, "must be a non-empty string")
        return None
    if value not in ctx.contracts.get(contract_key, []):
        ctx.error(path, field, f"unknown id {value}; expected one of {contract_key}")
        return None
    return value


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
