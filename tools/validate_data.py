#!/usr/bin/env python3
"""Validate project data, locale CSV, and generated contracts."""

from __future__ import annotations

import csv
import json
import math
import re
import sys
from pathlib import Path
from typing import Any

from sync_contracts import CONTRACTS_JSON, ROOT, extract_contracts


CLIENT_DATA = ROOT / "client" / "data"
LOCALE_CSV = ROOT / "client" / "locale" / "strings.csv"
CAMERA_FEEDBACK_JSON = ROOT / "client" / "data" / "camera_feedback.json"
VISUAL_EFFECTS_JSON = ROOT / "client" / "data" / "visual_effects.json"
PRESENTATION_PROFILES_JSON = ROOT / "client" / "data" / "presentation_profiles.json"
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
ELEMENTS_JSON = ROOT / "client" / "data" / "elements.json"
HERO_PASSIVES_JSON = ROOT / "client" / "data" / "hero_passives.json"
CREDITS_JSON = ROOT / "client" / "data" / "credits.json"
LEVEL_PROGRESSION_JSON = ROOT / "client" / "data" / "level_progression.json"
REWARD_CHOICE_POOLS_JSON = ROOT / "client" / "data" / "reward_choice_pools.json"
DIFFICULTY_PROFILES_JSON = ROOT / "client" / "data" / "difficulty_profiles.json"
ENEMY_REWARDS_JSON = ROOT / "client" / "data" / "enemy_rewards.json"
GAME_MODES_JSON = ROOT / "client" / "data" / "game_modes.json"
MAP_LAYOUTS_JSON = ROOT / "client" / "data" / "map_layouts.json"
WARZONE_DIRECTORS_JSON = ROOT / "client" / "data" / "warzone_directors.json"
MODULE_WORLDS_JSON = ROOT / "client" / "data" / "module_worlds.json"
MODULE_TEMPLATES_JSON = ROOT / "client" / "data" / "module_templates.json"
MODULE_TILE_CATALOG_JSON = ROOT / "client" / "data" / "module_tile_catalog.json"
MODULES_DIR = ROOT / "client" / "data" / "modules"
GEAR_MODS_JSON = ROOT / "client" / "data" / "gear_mods.json"
WORLD_EVENTS_JSON = ROOT / "client" / "data" / "world_events.json"
GEAR_MOD_DROP_TABLES_CSV = ROOT / "client" / "data" / "gear_mod_drop_tables.csv"
CONTENT_UNLOCK_RULES_JSON = ROOT / "client" / "data" / "content_unlock_rules.json"
PLACEHOLDER_RE = re.compile(r"\{[a-z0-9_]+\}")
LOCALE_KEY_RE = re.compile(r"^[a-z0-9_]+$")
HTML_COLOR_RE = re.compile(r"^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$")

INT_STATS = {"bullet_count", "pierce_count"}
WEAPON_RECOIL_MAXIMUM = 100.0
WEAPON_BASE_SPREAD_CAP_MAXIMUM = 60.0
WEAPON_RUNTIME_SPREAD_CAP_MAXIMUM = 180.0
NON_NEGATIVE_STATS = {
    "damage",
    "health_regen",
    "player_separation_radius",
    "pickup_range",
    "luck",
    "armor",
    "max_shield",
    "lifesteal_ratio",
    "wall_pierce",
    "recoil",
    "spread_angle_max",
}
POSITIVE_STATS = {
    "max_hp",
    "max_energy",
    "move_speed",
    "fire_rate",
    "bullet_speed",
    "bullet_range",
    "crit_mult",
    "ability_strength",
    "ability_range",
    "ability_efficiency",
    "ability_duration",
}
RATIO_STATS = {"crit_chance", "lifesteal_ratio"}
WEAPON_STATS = {
    "damage",
    "fire_rate",
    "bullet_speed",
    "bullet_range",
    "bullet_count",
    "pierce_count",
    "wall_pierce",
    "recoil",
    "spread_angle_max",
    "crit_chance",
    "crit_mult",
}
REQUIRED_WEAPON_STATS = {
    "damage",
    "fire_rate",
    "bullet_speed",
    "bullet_range",
    "bullet_count",
    "recoil",
    "spread_angle_max",
}


class ValidationContext:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.locale_keys: set[str] = set()
        self.locale_placeholders: dict[str, set[str]] = {}
        self.contracts = _load_contracts()

    def error(self, path: Path, field: str, message: str) -> None:
        self.errors.append(f"{_rel(path)}:{field}: {message}")


def main() -> int:
    ctx = ValidationContext()

    _validate_contracts_file(ctx)
    _validate_all_json(ctx)
    _validate_locale_csv(ctx)
    _validate_player_json(ctx)
    element_ids = _validate_elements(ctx)
    passive_ids = _validate_hero_passives(ctx, element_ids)
    camera_feedback_ids = _validate_camera_feedback(ctx)
    effect_ids = _validate_visual_effects(ctx)
    profile_ids = _validate_presentation_profiles(
        ctx, effect_ids, camera_feedback_ids
    )
    _validate_presentation_profile_references(ctx, profile_ids)
    _validate_weapons(ctx)
    weapon_ids = _collect_weapon_ids(ctx)
    _validate_enemy_ai_profiles(ctx)
    enemy_ai_profile_ids = _collect_enemy_ai_profile_ids(ctx)
    _validate_enemy_rewards(ctx)
    _validate_enemies_csv(ctx, enemy_ai_profile_ids)
    enemy_ids = _collect_enemy_ids(ctx)
    _validate_gear_mods(ctx)
    gear_mod_ids = _collect_gear_mod_ids(ctx)
    world_event_ids = _validate_world_events(ctx, gear_mod_ids)
    _validate_gear_mod_drop_tables(ctx, enemy_ids, gear_mod_ids)
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
    _validate_characters(ctx, weapon_ids, active_item_ids, consumable_ids, skill_ids, passive_ids, element_ids)
    character_ids = _collect_character_ids(ctx)
    _validate_content_unlocks(ctx, character_ids, gear_mod_ids, enemy_ids)
    _validate_level_progression(ctx)
    _validate_reward_choice_pools(ctx)
    difficulty_profile_ids = _validate_difficulty_profiles(ctx)
    _validate_game_modes(ctx, character_ids, weapon_ids, enemy_ids, hazard_ids, relic_ids, active_item_ids, consumable_ids, skill_ids, difficulty_profile_ids)
    game_mode_ids = _collect_game_mode_ids(ctx)
    _validate_map_layouts(ctx, hazard_ids, game_mode_ids)
    _validate_spawn_waves_csv(ctx, enemy_ids, hazard_ids, game_mode_ids)
    _validate_warzone_directors(ctx, game_mode_ids, _collect_spawn_wave_ids_by_mode(ctx), hazard_ids, _collect_map_layout_ids(ctx))
    module_tile_catalog = _validate_module_tile_catalog(ctx)
    _validate_module_world_data(
        ctx,
        enemy_ids,
        set(hazard_ids),
        world_event_ids,
        module_tile_catalog,
    )

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
                ctx.locale_placeholders[key] = baseline
                for locale, placeholders in placeholder_sets[1:]:
                    if placeholders != baseline:
                        ctx.error(LOCALE_CSV, f"line {line_number}", f"placeholder mismatch for {key}: {locale}")


def _validate_player_json(ctx: ValidationContext) -> None:
    path = CLIENT_DATA / "player.json"
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    schema_version = _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=4)
    if schema_version != 4:
        ctx.error(path, "schema_version", "must equal 4")
    body = data.get("body")
    if not isinstance(body, dict):
        ctx.error(path, "body", "must be an object")
    else:
        if set(body) != {"radius"}:
            ctx.error(path, "body", "must contain exactly ['radius']")
        _require_number(
            ctx,
            path,
            "body.radius",
            body.get("radius"),
            minimum=0,
            exclusive_minimum=True,
        )
    base_stats = data.get("base_stats")
    if not isinstance(base_stats, dict) or not base_stats:
        ctx.error(path, "base_stats", "must be a non-empty object")
        return
    if "damage_invulnerability_duration" in base_stats:
        ctx.error(path, "base_stats.damage_invulnerability_duration", "was removed in schema_version 2; use dash.invulnerability_duration or defense.shield_gate")
    if "pickup_orb_speed" in base_stats:
        ctx.error(path, "base_stats.pickup_orb_speed", "was removed in schema_version 3; use gold_drop.pickup_speed and energy_drop.pickup_speed")
    for stat, value in base_stats.items():
        _validate_stat_value(ctx, path, f"base_stats.{stat}", stat, value)
    defense = data.get("defense")
    if not isinstance(defense, dict):
        ctx.error(path, "defense", "must be an object")
    else:
        shield = defense.get("shield")
        if not isinstance(shield, dict):
            ctx.error(path, "defense.shield", "must be an object")
        else:
            _require_number(ctx, path, "defense.shield.recharge_delay", shield.get("recharge_delay"), minimum=0)
            _require_number(ctx, path, "defense.shield.recharge_rate", shield.get("recharge_rate"), minimum=0)
            _require_number(ctx, path, "defense.shield.overshield_decay_ratio_per_second", shield.get("overshield_decay_ratio_per_second"), minimum=0, maximum=1)
            _require_number(ctx, path, "defense.shield.overshield_snap_threshold", shield.get("overshield_snap_threshold"), minimum=0)
        armor = defense.get("armor")
        if not isinstance(armor, dict):
            ctx.error(path, "defense.armor", "must be an object")
        else:
            _require_number(ctx, path, "defense.armor.coefficient", armor.get("coefficient"), minimum=0, exclusive_minimum=True)
            _require_number(ctx, path, "defense.armor.maximum", armor.get("maximum"), minimum=0, exclusive_minimum=True)
        shield_gate = defense.get("shield_gate")
        if not isinstance(shield_gate, dict):
            ctx.error(path, "defense.shield_gate", "must be an object")
        else:
            _require_number(ctx, path, "defense.shield_gate.max_duration", shield_gate.get("max_duration"), minimum=0)
    dash = data.get("dash")
    if not isinstance(dash, dict):
        ctx.error(path, "dash", "must be an object")
    else:
        distance = _require_number(ctx, path, "dash.distance", dash.get("distance"), minimum=0, exclusive_minimum=True)
        speed = _require_number(ctx, path, "dash.speed", dash.get("speed"), minimum=0, exclusive_minimum=True)
        duration = _require_number(ctx, path, "dash.duration", dash.get("duration"), minimum=0, exclusive_minimum=True)
        _require_number(ctx, path, "dash.cooldown", dash.get("cooldown"), minimum=0)
        invulnerability = _require_number(ctx, path, "dash.invulnerability_duration", dash.get("invulnerability_duration"), minimum=0)
        if isinstance(invulnerability, float) and isinstance(duration, float) and invulnerability > duration:
            ctx.error(path, "dash.invulnerability_duration", "must be <= dash.duration")
        if isinstance(distance, float) and isinstance(speed, float) and isinstance(duration, float):
            if abs(distance - speed * duration) > 0.001:
                ctx.error(path, "dash.distance", "must equal dash.speed * dash.duration")
    energy_drop = data.get("energy_drop")
    if not isinstance(energy_drop, dict):
        ctx.error(path, "energy_drop", "must be an object")
    else:
        _require_number(ctx, path, "energy_drop.chance", energy_drop.get("chance"), minimum=0, maximum=1)
        _require_number(ctx, path, "energy_drop.amount", energy_drop.get("amount"), minimum=0, exclusive_minimum=True)
        _require_number(ctx, path, "energy_drop.pickup_speed", energy_drop.get("pickup_speed"), minimum=0, exclusive_minimum=True)
        _require_registered(ctx, path, "energy_drop.pool_id", energy_drop.get("pool_id"), "pool_ids")
        _require_registered(ctx, path, "energy_drop.rng_stream", energy_drop.get("rng_stream"), "rng_streams")
    gold_drop = data.get("gold_drop")
    if not isinstance(gold_drop, dict):
        ctx.error(path, "gold_drop", "must be an object")
    else:
        _require_number(ctx, path, "gold_drop.pickup_speed", gold_drop.get("pickup_speed"), minimum=0, exclusive_minimum=True)
        gold_pool_id = _require_registered(ctx, path, "gold_drop.pool_id", gold_drop.get("pool_id"), "pool_ids")
        if gold_pool_id != "gold_orb":
            ctx.error(path, "gold_drop.pool_id", "must equal gold_orb")


def _validate_elements(ctx: ValidationContext) -> set[str]:
    path = ELEMENTS_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return set()
    schema_version = _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=1)
    if schema_version != 1:
        ctx.error(path, "schema_version", "must equal 1")
    neutral_id = _require_registered(ctx, path, "neutral_element_id", data.get("neutral_element_id"), "elements")
    unmatched_result = data.get("unmatched_result")
    if not isinstance(unmatched_result, str):
        ctx.error(path, "unmatched_result", "must be a string")
    elements = _require_list(ctx, path, "elements", data.get("elements"))
    seen: set[str] = set()
    kinds: dict[str, str] = {}
    for index, element in enumerate(elements):
        field = f"elements[{index}]"
        if not isinstance(element, dict):
            ctx.error(path, field, "must be an object")
            continue
        element_id = _require_registered(ctx, path, f"{field}.id", element.get("id"), "elements")
        if element_id:
            if element_id in seen:
                ctx.error(path, f"{field}.id", f"duplicate element id {element_id}")
            seen.add(element_id)
        _require_locale_key(ctx, path, f"{field}.name_key", element.get("name_key"))
        kind = element.get("kind")
        if kind not in {"neutral", "primary", "composite"}:
            ctx.error(path, f"{field}.kind", "must be neutral, primary, or composite")
        elif element_id:
            kinds[element_id] = kind
        components = _validate_registered_string_list(ctx, path, f"{field}.components", element.get("components"), "elements", allow_empty=True)
        expected_count = {"neutral": 0, "primary": 1, "composite": 2}.get(kind)
        if expected_count is not None and len(components) != expected_count:
            ctx.error(path, f"{field}.components", f"must contain exactly {expected_count} element ids for kind {kind}")
        if kind == "primary" and element_id and components != {element_id}:
            ctx.error(path, f"{field}.components", "primary element must contain only itself")
    contract_ids = set(ctx.contracts.get("elements", []))
    if seen != contract_ids:
        ctx.error(path, "elements", f"ids must exactly match elements contract; missing={sorted(contract_ids - seen)} extra={sorted(seen - contract_ids)}")
    if neutral_id and kinds.get(neutral_id) != "neutral":
        ctx.error(path, "neutral_element_id", "must reference the neutral element")
    combinations = _require_list(ctx, path, "combinations", data.get("combinations"))
    pair_keys: set[tuple[str, str]] = set()
    results: set[str] = set()
    for index, combination in enumerate(combinations):
        field = f"combinations[{index}]"
        if not isinstance(combination, dict):
            ctx.error(path, field, "must be an object")
            continue
        left = _require_registered(ctx, path, f"{field}.left", combination.get("left"), "elements")
        right = _require_registered(ctx, path, f"{field}.right", combination.get("right"), "elements")
        result = _require_registered(ctx, path, f"{field}.result", combination.get("result"), "elements")
        if not left or not right or not result:
            continue
        pair = tuple(sorted((left, right)))
        if pair in pair_keys:
            ctx.error(path, field, "duplicate symmetric combination")
        pair_keys.add(pair)
        if left == right or left == neutral_id or right == neutral_id:
            ctx.error(path, field, "only distinct non-neutral primary pairs belong in the explicit table")
        if kinds.get(left) != "primary" or kinds.get(right) != "primary":
            ctx.error(path, field, "combination inputs must be primary elements")
        if kinds.get(result) != "composite":
            ctx.error(path, f"{field}.result", "must be a composite element")
        results.add(result)
    composite_ids = {element_id for element_id, kind in kinds.items() if kind == "composite"}
    if results != composite_ids:
        ctx.error(path, "combinations", "must produce every composite element exactly once")
    return seen


def _validate_hero_passives(ctx: ValidationContext, element_ids: set[str]) -> set[str]:
    path = HERO_PASSIVES_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return set()
    schema_version = _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=1)
    if schema_version != 1:
        ctx.error(path, "schema_version", "must equal 1")
    passives = _require_list(ctx, path, "passives", data.get("passives"))
    seen: set[str] = set()
    for index, passive in enumerate(passives):
        field = f"passives[{index}]"
        if not isinstance(passive, dict):
            ctx.error(path, field, "must be an object")
            continue
        passive_id = _require_registered(ctx, path, f"{field}.id", passive.get("id"), "hero_passive_ids")
        if passive_id:
            if passive_id in seen:
                ctx.error(path, f"{field}.id", f"duplicate hero passive id {passive_id}")
            seen.add(passive_id)
        _require_locale_key(ctx, path, f"{field}.name_key", passive.get("name_key"))
        desc_key = passive.get("desc_key")
        _require_locale_key(ctx, path, f"{field}.desc_key", desc_key)
        effect_id = _require_registered(ctx, path, f"{field}.effect", passive.get("effect"), "effects")
        params = passive.get("params")
        if not isinstance(params, dict):
            ctx.error(path, f"{field}.params", "must be an object")
            continue
        _validate_description_placeholders(
            ctx,
            path,
            f"{field}.desc_key",
            desc_key,
            _numeric_description_tokens("param", params),
        )
        if effect_id == "element_damage_taken_multiplier":
            element_id = _require_registered(ctx, path, f"{field}.params.element_id", params.get("element_id"), "elements")
            if element_id and element_id not in element_ids:
                ctx.error(path, f"{field}.params.element_id", f"element is not defined in elements.json: {element_id}")
            _require_number(ctx, path, f"{field}.params.multiplier", params.get("multiplier"), minimum=0)
    contract_ids = set(ctx.contracts.get("hero_passive_ids", []))
    if seen != contract_ids:
        ctx.error(path, "passives", f"ids must exactly match hero_passive_ids contract; missing={sorted(contract_ids - seen)} extra={sorted(seen - contract_ids)}")
    return seen


def _validate_visual_effects(ctx: ValidationContext) -> set[str]:
    path = VISUAL_EFFECTS_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return set()
    schema_version = _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=1)
    if schema_version != 3:
        ctx.error(path, "schema_version", "must equal 3")
    effects = _require_list(ctx, path, "effects", data.get("effects"))
    if not effects:
        ctx.error(path, "effects", "must be a non-empty array")

    effect_ids: set[str] = set()
    for index, effect in enumerate(effects):
        field = f"effects[{index}]"
        if not isinstance(effect, dict):
            ctx.error(path, field, "must be an object")
            continue
        effect_id = _require_non_empty_string(ctx, path, f"{field}.id", effect.get("id"))
        if effect_id:
            if effect_id in effect_ids:
                ctx.error(path, f"{field}.id", f"duplicate effect id {effect_id}")
            effect_ids.add(effect_id)
        _require_non_empty_string(ctx, path, f"{field}.editor_name", effect.get("editor_name"))
        _require_registered(ctx, path, f"{field}.domain", effect.get("domain"), "vfx_domains")
        kind = _require_registered(ctx, path, f"{field}.kind", effect.get("kind"), "vfx_kinds")
        _require_registered(ctx, path, f"{field}.space", effect.get("space"), "vfx_spaces")
        _require_registered(ctx, path, f"{field}.lifecycle", effect.get("lifecycle"), "vfx_lifecycles")
        _require_number(ctx, path, f"{field}.duration", effect.get("duration"), minimum=0)
        high_frequency = _require_bool(ctx, path, f"{field}.high_frequency", effect.get("high_frequency"))

        resource_path = _require_non_empty_string(
            ctx, path, f"{field}.resource_path", effect.get("resource_path")
        )
        if resource_path:
            _validate_vfx_resource_path(ctx, path, f"{field}.resource_path", resource_path, kind or "")

        pool_id = effect.get("pool_id", "")
        if high_frequency is True and not pool_id:
            ctx.error(path, f"{field}.pool_id", "is required for high-frequency effects")
        if pool_id:
            _require_registered(ctx, path, f"{field}.pool_id", pool_id, "pool_ids")
            _require_int(ctx, path, f"{field}.prewarm", effect.get("prewarm", 0), minimum=0)
        if "quality_variants" in effect:
            ctx.error(path, f"{field}.quality_variants", "field was removed in schema v3")
        if "reduced_motion" in effect:
            ctx.error(path, f"{field}.reduced_motion", "field was removed in schema v2")
        tags = _require_list(ctx, path, f"{field}.tags", effect.get("tags"))
        for tag_index, tag in enumerate(tags):
            _require_non_empty_string(ctx, path, f"{field}.tags[{tag_index}]", tag)
        if not isinstance(effect.get("preview"), dict):
            ctx.error(path, f"{field}.preview", "must be an object")

    return effect_ids


def _validate_vfx_resource_path(
    ctx: ValidationContext,
    data_path: Path,
    field: str,
    resource_path: str,
    kind: str,
) -> None:
    if (
        not resource_path.startswith("res://")
        or "\\" in resource_path
        or "/../" in resource_path
        or resource_path.startswith("res://addons/")
        or resource_path.startswith("res://scripts/editor/")
        or "output/test_lab" in resource_path
        or "/modules/geometry/" in resource_path
    ):
        ctx.error(data_path, field, "must be a runtime path outside editor/test/raw geometry modules")
        return
    local_path = ROOT / "client" / resource_path.removeprefix("res://")
    if not local_path.is_file():
        ctx.error(data_path, field, f"resource does not exist: {resource_path}")
        return
    if kind == "target_animation" and local_path.suffix not in {".tres", ".res"}:
        ctx.error(data_path, field, "target_animation must reference .tres or .res")
    if kind != "target_animation" and local_path.suffix != ".tscn":
        ctx.error(data_path, field, "spawned and screen effects must reference .tscn")


def _validate_presentation_profiles(
    ctx: ValidationContext,
    effect_ids: set[str],
    camera_feedback_ids: set[str],
) -> set[str]:
    path = PRESENTATION_PROFILES_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return set()
    schema_version = _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=1)
    if schema_version != 1:
        ctx.error(path, "schema_version", "must equal 1")
    profiles = _require_list(ctx, path, "profiles", data.get("profiles"))
    if not profiles:
        ctx.error(path, "profiles", "must be a non-empty array")

    profile_ids: set[str] = set()
    parents: dict[str, str] = {}
    for index, profile in enumerate(profiles):
        field = f"profiles[{index}]"
        if not isinstance(profile, dict):
            ctx.error(path, field, "must be an object")
            continue
        profile_id = _require_non_empty_string(ctx, path, f"{field}.id", profile.get("id"))
        if profile_id:
            if profile_id in profile_ids:
                ctx.error(path, f"{field}.id", f"duplicate profile id {profile_id}")
            profile_ids.add(profile_id)
            parents[profile_id] = profile.get("parent_profile_id", "")
        bindings = profile.get("bindings")
        if not isinstance(bindings, dict):
            ctx.error(path, f"{field}.bindings", "must be an object")
            continue
        for cue, binding in bindings.items():
            _require_registered(ctx, path, f"{field}.bindings.{cue}", cue, "vfx_cues")
            if not isinstance(binding, dict):
                ctx.error(path, f"{field}.bindings.{cue}", "must be an object")
                continue
            _validate_presentation_binding(
                ctx,
                path,
                f"{field}.bindings.{cue}",
                binding,
                effect_ids,
                camera_feedback_ids,
            )

    for profile_id, parent_id in parents.items():
        if parent_id and parent_id not in profile_ids:
            ctx.error(
                path,
                f"{profile_id}.parent_profile_id",
                f"unknown parent profile {parent_id}",
            )
        visiting: set[str] = set()
        cursor = profile_id
        while cursor:
            if cursor in visiting:
                ctx.error(
                    path,
                    f"{profile_id}.parent_profile_id",
                    "profile inheritance must be acyclic",
                )
                break
            visiting.add(cursor)
            cursor = parents.get(cursor, "")
    return profile_ids


def _validate_presentation_binding(
    ctx: ValidationContext,
    path: Path,
    field: str,
    binding: dict[str, Any],
    effect_ids: set[str],
    camera_feedback_ids: set[str],
) -> None:
    effects = _require_list(ctx, path, f"{field}.effects", binding.get("effects"))
    for index, effect in enumerate(effects):
        effect_field = f"{field}.effects[{index}]"
        if not isinstance(effect, dict):
            ctx.error(path, effect_field, "must be an object")
            continue
        effect_id = _require_non_empty_string(
            ctx, path, f"{effect_field}.effect_id", effect.get("effect_id")
        )
        if effect_id and effect_id not in effect_ids:
            ctx.error(path, f"{effect_field}.effect_id", f"unknown effect id {effect_id}")
        _require_registered(
            ctx, path, f"{effect_field}.anchor", effect.get("anchor"), "vfx_anchors"
        )
        if "params" in effect and not isinstance(effect["params"], dict):
            ctx.error(path, f"{effect_field}.params", "must be an object")
    for key in (
        "audio_id",
        "camera_feedback_id",
        "screen_effect_id",
        "hit_stop_profile_id",
    ):
        if not isinstance(binding.get(key, ""), str):
            ctx.error(path, f"{field}.{key}", "must be a string")
    audio_id = binding.get("audio_id", "")
    if audio_id:
        _require_audio_id(ctx, path, f"{field}.audio_id", audio_id)
    camera_feedback_id = binding.get("camera_feedback_id", "")
    if camera_feedback_id and camera_feedback_id not in camera_feedback_ids:
        ctx.error(
            path,
            f"{field}.camera_feedback_id",
            "must reference a profile in camera_feedback.json",
        )
    screen_effect_id = binding.get("screen_effect_id", "")
    if screen_effect_id and screen_effect_id not in effect_ids:
        ctx.error(path, f"{field}.screen_effect_id", "must reference a catalog effect")
    if binding.get("hit_stop_profile_id"):
        ctx.error(path, f"{field}.hit_stop_profile_id", "must be empty in schema v1")


def _validate_presentation_profile_references(
    ctx: ValidationContext, profile_ids: set[str]
) -> None:
    required_json = (
        (CHARACTERS_JSON, "characters"),
        (WEAPONS_JSON, "weapons"),
        (SKILLS_JSON, "skills"),
    )
    optional_json = (
        (RELICS_JSON, "relics"),
        (ACTIVE_ITEMS_JSON, "active_items"),
        (CONSUMABLES_JSON, "consumables"),
    )
    for path, root_key in required_json + optional_json:
        data = _load_json(path, ctx)
        if not isinstance(data, dict):
            continue
        rows = data.get(root_key)
        if not isinstance(rows, list):
            continue
        required = (path, root_key) in required_json
        for index, row in enumerate(rows):
            if not isinstance(row, dict):
                continue
            field = f"{root_key}[{index}].presentation_profile_id"
            profile_id = row.get("presentation_profile_id", "")
            if required and not profile_id:
                ctx.error(path, field, "is required")
            elif profile_id and profile_id not in profile_ids:
                ctx.error(path, field, f"unknown presentation profile {profile_id}")

    for path in (ENEMIES_CSV, HAZARDS_CSV):
        for index, row in enumerate(_load_csv_rows(path, ctx)):
            field = f"row[{index}].presentation_profile_id"
            profile_id = row.get("presentation_profile_id", "")
            if not profile_id:
                ctx.error(path, field, "is required")
            elif profile_id not in profile_ids:
                ctx.error(path, field, f"unknown presentation profile {profile_id}")


def _validate_characters(
    ctx: ValidationContext,
    weapon_ids: set[str],
    active_item_ids: set[str],
    consumable_ids: set[str],
    skill_ids: set[str],
    passive_ids: set[str],
    element_ids: set[str],
) -> None:
    path = CHARACTERS_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    schema_version = _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=4)
    if schema_version is not None and schema_version != 4:
        ctx.error(path, "schema_version", "must equal 4")
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
        _validate_actor_scene_path(
            ctx,
            path,
            f"{field}.scene_path",
            character.get("scene_path"),
            "res://scenes/gameplay/actors/characters/",
        )
        _require_locale_key(ctx, path, f"{field}.name_key", character.get("name_key"))
        _require_locale_key(ctx, path, f"{field}.desc_key", character.get("desc_key"))
        if "default_unlocked" in character:
            _require_bool(
                ctx,
                path,
                f"{field}.default_unlocked",
                character.get("default_unlocked"),
            )
        if "codex_icon_path" in character:
            _validate_codex_icon_path(
                ctx,
                path,
                f"{field}.codex_icon_path",
                character.get("codex_icon_path"),
            )
        tags = _validate_registered_string_list(ctx, path, f"{field}.tags", character.get("tags"), "content_tags", allow_empty=False)
        if "tag_character" not in tags:
            ctx.error(path, f"{field}.tags", "must include tag_character")
        _validate_registered_string_list(ctx, path, f"{field}.capabilities", character.get("capabilities", []), "capabilities", allow_empty=True)
        _require_non_empty_string(ctx, path, f"{field}.control_profile", character.get("control_profile"))
        _validate_character_palette(ctx, path, f"{field}.palette", character.get("palette"))
        element_id = _require_registered(ctx, path, f"{field}.element_id", character.get("element_id"), "elements")
        if element_id and element_id not in element_ids:
            ctx.error(path, f"{field}.element_id", f"element is not defined in elements.json: {element_id}")
        passive_id = _require_registered(ctx, path, f"{field}.passive_id", character.get("passive_id"), "hero_passive_ids")
        if passive_id and passive_id not in passive_ids:
            ctx.error(path, f"{field}.passive_id", f"passive is not defined in hero_passives.json: {passive_id}")
        hero_skill_values = _require_list(ctx, path, f"{field}.hero_skill_ids", character.get("hero_skill_ids"))
        if len(hero_skill_values) != 2:
            ctx.error(path, f"{field}.hero_skill_ids", "must contain exactly two skill ids")
        hero_skills: set[str] = set()
        for skill_index, skill_value in enumerate(hero_skill_values):
            skill_field = f"{field}.hero_skill_ids[{skill_index}]"
            skill_id = _require_registered(ctx, path, skill_field, skill_value, "skill_ids")
            if not skill_id:
                continue
            if skill_id in hero_skills:
                ctx.error(path, skill_field, f"duplicate skill id {skill_id}")
            hero_skills.add(skill_id)
            if skill_id not in skill_ids:
                ctx.error(path, skill_field, f"skill is not defined in skills.json: {skill_id}")
        _validate_character_starting_loadout(ctx, path, f"{field}.starting_loadout", character.get("starting_loadout"), weapon_ids, active_item_ids, consumable_ids)
        _validate_character_skill_resources(ctx, path, f"{field}.skill_resources", character.get("skill_resources", []))
        base_stats = character.get("base_stats")
        if not isinstance(base_stats, dict) or not base_stats:
            ctx.error(path, f"{field}.base_stats", "must be a non-empty object")
            continue
        for stat, value in base_stats.items():
            _validate_stat_value(ctx, path, f"{field}.base_stats.{stat}", stat, value)


def _validate_character_palette(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    expected = {"primary"}
    if set(data) != expected:
        ctx.error(path, field, f"must contain exactly {sorted(expected)}")
    for key in sorted(expected):
        value = data.get(key)
        if not isinstance(value, str) or not HTML_COLOR_RE.fullmatch(value):
            ctx.error(path, f"{field}.{key}", "must be a #RRGGBB or #RRGGBBAA color")


def _validate_character_starting_loadout(ctx: ValidationContext, path: Path, field: str, data: Any, weapon_ids: set[str], active_item_ids: set[str], consumable_ids: set[str]) -> None:
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
    if "skill_ids" in data:
        ctx.error(path, f"{field}.skill_ids", "was removed in schema_version 3; use character.hero_skill_ids")


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
        max_stat = _require_registered(ctx, path, f"{item_field}.max_stat", resource.get("max_stat"), "stats")
        if max_stat != "max_energy":
            ctx.error(path, f"{item_field}.max_stat", "must equal max_energy for the energy resource")
        _require_number(ctx, path, f"{item_field}.start_ratio", resource.get("start_ratio"), minimum=0, maximum=1)
        _require_number(ctx, path, f"{item_field}.regen_per_second", resource.get("regen_per_second"), minimum=0)
        if "max" in resource or "start" in resource:
            ctx.error(path, item_field, "legacy max/start fields are not allowed; use max_stat/start_ratio")


def _validate_weapons(ctx: ValidationContext) -> None:
    path = WEAPONS_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _require_int(
        ctx, path, "schema_version", data.get("schema_version"), minimum=5, maximum=5
    )
    recoil_model = data.get("recoil_model")
    if not isinstance(recoil_model, dict):
        ctx.error(path, "recoil_model", "must be an object")
        recoil_model = {}
    _validate_recoil_model(ctx, path, recoil_model)
    weapons = _require_list(ctx, path, "weapons", data.get("weapons"))
    if not weapons:
        ctx.error(path, "weapons", "must be a non-empty array")
    seen: set[str] = set()
    for index, weapon in enumerate(weapons):
        field = f"weapons[{index}]"
        if not isinstance(weapon, dict):
            ctx.error(path, field, "must be an object")
            continue
        _validate_exact_object_keys(
            ctx,
            path,
            field,
            weapon,
            {
                "id",
                "name_key",
                "desc_key",
                "default_unlocked",
                "fire_mode",
                "fire_audio_id",
                "presentation_profile_id",
                "base_stats",
                "projectile",
            },
        )
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
        _validate_weapon_stats(
            ctx,
            path,
            f"{field}.base_stats",
            weapon.get("base_stats"),
            recoil_model,
        )
        _validate_weapon_projectile(ctx, path, f"{field}.projectile", weapon.get("projectile"))


def _validate_recoil_model(
    ctx: ValidationContext, path: Path, recoil_model: dict[str, Any]
) -> None:
    recoil_max = _require_number(
        ctx,
        path,
        "recoil_model.recoil_max",
        recoil_model.get("recoil_max"),
        minimum=0,
        maximum=WEAPON_RECOIL_MAXIMUM,
        exclusive_minimum=True,
    )
    _require_number(
        ctx,
        path,
        "recoil_model.spread_exponent",
        recoil_model.get("spread_exponent"),
        minimum=0,
        exclusive_minimum=True,
    )
    _require_number(
        ctx,
        path,
        "recoil_model.kickback_max_distance",
        recoil_model.get("kickback_max_distance"),
        minimum=0,
    )
    _require_number(
        ctx,
        path,
        "recoil_model.kickback_duration",
        recoil_model.get("kickback_duration"),
        minimum=0,
        exclusive_minimum=True,
    )
    _require_number(
        ctx,
        path,
        "recoil_model.kickback_velocity_cap",
        recoil_model.get("kickback_velocity_cap"),
        minimum=0,
        exclusive_minimum=True,
    )
    base_spread_cap = _require_number(
        ctx,
        path,
        "recoil_model.base_spread_cap",
        recoil_model.get("base_spread_cap"),
        minimum=0,
        maximum=WEAPON_BASE_SPREAD_CAP_MAXIMUM,
    )
    runtime_spread_cap = _require_number(
        ctx,
        path,
        "recoil_model.runtime_spread_cap",
        recoil_model.get("runtime_spread_cap"),
        minimum=0,
        maximum=WEAPON_RUNTIME_SPREAD_CAP_MAXIMUM,
    )
    if (
        isinstance(base_spread_cap, (int, float))
        and isinstance(runtime_spread_cap, (int, float))
        and runtime_spread_cap < base_spread_cap
    ):
        ctx.error(
            path,
            "recoil_model.runtime_spread_cap",
            "must be >= recoil_model.base_spread_cap",
        )
    _ = recoil_max


def _validate_weapon_stats(
    ctx: ValidationContext,
    path: Path,
    field: str,
    data: Any,
    recoil_model: dict[str, Any],
) -> None:
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
        elif stat == "recoil":
            _require_number(
                ctx,
                path,
                f"{field}.{stat}",
                value,
                minimum=0,
                maximum=float(recoil_model.get("recoil_max", 0.0)),
            )
        elif stat == "spread_angle_max":
            _require_number(
                ctx,
                path,
                f"{field}.{stat}",
                value,
                minimum=0,
                maximum=float(recoil_model.get("base_spread_cap", 0.0)),
            )
        else:
            _validate_stat_value(ctx, path, f"{field}.{stat}", stat, value)


def _validate_weapon_projectile(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    _require_registered(ctx, path, f"{field}.pool_id", data.get("pool_id"), "pool_ids")
    if "damage_type" in data:
        ctx.error(path, f"{field}.damage_type", "was removed; use element_id")
    _require_registered(ctx, path, f"{field}.element_id", data.get("element_id"), "elements")
    _require_number(ctx, path, f"{field}.hit_radius", data.get("hit_radius"), minimum=0, exclusive_minimum=True)
    _require_number(ctx, path, f"{field}.muzzle_distance", data.get("muzzle_distance"), minimum=0, exclusive_minimum=True)
    _require_number(ctx, path, f"{field}.lifetime", data.get("lifetime"), minimum=0, exclusive_minimum=True)


def _validate_enemy_ai_profiles(ctx: ValidationContext) -> None:
    path = ENEMY_AI_PROFILES_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=5, maximum=5)
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
        _reject_removed_field(ctx, path, field, profile, "contact_interval", schema_version=2)
        _reject_removed_field(ctx, path, field, profile, "sense_radius", schema_version=3)
        _validate_enemy_ai_perception(ctx, path, f"{field}.perception", profile.get("perception"))
        _require_number(ctx, path, f"{field}.decision_interval", profile.get("decision_interval"), minimum=0, exclusive_minimum=True)
        _validate_enemy_ai_targeting(ctx, path, f"{field}.targeting", profile.get("targeting"))
        _validate_enemy_ai_movement(ctx, path, f"{field}.movement", profile.get("movement"))
        _validate_enemy_ai_actions(ctx, path, f"{field}.actions", profile.get("actions"))


def _validate_enemy_ai_perception(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    sight_radius = _require_number(
        ctx, path, f"{field}.sight_radius", data.get("sight_radius"), minimum=0, exclusive_minimum=True
    )
    path_awareness_radius = _require_number(
        ctx, path, f"{field}.path_awareness_radius", data.get("path_awareness_radius"), minimum=0
    )
    _require_number(ctx, path, f"{field}.memory_duration", data.get("memory_duration"), minimum=0)
    if sight_radius is not None and path_awareness_radius is not None and path_awareness_radius > sight_radius:
        ctx.error(path, f"{field}.path_awareness_radius", "must be <= sight_radius")


def _validate_enemy_ai_targeting(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    _reject_removed_field(ctx, path, field, data, "hunt_tags", schema_version=2)
    _reject_removed_field(ctx, path, field, data, "flee_tags", schema_version=2)
    _require_number(ctx, path, f"{field}.player_weight", data.get("player_weight"), minimum=0)
    _require_number(ctx, path, f"{field}.territory_radius", data.get("territory_radius"), minimum=0)
    _require_number(ctx, path, f"{field}.territory_weight", data.get("territory_weight"), minimum=0)


def _validate_enemy_ai_movement(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    _reject_removed_field(ctx, path, field, data, "flee_distance", schema_version=2)
    _require_number(ctx, path, f"{field}.orbit_radius", data.get("orbit_radius"), minimum=0)
    unexpected = set(data).difference({"orbit_radius"})
    for key in sorted(unexpected):
        ctx.error(path, f"{field}.{key}", "was removed from movement in schema v4; move attack parameters into actions[].attack")


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
        _validate_enemy_ai_attack(ctx, path, item_field, action_id, action)


def _validate_enemy_ai_attack(
    ctx: ValidationContext,
    path: Path,
    field: str,
    action_id: str,
    action: dict[str, Any],
) -> None:
    attack_actions = {
        "ai_action_explode_target",
        "ai_action_melee_attack",
        "ai_action_charge_target",
        "ai_action_ranged_attack",
    }
    if action_id not in attack_actions:
        if "attack" in action:
            ctx.error(path, f"{field}.attack", "is forbidden for non-attack actions")
        return
    attack = action.get("attack")
    if not isinstance(attack, dict):
        ctx.error(path, f"{field}.attack", "must be an object")
        return
    if action_id == "ai_action_explode_target":
        expected = {"trigger_range", "windup", "damage", "element_id", "radius"}
        _validate_exact_object_keys(ctx, path, f"{field}.attack", attack, expected)
        for key in ("trigger_range", "windup", "damage", "radius"):
            _require_number(ctx, path, f"{field}.attack.{key}", attack.get(key), minimum=0, exclusive_minimum=True)
        _require_registered(ctx, path, f"{field}.attack.element_id", attack.get("element_id"), "elements")
        return
    if action_id == "ai_action_melee_attack":
        expected = {"trigger_range", "windup", "cooldown", "damage", "element_id", "range", "arc_degrees"}
        _validate_exact_object_keys(ctx, path, f"{field}.attack", attack, expected)
        for key in ("trigger_range", "windup", "cooldown", "damage", "range"):
            _require_number(ctx, path, f"{field}.attack.{key}", attack.get(key), minimum=0, exclusive_minimum=True)
        _require_number(
            ctx,
            path,
            f"{field}.attack.arc_degrees",
            attack.get("arc_degrees"),
            minimum=0,
            maximum=360,
            exclusive_minimum=True,
        )
        _require_registered(ctx, path, f"{field}.attack.element_id", attack.get("element_id"), "elements")
        return
    if action_id == "ai_action_charge_target":
        expected = {
            "trigger_range",
            "windup",
            "release_duration",
            "cooldown",
            "damage",
            "element_id",
            "speed_multiplier",
            "stop_on_hit",
            "knockback_distance",
            "knockback_duration",
        }
        _validate_exact_object_keys(ctx, path, f"{field}.attack", attack, expected)
        for key in (
            "trigger_range",
            "windup",
            "release_duration",
            "cooldown",
            "damage",
            "speed_multiplier",
        ):
            _require_number(ctx, path, f"{field}.attack.{key}", attack.get(key), minimum=0, exclusive_minimum=True)
        knockback_distance = _require_number(
            ctx, path, f"{field}.attack.knockback_distance", attack.get("knockback_distance"), minimum=0
        )
        knockback_duration = _require_number(
            ctx, path, f"{field}.attack.knockback_duration", attack.get("knockback_duration"), minimum=0
        )
        if (
            knockback_distance is not None
            and knockback_duration is not None
            and (knockback_distance > 0) != (knockback_duration > 0)
        ):
            ctx.error(path, f"{field}.attack.knockback_duration", "must be positive exactly when knockback_distance is positive")
        _require_bool(ctx, path, f"{field}.attack.stop_on_hit", attack.get("stop_on_hit"))
        _require_registered(ctx, path, f"{field}.attack.element_id", attack.get("element_id"), "elements")
        return

    expected = {
        "attack_range",
        "keep_distance",
        "windup",
        "burst_count",
        "shot_interval",
        "cooldown",
        "initial_cooldown",
        "damage",
        "element_id",
        "projectile",
    }
    _validate_exact_object_keys(ctx, path, f"{field}.attack", attack, expected)
    for key in ("attack_range", "windup", "shot_interval", "cooldown", "damage"):
        _require_number(ctx, path, f"{field}.attack.{key}", attack.get(key), minimum=0, exclusive_minimum=True)
    _require_int(ctx, path, f"{field}.attack.burst_count", attack.get("burst_count"), minimum=1)
    for key in ("keep_distance", "initial_cooldown"):
        _require_number(ctx, path, f"{field}.attack.{key}", attack.get(key), minimum=0)
    _require_registered(ctx, path, f"{field}.attack.element_id", attack.get("element_id"), "elements")
    projectile = attack.get("projectile")
    if not isinstance(projectile, dict):
        ctx.error(path, f"{field}.attack.projectile", "must be an object")
        return
    projectile_expected = {"pool_id", "speed", "range", "hit_radius", "lifetime", "muzzle_distance"}
    _validate_exact_object_keys(ctx, path, f"{field}.attack.projectile", projectile, projectile_expected)
    _require_registered(ctx, path, f"{field}.attack.projectile.pool_id", projectile.get("pool_id"), "pool_ids")
    for key in ("speed", "range", "hit_radius", "lifetime"):
        _require_number(
            ctx,
            path,
            f"{field}.attack.projectile.{key}",
            projectile.get(key),
            minimum=0,
            exclusive_minimum=True,
        )
    _require_number(
        ctx,
        path,
        f"{field}.attack.projectile.muzzle_distance",
        projectile.get("muzzle_distance"),
        minimum=0,
    )


def _validate_exact_object_keys(
    ctx: ValidationContext,
    path: Path,
    field: str,
    data: dict[str, Any],
    expected: set[str],
) -> None:
    for key in sorted(expected.difference(data)):
        ctx.error(path, f"{field}.{key}", "is required")
    for key in sorted(set(data).difference(expected)):
        ctx.error(path, f"{field}.{key}", "is not allowed")


def _validate_enemies_csv(ctx: ValidationContext, enemy_ai_profile_ids: set[str]) -> None:
    path = ENEMIES_CSV
    if not path.exists():
        ctx.error(path, "$", "missing enemies CSV")
        return

    required = {
        "id",
        "name_key",
        "desc_key",
        "default_unlocked",
        "unlock_rule_id",
        "codex_icon_path",
        "tags",
        "pool_id",
        "scene_path",
        "pool_prewarm",
        "ai_profile_id",
        "presentation_profile_id",
        "max_hp",
        "move_speed",
        "gold_value_multiplier",
        "hit_radius",
        "separation_radius",
    }
    seen_enemy_ids: set[str] = set()
    seen_pool_ids: set[str] = set()
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        fieldnames = reader.fieldnames or []
        missing = required.difference(fieldnames)
        if missing:
            ctx.error(path, "header", f"missing required columns {sorted(missing)}")
            return
        unexpected = set(fieldnames).difference(required)
        if unexpected:
            ctx.error(path, "header", f"unexpected columns {sorted(unexpected)}")
        row_count = 0
        for line_number, row in enumerate(reader, start=2):
            row_count += 1
            field = f"line {line_number}"
            enemy_id = _require_non_empty_string(ctx, path, f"{field}.id", row.get("id"))
            if enemy_id:
                if enemy_id in seen_enemy_ids:
                    ctx.error(path, f"{field}.id", f"duplicate enemy id {enemy_id}")
                seen_enemy_ids.add(enemy_id)
            _require_locale_key(ctx, path, f"{field}.name_key", row.get("name_key"))
            _require_locale_key(ctx, path, f"{field}.desc_key", row.get("desc_key"))
            _parse_csv_bool(
                ctx,
                path,
                f"{field}.default_unlocked",
                row.get("default_unlocked"),
            )
            _validate_codex_icon_path(
                ctx,
                path,
                f"{field}.codex_icon_path",
                row.get("codex_icon_path", ""),
            )
            tags = _validate_registered_string_list(ctx, path, f"{field}.tags", _parse_pipe_list(row.get("tags")), "content_tags", allow_empty=False)
            if "tag_enemy" not in tags:
                ctx.error(path, f"{field}.tags", "must include tag_enemy")
            pool_id = _require_registered(ctx, path, f"{field}.pool_id", row.get("pool_id"), "pool_ids")
            if pool_id:
                if pool_id in seen_pool_ids:
                    ctx.error(path, f"{field}.pool_id", f"duplicate enemy pool id {pool_id}")
                seen_pool_ids.add(pool_id)
                if pool_id != enemy_id:
                    ctx.error(path, f"{field}.pool_id", "must match the enemy id")
            _validate_actor_scene_path(
                ctx,
                path,
                f"{field}.scene_path",
                row.get("scene_path"),
                "res://scenes/gameplay/actors/enemies/",
            )
            _parse_int(ctx, path, f"{field}.pool_prewarm", row.get("pool_prewarm"), minimum=0)
            ai_profile_id = _require_non_empty_string(ctx, path, f"{field}.ai_profile_id", row.get("ai_profile_id"))
            if ai_profile_id and ai_profile_id not in enemy_ai_profile_ids:
                ctx.error(path, f"{field}.ai_profile_id", f"profile is not defined in enemy_ai_profiles.json: {ai_profile_id}")
            _parse_int(ctx, path, f"{field}.max_hp", row.get("max_hp"), minimum=1)
            _parse_float(ctx, path, f"{field}.move_speed", row.get("move_speed"), minimum=0, exclusive_minimum=True)
            _parse_float(
                ctx,
                path,
                f"{field}.gold_value_multiplier",
                row.get("gold_value_multiplier"),
                minimum=0,
                exclusive_minimum=True,
            )
            _parse_float(ctx, path, f"{field}.hit_radius", row.get("hit_radius"), minimum=0, exclusive_minimum=True)
            _parse_float(ctx, path, f"{field}.separation_radius", row.get("separation_radius"), minimum=0)
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
        "presentation_profile_id",
        "damage",
        "element_id",
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
            _require_registered(ctx, path, f"{field}.element_id", row.get("element_id"), "elements")
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
    schema_version = _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=2)
    if schema_version != 2:
        ctx.error(path, "schema_version", "must equal 2")
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
        desc_key = skill.get("desc_key")
        _require_locale_key(ctx, path, f"{field}.desc_key", desc_key)
        _validate_description_placeholders(
            ctx,
            path,
            f"{field}.desc_key",
            desc_key,
            _skill_description_tokens(skill),
        )
        if "default_unlocked" in skill:
            skill_default_unlocked = _require_bool(
                ctx,
                path,
                f"{field}.default_unlocked",
                skill.get("default_unlocked"),
            )
            if skill_default_unlocked is False:
                ctx.error(
                    path,
                    f"{field}.default_unlocked",
                    "must remain true; skills inherit their character unlock",
                )
        tags = _validate_registered_string_list(ctx, path, f"{field}.tags", skill.get("tags"), "content_tags", allow_empty=False)
        if "tag_skill" not in tags:
            ctx.error(path, f"{field}.tags", "must include tag_skill")
        _validate_registered_string_list(ctx, path, f"{field}.ability_tags", skill.get("ability_tags"), "ability_tags", allow_empty=False)
        _validate_skill_activation(ctx, path, f"{field}.activation", skill.get("activation"))
        _require_number(ctx, path, f"{field}.cooldown", skill.get("cooldown"), minimum=0)
        _validate_skill_costs(ctx, path, f"{field}.costs", skill.get("costs"))
        _validate_skill_targeting(ctx, path, f"{field}.targeting", skill.get("targeting"))
        _validate_skill_scaling(ctx, path, f"{field}.scaling", skill.get("scaling"))
        _validate_skill_effects(ctx, path, f"{field}.effects", skill.get("effects"))


def _skill_description_tokens(skill: dict[str, Any]) -> set[str]:
    tokens = {"{cooldown}", "{target_radius}"}
    costs = skill.get("costs")
    if isinstance(costs, list):
        for cost in costs:
            if not isinstance(cost, dict):
                continue
            resource_id = cost.get("resource")
            if isinstance(resource_id, str) and resource_id:
                tokens.add(f"{{cost_{resource_id}}}")
    effects = skill.get("effects")
    if not isinstance(effects, list):
        return tokens
    for effect_index, effect in enumerate(effects, start=1):
        if not isinstance(effect, dict):
            continue
        params = effect.get("params")
        if not isinstance(params, dict):
            continue
        effect_prefix = f"effect_{effect_index}"
        tokens.update(_numeric_description_tokens(effect_prefix, params))
        modifiers = params.get("modifiers")
        if not isinstance(modifiers, list):
            continue
        for modifier_index, modifier in enumerate(modifiers, start=1):
            if isinstance(modifier, dict):
                tokens.update(
                    _numeric_description_tokens(
                        f"{effect_prefix}_modifier_{modifier_index}",
                        modifier,
                    )
                )
    return tokens


def _numeric_description_tokens(
    prefix: str,
    source: dict[str, Any],
) -> set[str]:
    tokens: set[str] = set()
    for key, value in source.items():
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            continue
        base = f"{prefix}_{key}"
        tokens.update(
            {
                f"{{{base}}}",
                f"{{{base}_percent}}",
                f"{{{base}_bonus_percent}}",
                f"{{{base}_reduction_percent}}",
            }
        )
    return tokens


def _validate_description_placeholders(
    ctx: ValidationContext,
    path: Path,
    field: str,
    desc_key: Any,
    allowed_tokens: set[str],
) -> None:
    if not isinstance(desc_key, str) or not desc_key:
        return
    used_tokens = ctx.locale_placeholders.get(desc_key, set())
    unsupported = used_tokens.difference(allowed_tokens)
    if unsupported:
        ctx.error(
            path,
            field,
            f"unsupported config description placeholders {sorted(unsupported)}",
        )


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


def _validate_skill_scaling(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    allowed = {
        "cost_stat": "ability_efficiency",
        "radius_stat": "ability_range",
        "duration_stat": "ability_duration",
        "strength_stat": "ability_strength",
    }
    for key, value in data.items():
        if key not in allowed:
            ctx.error(path, f"{field}.{key}", f"unsupported scaling key; expected one of {sorted(allowed)}")
            continue
        stat = _require_registered(ctx, path, f"{field}.{key}", value, "stats")
        if stat and stat != allowed[key]:
            ctx.error(path, f"{field}.{key}", f"must equal {allowed[key]}")
    if data.get("cost_stat") != "ability_efficiency":
        ctx.error(path, f"{field}.cost_stat", "is required and must equal ability_efficiency")


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
            if "damage_type" in params:
                ctx.error(path, f"{item_field}.params.damage_type", "was removed; use element_id")
            _require_registered(ctx, path, f"{item_field}.params.element_id", params.get("element_id"), "elements")
        if effect_id == "skill_effect_apply_status":
            _require_registered(ctx, path, f"{item_field}.params.status", params.get("status"), "status_effects")
            _require_number(ctx, path, f"{item_field}.params.duration", params.get("duration"), minimum=0, exclusive_minimum=True)
            _require_registered(ctx, path, f"{item_field}.params.stack_rule", params.get("stack_rule"), "status_stack_rules")
            _validate_registered_string_list(ctx, path, f"{item_field}.params.granted_ability_tags", params.get("granted_ability_tags"), "ability_tags", allow_empty=True)
            if "magnitude" in params:
                _require_number(ctx, path, f"{item_field}.params.magnitude", params.get("magnitude"))
            if "magnitude_cap" in params:
                _require_number(ctx, path, f"{item_field}.params.magnitude_cap", params.get("magnitude_cap"), minimum=0)
            if "max_stacks" in params:
                _require_int(ctx, path, f"{item_field}.params.max_stacks", params.get("max_stacks"), minimum=1)
            if "tick_interval" in params:
                _require_number(ctx, path, f"{item_field}.params.tick_interval", params.get("tick_interval"), minimum=0)
            if "damage_type" in params:
                ctx.error(path, f"{item_field}.params.damage_type", "was removed; use element_id")
            if "element_id" in params:
                _require_registered(ctx, path, f"{item_field}.params.element_id", params.get("element_id"), "elements")
            elif _status_params_has_damage_tick(params):
                ctx.error(path, f"{item_field}.params.element_id", "is required when magnitude and tick_interval are positive")
            if "modifiers" in params:
                _validate_modifiers(ctx, path, f"{item_field}.params.modifiers", params.get("modifiers"), require_value_per_level=False)
                for modifier_index, modifier in enumerate(params.get("modifiers", [])):
                    if isinstance(modifier, dict) and "scale_mode" in modifier and modifier.get("scale_mode") != "inverse_from_magnitude":
                        ctx.error(path, f"{item_field}.params.modifiers[{modifier_index}].scale_mode", "must equal inverse_from_magnitude when present")
            if "incoming_damage_per_stack" in params:
                _require_number(ctx, path, f"{item_field}.params.incoming_damage_per_stack", params.get("incoming_damage_per_stack"), minimum=0)
            if "incoming_damage_source_team" in params:
                _require_non_empty_string(ctx, path, f"{item_field}.params.incoming_damage_source_team", params.get("incoming_damage_source_team"))
        if effect_id == "skill_effect_weapon_modifiers":
            _require_number(ctx, path, f"{item_field}.params.duration", params.get("duration"), minimum=0, exclusive_minimum=True)
            _validate_modifiers(ctx, path, f"{item_field}.params.modifiers", params.get("modifiers"), require_value_per_level=False)
        if effect_id == "skill_effect_deploy_barrier":
            _require_registered(ctx, path, f"{item_field}.params.pool_id", params.get("pool_id"), "pool_ids")
            _require_number(ctx, path, f"{item_field}.params.radius", params.get("radius"), minimum=0, exclusive_minimum=True)
            _require_number(ctx, path, f"{item_field}.params.hp", params.get("hp"), minimum=0, exclusive_minimum=True)
            _require_int(ctx, path, f"{item_field}.params.max_active", params.get("max_active"), minimum=1)
            if params.get("recast_policy") != "replace":
                ctx.error(path, f"{item_field}.params.recast_policy", "must equal replace")
        if effect_id == "skill_effect_actor_modifiers":
            _require_number(ctx, path, f"{item_field}.params.duration", params.get("duration"), minimum=0, exclusive_minimum=True)
            _require_registered(ctx, path, f"{item_field}.params.stack_rule", params.get("stack_rule"), "status_stack_rules")
            _validate_modifiers(ctx, path, f"{item_field}.params.modifiers", params.get("modifiers"), require_value_per_level=False)


def _validate_gear_mods(ctx: ValidationContext) -> None:
    path = GEAR_MODS_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _validate_exact_object_keys(
        ctx,
        path,
        "root",
        data,
        {"schema_version", "board", "pickup", "reward_pools", "mods"},
    )
    _require_exact_int(ctx, path, "schema_version", data.get("schema_version"), 5)
    _validate_gear_mod_board(ctx, path, data.get("board"))
    pickup = data.get("pickup")
    if not isinstance(pickup, dict):
        ctx.error(path, "pickup", "must be an object")
    else:
        expected_pickup_keys = {
            "pool_id",
            "interaction_radius",
            "spawn_vertical_offset",
            "spawn_spread",
        }
        if set(pickup) != expected_pickup_keys:
            ctx.error(path, "pickup", "must define exactly pool_id, interaction_radius, spawn_vertical_offset, and spawn_spread")
        pool_id = _require_registered(ctx, path, "pickup.pool_id", pickup.get("pool_id"), "pool_ids")
        if pool_id and pool_id != "gear_mod_pickup":
            ctx.error(path, "pickup.pool_id", "must equal gear_mod_pickup")
        _require_number(ctx, path, "pickup.interaction_radius", pickup.get("interaction_radius"), minimum=0, exclusive_minimum=True)
        _require_number(ctx, path, "pickup.spawn_vertical_offset", pickup.get("spawn_vertical_offset"))
        _require_number(ctx, path, "pickup.spawn_spread", pickup.get("spawn_spread"), minimum=0)
    reward_pools = _require_list(ctx, path, "reward_pools", data.get("reward_pools"))
    seen_pool_ids: set[str] = set()
    for pool_index, pool in enumerate(reward_pools):
        pool_field = f"reward_pools[{pool_index}]"
        if not isinstance(pool, dict):
            ctx.error(path, pool_field, "must be an object")
            continue
        if set(pool) != {"id", "mod_ids"}:
            ctx.error(path, pool_field, "must define exactly id and mod_ids")
        pool_id = _require_registered(
            ctx, path, f"{pool_field}.id", pool.get("id"), "world_event_mod_pool_ids"
        )
        if pool_id:
            if pool_id in seen_pool_ids:
                ctx.error(path, f"{pool_field}.id", f"duplicate reward pool id {pool_id}")
            seen_pool_ids.add(pool_id)
        pool_mod_ids = _require_list(ctx, path, f"{pool_field}.mod_ids", pool.get("mod_ids"))
        if not pool_mod_ids:
            ctx.error(path, f"{pool_field}.mod_ids", "must be a non-empty array")
        seen_pool_mod_ids: set[str] = set()
        for mod_index, raw_mod_id in enumerate(pool_mod_ids):
            mod_field = f"{pool_field}.mod_ids[{mod_index}]"
            mod_id = _require_registered(ctx, path, mod_field, raw_mod_id, "gear_mod_ids")
            if mod_id:
                if mod_id in seen_pool_mod_ids:
                    ctx.error(path, mod_field, f"duplicate Gear Mod id {mod_id}")
                seen_pool_mod_ids.add(mod_id)
    expected_pool_ids = set(ctx.contracts.get("world_event_mod_pool_ids", []))
    if seen_pool_ids != expected_pool_ids:
        ctx.error(path, "reward_pools", "must define every registered world_event_mod_pool_id exactly once")
    mods = _require_list(ctx, path, "mods", data.get("mods"))
    if not mods:
        ctx.error(path, "mods", "must be a non-empty array")
    seen: set[str] = set()
    for index, mod in enumerate(mods):
        field = f"mods[{index}]"
        if not isinstance(mod, dict):
            ctx.error(path, field, "must be an object")
            continue
        common_required_mod_keys = {
            "id",
            "name_key",
            "desc_key",
            "kind",
            "rarity",
        }
        optional_mod_keys = {
            "default_unlocked",
            "unlock_rule_id",
            "codex_icon_path",
        }
        kind = _require_registered(
            ctx,
            path,
            f"{field}.kind",
            mod.get("kind"),
            "gear_mod_kinds",
        )
        kind_required_keys: set[str] = set()
        if kind == "effect":
            kind_required_keys = {"slot", "modifiers"}
        elif kind == "map":
            kind_required_keys = {"map_behavior"}
        elif kind == "grid":
            kind_required_keys = {"grid_behavior"}
        _validate_exact_object_keys(
            ctx,
            path,
            field,
            mod,
            common_required_mod_keys | optional_mod_keys.intersection(mod) | kind_required_keys,
        )
        mod_id = _require_registered(ctx, path, f"{field}.id", mod.get("id"), "gear_mod_ids")
        if mod_id:
            if mod_id in seen:
                ctx.error(path, f"{field}.id", f"duplicate gear mod id {mod_id}")
            seen.add(mod_id)
        _require_locale_key(ctx, path, f"{field}.name_key", mod.get("name_key"))
        _require_locale_key(ctx, path, f"{field}.desc_key", mod.get("desc_key"))
        if "default_unlocked" in mod:
            _require_bool(
                ctx,
                path,
                f"{field}.default_unlocked",
                mod.get("default_unlocked"),
            )
        if "codex_icon_path" in mod:
            _validate_codex_icon_path(
                ctx,
                path,
                f"{field}.codex_icon_path",
                mod.get("codex_icon_path"),
            )
        _require_registered(ctx, path, f"{field}.rarity", mod.get("rarity"), "gear_mod_rarities")
        if kind == "effect":
            _require_registered(ctx, path, f"{field}.slot", mod.get("slot"), "gear_mod_slots")
            _validate_gear_mod_modifiers(
                ctx,
                path,
                f"{field}.modifiers",
                mod.get("modifiers"),
            )
        elif kind == "map":
            _validate_gear_mod_map_behavior(
                ctx,
                path,
                f"{field}.map_behavior",
                mod.get("map_behavior"),
            )
        elif kind == "grid":
            _validate_gear_mod_grid_behavior(
                ctx,
                path,
                f"{field}.grid_behavior",
                mod.get("grid_behavior"),
            )


def _validate_gear_mod_board(
    ctx: ValidationContext,
    path: Path,
    data: Any,
) -> None:
    if not isinstance(data, dict):
        ctx.error(path, "board", "must be an object")
        return
    _validate_exact_object_keys(
        ctx,
        path,
        "board",
        data,
        {"width", "height", "center", "initial_unlocked_cells"},
    )
    _require_exact_int(ctx, path, "board.width", data.get("width"), 7)
    _require_exact_int(ctx, path, "board.height", data.get("height"), 7)
    center = data.get("center")
    if not isinstance(center, dict):
        ctx.error(path, "board.center", "must be an object")
    else:
        _validate_exact_object_keys(
            ctx,
            path,
            "board.center",
            center,
            {"x", "y"},
        )
        _require_exact_int(ctx, path, "board.center.x", center.get("x"), 3)
        _require_exact_int(ctx, path, "board.center.y", center.get("y"), 3)
    raw_cells = _require_list(
        ctx,
        path,
        "board.initial_unlocked_cells",
        data.get("initial_unlocked_cells"),
    )
    expected_cells = {
        (3, 1),
        (2, 2),
        (3, 2),
        (4, 2),
        (1, 3),
        (2, 3),
        (3, 3),
        (4, 3),
        (5, 3),
        (2, 4),
        (3, 4),
        (4, 4),
        (3, 5),
    }
    actual_cells: set[tuple[int, int]] = set()
    for index, raw_cell in enumerate(raw_cells):
        field = f"board.initial_unlocked_cells[{index}]"
        if not isinstance(raw_cell, dict):
            ctx.error(path, field, "must be an object")
            continue
        _validate_exact_object_keys(ctx, path, field, raw_cell, {"x", "y"})
        x = _require_int(ctx, path, f"{field}.x", raw_cell.get("x"), minimum=0, maximum=6)
        y = _require_int(ctx, path, f"{field}.y", raw_cell.get("y"), minimum=0, maximum=6)
        if x is None or y is None:
            continue
        cell = (x, y)
        if cell in actual_cells:
            ctx.error(path, field, f"duplicate board cell {cell}")
        actual_cells.add(cell)
    if len(raw_cells) != 13 or actual_cells != expected_cells:
        ctx.error(
            path,
            "board.initial_unlocked_cells",
            "must equal the 13-cell 0/1/3/5/3/1/0 center mask",
        )


def _validate_gear_mod_map_behavior(
    ctx: ValidationContext,
    path: Path,
    field: str,
    data: Any,
) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    _validate_exact_object_keys(
        ctx,
        path,
        field,
        data,
        {
            "id",
            "interval_seconds",
            "reset_on_module_exit",
            "current_layer_only",
            "normal_rewards",
        },
    )
    behavior_id = _require_registered(
        ctx,
        path,
        f"{field}.id",
        data.get("id"),
        "gear_mod_map_behaviors",
    )
    if behavior_id and behavior_id != "periodic_enemy_spawn":
        ctx.error(path, f"{field}.id", "must equal periodic_enemy_spawn")
    interval = _require_number(
        ctx,
        path,
        f"{field}.interval_seconds",
        data.get("interval_seconds"),
        minimum=0,
        exclusive_minimum=True,
    )
    if interval is not None and interval != 10.0:
        ctx.error(path, f"{field}.interval_seconds", "must equal 10.0")
    for key in ("reset_on_module_exit", "current_layer_only", "normal_rewards"):
        value = _require_bool(ctx, path, f"{field}.{key}", data.get(key))
        if value is False:
            ctx.error(path, f"{field}.{key}", "must be true")


def _validate_gear_mod_grid_behavior(
    ctx: ValidationContext,
    path: Path,
    field: str,
    data: Any,
) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    _validate_exact_object_keys(ctx, path, field, data, {"id"})
    behavior_id = _require_registered(
        ctx,
        path,
        f"{field}.id",
        data.get("id"),
        "gear_mod_grid_behaviors",
    )
    if behavior_id and behavior_id != "occupy_only":
        ctx.error(path, f"{field}.id", "must equal occupy_only")


def _validate_gear_mod_modifiers(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    modifiers = _require_list(ctx, path, field, data)
    if not modifiers:
        ctx.error(path, field, "must be a non-empty array")
    for index, modifier in enumerate(modifiers):
        item_field = f"{field}[{index}]"
        if not isinstance(modifier, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        _validate_exact_object_keys(
            ctx,
            path,
            item_field,
            modifier,
            {"stat", "type", "value"},
        )
        _require_registered(ctx, path, f"{item_field}.stat", modifier.get("stat"), "stats")
        if modifier.get("type") not in {"add", "mult"}:
            ctx.error(path, f"{item_field}.type", "must be add or mult")
        _require_number(ctx, path, f"{item_field}.value", modifier.get("value"))


def _validate_content_unlocks(
    ctx: ValidationContext,
    character_ids: set[str],
    gear_mod_ids: set[str],
    enemy_ids: set[str],
) -> None:
    path = CONTENT_UNLOCK_RULES_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _validate_exact_object_keys(
        ctx, path, "root", data, {"schema_version", "rules"}
    )
    _require_exact_int(ctx, path, "schema_version", data.get("schema_version"), 1)

    entries = _content_unlock_entries(ctx)
    default_state: dict[str, dict[str, bool]] = {
        content_type: {
            content_id: _content_default_unlocked(entry)
            for content_id, entry in typed_entries.items()
        }
        for content_type, typed_entries in entries.items()
    }
    expected_ids = {
        "character": character_ids,
        "gear_mod": gear_mod_ids,
        "enemy": enemy_ids,
    }
    for content_type, ids in expected_ids.items():
        if set(entries.get(content_type, {})) != ids:
            ctx.error(
                path,
                content_type,
                "content definitions must match the registered ids exactly",
            )

    rules = _require_list(ctx, path, "rules", data.get("rules"))
    rules_by_id: dict[str, dict[str, Any]] = {}
    subject_counters = {"character_run_completed", "enemy_defeated"}
    for rule_index, rule in enumerate(rules):
        field = f"rules[{rule_index}]"
        if not isinstance(rule, dict):
            ctx.error(path, field, "must be an object")
            continue
        _validate_exact_object_keys(
            ctx, path, field, rule, {"id", "mode", "conditions"}
        )
        rule_id = _require_non_empty_string(ctx, path, f"{field}.id", rule.get("id"))
        if rule_id:
            if not LOCALE_KEY_RE.fullmatch(rule_id):
                ctx.error(path, f"{field}.id", "must be snake_case")
            elif rule_id in rules_by_id:
                ctx.error(path, f"{field}.id", f"duplicate unlock rule id {rule_id}")
            else:
                rules_by_id[rule_id] = rule
        _require_registered(
            ctx,
            path,
            f"{field}.mode",
            rule.get("mode"),
            "content_unlock_rule_modes",
        )
        conditions = _require_list(ctx, path, f"{field}.conditions", rule.get("conditions"))
        if not conditions:
            ctx.error(path, f"{field}.conditions", "must be a non-empty array")
        for condition_index, condition in enumerate(conditions):
            condition_field = f"{field}.conditions[{condition_index}]"
            if not isinstance(condition, dict):
                ctx.error(path, condition_field, "must be an object")
                continue
            expected_keys = {"counter_id", "target"}
            counter_id = condition.get("counter_id")
            if counter_id in subject_counters:
                expected_keys.add("subject_id")
            _validate_exact_object_keys(
                ctx, path, condition_field, condition, expected_keys
            )
            registered_counter = _require_registered(
                ctx,
                path,
                f"{condition_field}.counter_id",
                counter_id,
                "content_unlock_progress_counters",
            )
            _require_int(
                ctx,
                path,
                f"{condition_field}.target",
                condition.get("target"),
                minimum=1,
            )
            if registered_counter not in subject_counters:
                continue
            subject_type = (
                "character"
                if registered_counter == "character_run_completed"
                else "enemy"
            )
            subject_id = _require_non_empty_string(
                ctx,
                path,
                f"{condition_field}.subject_id",
                condition.get("subject_id"),
            )
            if subject_id and subject_id not in entries.get(subject_type, {}):
                ctx.error(
                    path,
                    f"{condition_field}.subject_id",
                    f"unknown {subject_type} id {subject_id}",
                )
            elif subject_id and not default_state[subject_type].get(subject_id, False):
                ctx.error(
                    path,
                    f"{condition_field}.subject_id",
                    "unlock requirements may only reference default-unlocked content",
                )

    referenced_rule_ids: set[str] = set()
    for content_type, typed_entries in entries.items():
        for content_id, entry in typed_entries.items():
            field = f"{content_type}.{content_id}"
            default_unlocked = default_state[content_type][content_id]
            raw_rule_id = entry.get("unlock_rule_id", "")
            if not isinstance(raw_rule_id, str):
                ctx.error(path, f"{field}.unlock_rule_id", "must be a string when present")
                continue
            rule_id = raw_rule_id.strip()
            if default_unlocked and rule_id:
                ctx.error(
                    path,
                    f"{field}.unlock_rule_id",
                    "default-unlocked content must not reference an unlock rule",
                )
            if not default_unlocked and not rule_id:
                ctx.error(
                    path,
                    f"{field}.unlock_rule_id",
                    "locked content must reference an unlock rule",
                )
            if rule_id:
                referenced_rule_ids.add(rule_id)
                if rule_id not in rules_by_id:
                    ctx.error(
                        path,
                        f"{field}.unlock_rule_id",
                        f"unknown unlock rule {rule_id}",
                    )

    for rule_id in sorted(set(rules_by_id).difference(referenced_rule_ids)):
        ctx.error(path, f"rules.{rule_id}", "unlock rule is not referenced by content")
    if sum(default_state.get("character", {}).values()) < 2:
        ctx.error(path, "characters", "at least two characters must be default unlocked")
    _validate_default_unlocked_gear_mod_pools(
        ctx, default_state.get("gear_mod", {})
    )
    _validate_default_unlocked_enemy_pools(ctx, default_state.get("enemy", {}))


def _content_unlock_entries(
    ctx: ValidationContext,
) -> dict[str, dict[str, dict[str, Any]]]:
    result: dict[str, dict[str, dict[str, Any]]] = {
        "character": {},
        "gear_mod": {},
        "enemy": {},
    }
    for content_type, path, root_key in (
        ("character", CHARACTERS_JSON, "characters"),
        ("gear_mod", GEAR_MODS_JSON, "mods"),
    ):
        data = _load_json(path, ctx)
        if not isinstance(data, dict) or not isinstance(data.get(root_key), list):
            continue
        for entry in data[root_key]:
            if isinstance(entry, dict) and isinstance(entry.get("id"), str):
                result[content_type][entry["id"]] = entry
    for row in _load_csv_rows(ENEMIES_CSV, ctx):
        enemy_id = row.get("id", "")
        if enemy_id:
            result["enemy"][enemy_id] = row
    return result


def _content_default_unlocked(entry: dict[str, Any]) -> bool:
    value = entry.get("default_unlocked", True)
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        normalized = value.strip().lower()
        return not normalized or normalized == "true"
    return False


def _validate_default_unlocked_gear_mod_pools(
    ctx: ValidationContext,
    default_state: dict[str, bool],
) -> None:
    data = _load_json(GEAR_MODS_JSON, ctx)
    if not isinstance(data, dict) or not isinstance(data.get("reward_pools"), list):
        return
    for pool_index, pool in enumerate(data["reward_pools"]):
        if not isinstance(pool, dict) or not isinstance(pool.get("mod_ids"), list):
            continue
        if not any(default_state.get(str(mod_id), False) for mod_id in pool["mod_ids"]):
            ctx.error(
                GEAR_MODS_JSON,
                f"reward_pools[{pool_index}].mod_ids",
                "must contain at least one default-unlocked Gear Mod",
            )


def _validate_default_unlocked_enemy_pools(
    ctx: ValidationContext,
    default_state: dict[str, bool],
) -> None:
    module_data = _load_json(MODULE_WORLDS_JSON, ctx)
    if isinstance(module_data, dict) and isinstance(module_data.get("worlds"), list):
        for world_index, world in enumerate(module_data["worlds"]):
            if not isinstance(world, dict):
                continue
            spawn = world.get("first_visit_enemy_spawn")
            pool = spawn.get("enemy_pool") if isinstance(spawn, dict) else None
            if not isinstance(pool, list):
                continue
            has_default_zero = any(
                isinstance(entry, dict)
                and float(entry.get("unlock_time", -1)) == 0.0
                and default_state.get(str(entry.get("enemy_id", "")), False)
                for entry in pool
            )
            if not has_default_zero:
                ctx.error(
                    MODULE_WORLDS_JSON,
                    f"worlds[{world_index}].first_visit_enemy_spawn.enemy_pool",
                    "must contain a 0-second default-unlocked enemy",
                )

    rows_by_mode: dict[str, list[dict[str, str]]] = {}
    for row in _load_csv_rows(SPAWN_WAVES_CSV, ctx):
        rows_by_mode.setdefault(row.get("mode_id", ""), []).append(row)
    for mode_id, rows in rows_by_mode.items():
        has_default_zero = any(
            row.get("start_time") in {"0", "0.0"}
            and default_state.get(row.get("enemy_id", ""), False)
            for row in rows
        )
        if not has_default_zero:
            ctx.error(
                SPAWN_WAVES_CSV,
                mode_id,
                "must contain a 0-second default-unlocked enemy wave",
            )


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


def _validate_camera_feedback(ctx: ValidationContext) -> set[str]:
    path = CAMERA_FEEDBACK_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return set()
    _require_int(
        ctx, path, "schema_version", data.get("schema_version"), minimum=3, maximum=3
    )
    aim_look = data.get("aim_look")
    if not isinstance(aim_look, dict):
        ctx.error(path, "aim_look", "must be an object")
    else:
        _validate_camera_aim_look(ctx, path, aim_look)
    for profile_id in ("player_damage_shake", "weapon_recoil_shake"):
        shake = data.get(profile_id)
        if not isinstance(shake, dict):
            ctx.error(path, profile_id, "must be an object")
            continue
        _validate_camera_feedback_profile(ctx, path, profile_id, shake)
    recoil_profile = data.get("weapon_recoil_shake")
    if isinstance(recoil_profile, dict):
        _require_number(
            ctx,
            path,
            "weapon_recoil_shake.amplitude_exponent",
            recoil_profile.get("amplitude_exponent"),
            minimum=0.0,
        )
    return {
        profile_id
        for profile_id in ("player_damage_shake", "weapon_recoil_shake")
        if isinstance(data.get(profile_id), dict)
    }


def _validate_camera_aim_look(
    ctx: ValidationContext,
    path: Path,
    profile: dict[str, Any],
) -> None:
    _require_number(
        ctx,
        path,
        "aim_look.pointer_offset_ratio",
        profile.get("pointer_offset_ratio"),
        minimum=0.0,
        maximum=1.0,
        exclusive_minimum=True,
    )
    _require_number(
        ctx,
        path,
        "aim_look.max_offset_px",
        profile.get("max_offset_px"),
        minimum=0.0,
    )
    _require_number(
        ctx,
        path,
        "aim_look.pointer_dead_zone_px",
        profile.get("pointer_dead_zone_px"),
        minimum=0.0,
    )
    _require_number(
        ctx,
        path,
        "aim_look.smoothing_time_seconds",
        profile.get("smoothing_time_seconds"),
        minimum=0.0,
        exclusive_minimum=True,
    )


def _validate_camera_feedback_profile(
    ctx: ValidationContext,
    path: Path,
    profile_id: str,
    profile: dict[str, Any],
) -> None:
    _require_number(
        ctx, path, f"{profile_id}.amplitude", profile.get("amplitude"), minimum=0.0
    )
    _require_number(
        ctx,
        path,
        f"{profile_id}.frequency",
        profile.get("frequency"),
        minimum=0.0,
        exclusive_minimum=True,
    )
    _require_number(
        ctx,
        path,
        f"{profile_id}.growth_time",
        profile.get("growth_time"),
        minimum=0.0,
        exclusive_minimum=True,
    )
    _require_number(
        ctx,
        path,
        f"{profile_id}.duration",
        profile.get("duration"),
        minimum=0.0,
        exclusive_minimum=True,
    )
    _require_number(
        ctx,
        path,
        f"{profile_id}.decay_time",
        profile.get("decay_time"),
        minimum=0.0,
        exclusive_minimum=True,
    )
    _require_number(
        ctx,
        path,
        f"{profile_id}.positional_multiplier_x",
        profile.get("positional_multiplier_x"),
        minimum=0.0,
        maximum=1.0,
    )
    _require_number(
        ctx,
        path,
        f"{profile_id}.positional_multiplier_y",
        profile.get("positional_multiplier_y"),
        minimum=0.0,
        maximum=1.0,
    )


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


def _validate_level_progression(ctx: ValidationContext) -> None:
    path = LEVEL_PROGRESSION_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _require_exact_int(ctx, path, "schema_version", data.get("schema_version"), 1)
    first_level_cost = _require_int(
        ctx, path, "first_level_cost", data.get("first_level_cost"), minimum=1
    )
    numerator = _require_int(
        ctx,
        path,
        "multiplier_numerator",
        data.get("multiplier_numerator"),
        minimum=1,
    )
    denominator = _require_int(
        ctx,
        path,
        "multiplier_denominator",
        data.get("multiplier_denominator"),
        minimum=1,
    )
    if (
        isinstance(numerator, int)
        and isinstance(denominator, int)
        and numerator <= denominator
    ):
        ctx.error(path, "multiplier_numerator", "must be greater than multiplier_denominator")


def _validate_reward_choice_pools(ctx: ValidationContext) -> None:
    path = REWARD_CHOICE_POOLS_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _require_exact_int(ctx, path, "schema_version", data.get("schema_version"), 1)
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
            kind = _require_non_empty_string(ctx, path, f"{entry_field}.kind", entry.get("kind"))
            if kind and kind != "stat_modifier":
                ctx.error(path, f"{entry_field}.kind", "must equal stat_modifier")
            _require_int(ctx, path, f"{entry_field}.weight", entry.get("weight"), minimum=1)
            if "min_level" in entry:
                _require_int(ctx, path, f"{entry_field}.min_level", entry.get("min_level"), minimum=1)
            if "modifiers" not in entry:
                ctx.error(path, f"{entry_field}.modifiers", "is required")
            else:
                _validate_modifiers(ctx, path, f"{entry_field}.modifiers", entry.get("modifiers"), require_value_per_level=False)


def _validate_enemy_rewards(ctx: ValidationContext) -> None:
    path = ENEMY_REWARDS_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _validate_exact_object_keys(
        ctx,
        path,
        "root",
        data,
        {
            "schema_version",
            "base_coefficient",
            "time_growth_per_tier",
            "random_multiplier_min",
            "random_multiplier_max",
        },
    )
    _require_exact_int(ctx, path, "schema_version", data.get("schema_version"), 1)
    _require_number(
        ctx,
        path,
        "base_coefficient",
        data.get("base_coefficient"),
        minimum=0.0,
        exclusive_minimum=True,
    )
    _require_number(
        ctx,
        path,
        "time_growth_per_tier",
        data.get("time_growth_per_tier"),
        minimum=0.0,
    )
    random_minimum = _require_number(
        ctx,
        path,
        "random_multiplier_min",
        data.get("random_multiplier_min"),
        minimum=0.0,
        exclusive_minimum=True,
    )
    random_maximum = _require_number(
        ctx,
        path,
        "random_multiplier_max",
        data.get("random_multiplier_max"),
        minimum=0.0,
        exclusive_minimum=True,
    )
    if (
        random_minimum is not None
        and random_maximum is not None
        and random_minimum > random_maximum
    ):
        ctx.error(
            path,
            "random_multiplier_min",
            "must be <= random_multiplier_max",
        )


def _validate_difficulty_profiles(ctx: ValidationContext) -> set[str]:
    path = DIFFICULTY_PROFILES_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return set()
    _validate_exact_object_keys(
        ctx,
        path,
        "root",
        data,
        {"schema_version", "profiles"},
    )
    _require_exact_int(ctx, path, "schema_version", data.get("schema_version"), 2)
    profiles = _require_list(ctx, path, "profiles", data.get("profiles"))
    if not profiles:
        ctx.error(path, "profiles", "must be a non-empty array")
    profile_ids: set[str] = set()
    for profile_index, profile in enumerate(profiles):
        profile_field = f"profiles[{profile_index}]"
        if not isinstance(profile, dict):
            ctx.error(path, profile_field, "must be an object")
            continue
        _validate_exact_object_keys(
            ctx,
            path,
            profile_field,
            profile,
            {
                "id",
                "name_key",
                "difficulty_coefficient",
                "tier_interval_seconds",
                "continuous_growth_per_interval",
                "tier_step_growth",
                "damage_growth_ratio",
                "stage_name_keys",
            },
        )
        profile_id = _require_non_empty_string(
            ctx, path, f"{profile_field}.id", profile.get("id")
        )
        if profile_id:
            if profile_id in profile_ids:
                ctx.error(
                    path,
                    f"{profile_field}.id",
                    f"duplicate difficulty profile id {profile_id}",
                )
            profile_ids.add(profile_id)
        _require_locale_key(
            ctx,
            path,
            f"{profile_field}.name_key",
            profile.get("name_key"),
        )
        _require_number(
            ctx,
            path,
            f"{profile_field}.difficulty_coefficient",
            profile.get("difficulty_coefficient"),
            minimum=0.0,
            exclusive_minimum=True,
        )
        _require_number(
            ctx,
            path,
            f"{profile_field}.tier_interval_seconds",
            profile.get("tier_interval_seconds"),
            minimum=0.0,
            maximum=3600.0,
            exclusive_minimum=True,
        )
        for field_name in (
            "continuous_growth_per_interval",
            "tier_step_growth",
            "damage_growth_ratio",
        ):
            _require_number(
                ctx,
                path,
                f"{profile_field}.{field_name}",
                profile.get(field_name),
                minimum=0.0,
                maximum=10.0,
            )
        stage_name_keys = _require_list(
            ctx,
            path,
            f"{profile_field}.stage_name_keys",
            profile.get("stage_name_keys"),
        )
        if len(stage_name_keys) != 9:
            ctx.error(
                path,
                f"{profile_field}.stage_name_keys",
                "must contain exactly 9 entries",
            )
        seen_name_keys: set[str] = set()
        for key_index, name_key in enumerate(stage_name_keys):
            key_field = f"{profile_field}.stage_name_keys[{key_index}]"
            _require_locale_key(ctx, path, key_field, name_key)
            if isinstance(name_key, str) and name_key:
                if name_key in seen_name_keys:
                    ctx.error(path, key_field, f"duplicate stage name key {name_key}")
                seen_name_keys.add(name_key)
    return profile_ids


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
    difficulty_profile_ids: set[str],
) -> None:
    path = GAME_MODES_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _require_exact_int(ctx, path, "schema_version", data.get("schema_version"), 3)
    modes = _require_list(ctx, path, "modes", data.get("modes"))
    if not modes:
        ctx.error(path, "modes", "must be a non-empty array")
    seen_modes: set[str] = set()
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
        difficulty_profile_id = _require_non_empty_string(
            ctx,
            path,
            f"{mode_field}.difficulty_profile_id",
            mode.get("difficulty_profile_id"),
        )
        if (
            difficulty_profile_id
            and difficulty_profile_id not in difficulty_profile_ids
        ):
            ctx.error(
                path,
                f"{mode_field}.difficulty_profile_id",
                "profile is not defined in difficulty_profiles.json: "
                f"{difficulty_profile_id}",
            )
        team_ids = _validate_mode_teams(ctx, path, mode_field, mode.get("teams"))
        _validate_mode_participants(ctx, path, mode_field, mode.get("participants"), team_ids)
        _validate_mode_resource_pools(ctx, path, mode_field, mode.get("resource_pools"), character_ids, weapon_ids, enemy_ids, hazard_ids, relic_ids, active_item_ids, consumable_ids, skill_ids)
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
) -> None:
    path = WARZONE_DIRECTORS_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=3, maximum=3)
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
        _reject_removed_field(ctx, path, director_field, director, "encounters", schema_version=2)
        _validate_warzone_interest_points(ctx, path, f"{director_field}.interest_points", director.get("interest_points"), hazard_ids, map_layout_ids)
        mode_wave_ids = wave_ids_by_mode.get(mode_id or "", set())
        referenced_waves = _validate_warzone_phases(ctx, path, director_field, director.get("phases"), mode_id or "", mode_wave_ids)
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
        _reject_removed_field(ctx, path, phase_field, phase, "encounter_ids", schema_version=2)
    return referenced_waves


def _validate_warzone_interest_points(
    ctx: ValidationContext,
    path: Path,
    field: str,
    data: Any,
    hazard_ids: dict[str, int],
    map_layout_ids: set[str],
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
        has_gold_reward = "gold_reward_amount" in point
        has_mod_pool = "gear_mod_pool_id" in point
        has_mod_rolls = "gear_mod_rolls" in point
        has_reward_payload = has_gold_reward or has_mod_pool or has_mod_rolls or completes_run
        if "claim_radius" in point or has_reward_payload:
            _require_number(ctx, path, f"{item_field}.claim_radius", point.get("claim_radius"), minimum=0, exclusive_minimum=True)
        if "claim_start_time" in point:
            _require_number(ctx, path, f"{item_field}.claim_start_time", point.get("claim_start_time"), minimum=0)
        if "requires_interaction" in point:
            _require_bool(ctx, path, f"{item_field}.requires_interaction", point.get("requires_interaction"))
        if "completes_run" in point:
            _require_bool(ctx, path, f"{item_field}.completes_run", point.get("completes_run"))
        if has_gold_reward:
            _require_int(ctx, path, f"{item_field}.gold_reward_amount", point.get("gold_reward_amount"), minimum=1)
        if has_mod_pool != has_mod_rolls:
            ctx.error(path, item_field, "must define gear_mod_pool_id and gear_mod_rolls together")
        if has_mod_pool:
            _require_registered(
                ctx,
                path,
                f"{item_field}.gear_mod_pool_id",
                point.get("gear_mod_pool_id"),
                "world_event_mod_pool_ids",
            )
        if has_mod_rolls:
            _require_int(ctx, path, f"{item_field}.gear_mod_rolls", point.get("gear_mod_rolls"), minimum=1)
        if completes_run and (has_gold_reward or has_mod_pool or has_mod_rolls):
            ctx.error(path, item_field, "run completion point must not define a reward payload")
        if "target_hp" in point:
            _require_number(ctx, path, f"{item_field}.target_hp", point.get("target_hp"), minimum=0, exclusive_minimum=True)
        if "target_hit_radius" in point:
            _require_number(ctx, path, f"{item_field}.target_hit_radius", point.get("target_hit_radius"), minimum=0, exclusive_minimum=True)
        for removed_field in (
            "resource_rewards",
            "gear_mod_rewards",
            "extraction_radius",
            "extraction_hold_time",
        ):
            _reject_removed_field(ctx, path, item_field, point, removed_field, schema_version=3)
        if "notes" in point:
            _require_non_empty_string(ctx, path, f"{item_field}.notes", point.get("notes"))


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
    if isinstance(height, (int, float)) and isinstance(cell_height, (int, float)):
        if not _is_nearly_grid_multiple(float(height), float(cell_height)):
            ctx.error(path, f"{field}.bounds.height", "must be an integer multiple of grid.cell_height")


def _validate_map_point(ctx: ValidationContext, path: Path, field: str, data: Any) -> None:
    if not isinstance(data, dict):
        ctx.error(path, field, "must be an object")
        return
    _require_number(ctx, path, f"{field}.x", data.get("x"))
    _require_number(ctx, path, f"{field}.y", data.get("y"))


def _validate_map_point_on_grid(ctx: ValidationContext, path: Path, field: str, point: Any, grid: Any) -> None:
    if _is_map_point_on_grid_center(point, grid):
        return
    ctx.error(path, field, "must be a rectangular grid center")


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
        ctx.error(path, field, "must be a rectangular grid center for odd radius_tiles")
        return
    if _is_map_point_on_grid_vertex(point, grid):
        return
    ctx.error(path, field, "must be a rectangular grid vertex for even radius_tiles")


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
    column = float(x) / max(float(cell_width), 1.0)
    row = float(y) / max(float(cell_height), 1.0)
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
    column = float(x) / max(float(cell_width), 1.0) - 0.5
    row = float(y) / max(float(cell_height), 1.0) - 0.5
    return _is_nearly_integer(column) and _is_nearly_integer(row)


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
        ctx.error(path, f"{field}.growth_pools", "was removed in schema_version 3")
    if "characters" not in data and "weapons" not in data and "enemies" not in data and "hazards" not in data and "relics" not in data and "active_items" not in data and "skills" not in data and "consumables" not in data:
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


def _validate_world_events(ctx: ValidationContext, _gear_mod_ids: set[str]) -> set[str]:
    path = WORLD_EVENTS_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return set()
    if set(data) != {"schema_version", "events"}:
        ctx.error(path, "root", "must define exactly schema_version and events")
    _require_exact_int(ctx, path, "schema_version", data.get("schema_version"), 2)

    mod_pool_ids = set(ctx.contracts.get("world_event_mod_pool_ids", []))

    events = _require_list(ctx, path, "events", data.get("events"))
    event_ids: set[str] = set()
    kinds: set[str] = set()
    expected_kind_by_id = {
        "world_event_defense": "world_event_kind_defense",
        "world_event_survival": "world_event_kind_survival",
        "world_event_capture": "world_event_kind_capture",
        "world_event_gold_shrine": "world_event_kind_gold_shrine",
        "world_event_blood_shrine": "world_event_kind_blood_shrine",
    }
    for event_index, event in enumerate(events):
        field = f"events[{event_index}]"
        if not isinstance(event, dict):
            ctx.error(path, field, "must be an object")
            continue
        event_id = _require_registered(
            ctx, path, f"{field}.id", event.get("id"), "world_event_ids"
        )
        kind = _require_registered(
            ctx, path, f"{field}.kind", event.get("kind"), "world_event_kinds"
        )
        if event_id:
            if event_id in event_ids:
                ctx.error(path, f"{field}.id", f"duplicate world event id {event_id}")
            event_ids.add(event_id)
        if kind:
            if kind in kinds:
                ctx.error(path, f"{field}.kind", f"duplicate world event kind {kind}")
            kinds.add(kind)
        if event_id and kind and expected_kind_by_id.get(event_id) != kind:
            ctx.error(path, f"{field}.kind", "must match the world event id")
        _require_locale_key(ctx, path, f"{field}.name_key", event.get("name_key"))
        _require_locale_key(ctx, path, f"{field}.desc_key", event.get("desc_key"))
        _require_number(
            ctx,
            path,
            f"{field}.interaction_radius",
            event.get("interaction_radius"),
            minimum=0.0,
            exclusive_minimum=True,
        )
        _validate_world_event_kind(ctx, path, field, event, kind, mod_pool_ids)
    if event_ids != set(ctx.contracts.get("world_event_ids", [])):
        ctx.error(path, "events", "must define every registered world_event_id exactly once")
    if kinds != set(ctx.contracts.get("world_event_kinds", [])):
        ctx.error(path, "events", "must define every registered world_event_kind exactly once")
    return event_ids


def _validate_world_event_kind(
    ctx: ValidationContext,
    path: Path,
    field: str,
    event: dict[str, Any],
    kind: str | None,
    mod_pool_ids: set[str],
) -> None:
    common = {"id", "kind", "name_key", "desc_key", "interaction_radius"}
    specific: dict[str, set[str]] = {
        "world_event_kind_defense": {
            "duration", "waves", "target_max_health", "target_hit_radius", "completion_reward"
        },
        "world_event_kind_survival": {"duration", "waves", "completion_reward"},
        "world_event_kind_capture": {
            "capture_radius", "entry_delay", "entry_delay_decay", "capture_duration",
            "timeout", "waves", "completion_reward",
        },
        "world_event_kind_gold_shrine": {
            "base_cost", "cost_multiplier", "success_chance", "max_successes", "mod_pool_id"
        },
        "world_event_kind_blood_shrine": {"sacrifice_ratios", "gold_ratio"},
    }
    expected = common | specific.get(kind or "", set())
    if set(event) != expected:
        ctx.error(path, field, f"fields must exactly match {kind or 'registered world event kind'} schema")
    if kind in {"world_event_kind_defense", "world_event_kind_survival"}:
        duration = _require_number(
            ctx, path, f"{field}.duration", event.get("duration"),
            minimum=0.0, exclusive_minimum=True,
        )
        _validate_world_event_waves(ctx, path, f"{field}.waves", event.get("waves"), duration)
        _validate_world_event_completion_reward(
            ctx, path, f"{field}.completion_reward", event.get("completion_reward"), mod_pool_ids
        )
        if kind == "world_event_kind_defense":
            _require_number(
                ctx, path, f"{field}.target_max_health", event.get("target_max_health"),
                minimum=0.0, exclusive_minimum=True,
            )
            _require_number(
                ctx, path, f"{field}.target_hit_radius", event.get("target_hit_radius"),
                minimum=0.0, exclusive_minimum=True,
            )
    elif kind == "world_event_kind_capture":
        values: dict[str, float | None] = {}
        for key in (
            "capture_radius", "entry_delay", "entry_delay_decay", "capture_duration", "timeout"
        ):
            values[key] = _require_number(
                ctx, path, f"{field}.{key}", event.get(key),
                minimum=0.0, exclusive_minimum=True,
            )
        _validate_world_event_waves(
            ctx, path, f"{field}.waves", event.get("waves"), values["capture_duration"]
        )
        _validate_world_event_completion_reward(
            ctx, path, f"{field}.completion_reward", event.get("completion_reward"), mod_pool_ids
        )
    elif kind == "world_event_kind_gold_shrine":
        _require_int(ctx, path, f"{field}.base_cost", event.get("base_cost"), minimum=1)
        _require_number(
            ctx, path, f"{field}.cost_multiplier", event.get("cost_multiplier"),
            minimum=1.0, exclusive_minimum=True,
        )
        chance = _require_number(
            ctx, path, f"{field}.success_chance", event.get("success_chance"),
            minimum=0.0, maximum=1.0, exclusive_minimum=True,
        )
        if chance is not None and chance >= 1.0:
            ctx.error(path, f"{field}.success_chance", "must be < 1.0")
        _require_int(ctx, path, f"{field}.max_successes", event.get("max_successes"), minimum=1)
        _validate_world_event_mod_pool_reference(
            ctx, path, f"{field}.mod_pool_id", event.get("mod_pool_id"), mod_pool_ids
        )
    elif kind == "world_event_kind_blood_shrine":
        ratios = _require_list(ctx, path, f"{field}.sacrifice_ratios", event.get("sacrifice_ratios"))
        if len(ratios) != 3:
            ctx.error(path, f"{field}.sacrifice_ratios", "must contain exactly three ratios")
        previous = 0.0
        for ratio_index, raw_ratio in enumerate(ratios):
            ratio_field = f"{field}.sacrifice_ratios[{ratio_index}]"
            ratio = _require_number(
                ctx, path, ratio_field, raw_ratio,
                minimum=0.0, maximum=1.0, exclusive_minimum=True,
            )
            if ratio is not None:
                if ratio >= 1.0:
                    ctx.error(path, ratio_field, "must be < 1.0")
                if ratio <= previous:
                    ctx.error(path, ratio_field, "must be strictly increasing")
                previous = ratio
        gold_ratio = _require_number(
            ctx, path, f"{field}.gold_ratio", event.get("gold_ratio"),
            minimum=0.0, maximum=1.0, exclusive_minimum=True,
        )
        if gold_ratio is not None and gold_ratio >= 1.0:
            ctx.error(path, f"{field}.gold_ratio", "must be < 1.0")


def _validate_world_event_waves(
    ctx: ValidationContext,
    path: Path,
    field: str,
    value: Any,
    maximum_trigger: float | None,
) -> None:
    waves = _require_list(ctx, path, field, value)
    if not waves:
        ctx.error(path, field, "must be a non-empty array")
    previous = -1.0
    for wave_index, wave in enumerate(waves):
        wave_field = f"{field}[{wave_index}]"
        if not isinstance(wave, dict):
            ctx.error(path, wave_field, "must be an object")
            continue
        if set(wave) != {"trigger", "count"}:
            ctx.error(path, wave_field, "must define exactly trigger and count")
        trigger = _require_number(
            ctx, path, f"{wave_field}.trigger", wave.get("trigger"),
            minimum=0.0, maximum=maximum_trigger,
        )
        _require_int(ctx, path, f"{wave_field}.count", wave.get("count"), minimum=1)
        if trigger is not None:
            if trigger < previous:
                ctx.error(path, f"{wave_field}.trigger", "must be non-decreasing")
            previous = trigger
    if waves and (not isinstance(waves[0], dict) or waves[0].get("trigger") != 0):
        ctx.error(path, f"{field}[0].trigger", "must be 0")


def _validate_world_event_completion_reward(
    ctx: ValidationContext,
    path: Path,
    field: str,
    value: Any,
    mod_pool_ids: set[str],
) -> None:
    if not isinstance(value, dict):
        ctx.error(path, field, "must be an object")
        return
    if set(value) != {"mod_pool_id"}:
        ctx.error(path, field, "must define exactly mod_pool_id")
    _validate_world_event_mod_pool_reference(
        ctx, path, f"{field}.mod_pool_id", value.get("mod_pool_id"), mod_pool_ids
    )


def _validate_world_event_mod_pool_reference(
    ctx: ValidationContext,
    path: Path,
    field: str,
    value: Any,
    mod_pool_ids: set[str],
) -> None:
    pool_id = _require_registered(ctx, path, field, value, "world_event_mod_pool_ids")
    if pool_id and pool_id not in mod_pool_ids:
        ctx.error(path, field, f"mod pool is not defined in gear_mods.json: {pool_id}")


def _validate_content_tags(ctx: ValidationContext, path: Path, field: str, value: Any) -> None:
    tags = _require_list(ctx, path, field, value)
    for tag_index, tag in enumerate(tags):
        _require_registered(ctx, path, f"{field}[{tag_index}]", tag, "content_tags")


def _validate_module_tile_catalog(ctx: ValidationContext) -> dict[str, str]:
    path = MODULE_TILE_CATALOG_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return {}
    _require_exact_int(ctx, path, "schema_version", data.get("schema_version"), 1)
    tile_set_path = _require_non_empty_string(ctx, path, "tile_set_path", data.get("tile_set_path"))
    if tile_set_path is not None:
        if not tile_set_path.startswith("res://resources/modules/") or not tile_set_path.endswith(".tres"):
            ctx.error(path, "tile_set_path", "must be a res://resources/modules/*.tres path")
        elif not (ROOT / "client" / tile_set_path.removeprefix("res://")).is_file():
            ctx.error(path, "tile_set_path", "referenced TileSet must exist")
    tiles = _require_list(ctx, path, "tiles", data.get("tiles"))
    catalog: dict[str, str] = {}
    for index, tile in enumerate(tiles):
        field = f"tiles[{index}]"
        if not isinstance(tile, dict):
            ctx.error(path, field, "must be an object")
            continue
        tile_id = _require_registered(ctx, path, f"{field}.id", tile.get("id"), "module_tile_ids")
        layer = _require_non_empty_string(ctx, path, f"{field}.layer", tile.get("layer"))
        if layer not in {"ground", "obstacles", "decoration"}:
            ctx.error(path, f"{field}.layer", "must be ground, obstacles, or decoration")
        if tile_id:
            if tile_id in catalog:
                ctx.error(path, f"{field}.id", f"duplicate tile id {tile_id}")
            catalog[tile_id] = layer or ""
        _require_int(ctx, path, f"{field}.source_id", tile.get("source_id"), minimum=0)
        _validate_module_cell(ctx, path, f"{field}.atlas_coords", tile.get("atlas_coords"), 1_000_000, 1_000_000)
        alternative_id = _require_int(ctx, path, f"{field}.alternative_id", tile.get("alternative_id"), minimum=0)
        if alternative_id is not None and alternative_id >= 4096:
            ctx.error(path, f"{field}.alternative_id", "must be < 4096 because higher bits are reserved for transforms")
    expected_ids = set(ctx.contracts.get("module_tile_ids", []))
    if set(catalog) != expected_ids:
        ctx.error(path, "tiles", "must define every registered module_tile_id exactly once")
    return catalog


def _validate_module_world_data(
    ctx: ValidationContext,
    enemy_ids: set[str],
    hazard_ids: set[str],
    world_event_ids: set[str],
    module_tile_catalog: dict[str, str],
) -> None:
    templates = _validate_module_templates(
        ctx, hazard_ids, world_event_ids, module_tile_catalog
    )
    path = MODULE_WORLDS_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return
    _require_exact_int(ctx, path, "schema_version", data.get("schema_version"), 5)
    worlds = _require_list(ctx, path, "worlds", data.get("worlds"))
    if not worlds:
        ctx.error(path, "worlds", "must be a non-empty array")
    seen_worlds: set[str] = set()
    for world_index, world in enumerate(worlds):
        field = f"worlds[{world_index}]"
        if not isinstance(world, dict):
            ctx.error(path, field, "must be an object")
            continue
        world_id = _require_non_empty_string(ctx, path, f"{field}.id", world.get("id"))
        if world_id:
            if world_id in seen_worlds:
                ctx.error(path, f"{field}.id", f"duplicate world id {world_id}")
            seen_worlds.add(world_id)
        columns = _require_exact_int(ctx, path, f"{field}.columns", world.get("columns"), 7)
        rows = _require_exact_int(ctx, path, f"{field}.rows", world.get("rows"), 7)
        _require_exact_int(ctx, path, f"{field}.module_columns", world.get("module_columns"), 11)
        _require_exact_int(ctx, path, f"{field}.module_rows", world.get("module_rows"), 11)
        _require_number(ctx, path, f"{field}.cell_size", world.get("cell_size"), minimum=0.0, exclusive_minimum=True)
        _require_exact_int(ctx, path, f"{field}.active_radius", world.get("active_radius"), 1)
        seal_outer_edges = _require_bool(ctx, path, f"{field}.seal_outer_edges", world.get("seal_outer_edges"))
        if seal_outer_edges is False:
            ctx.error(path, f"{field}.seal_outer_edges", "must be true")
        if columns != 7 or rows != 7:
            continue

        anchors: dict[str, tuple[int, int] | None] = {
            "start_slot": _validate_module_cell(
                ctx, path, f"{field}.start_slot", world.get("start_slot"), 7, 7
            )
        }
        objective_spawn = _validate_module_objective_spawn(
            ctx,
            path,
            f"{field}.objective_spawn",
            world.get("objective_spawn"),
            templates,
            anchors["start_slot"],
        )
        route_budget = _validate_module_route_budget(ctx, path, f"{field}.route_budget", world.get("route_budget"))
        if route_budget.get("start_to_objective") != (6, 12):
            ctx.error(path, f"{field}.route_budget.start_to_objective", "must be 6..12 crossings")
        if route_budget.get("main_route_modules") != (7, 13):
            ctx.error(path, f"{field}.route_budget.main_route_modules", "must be 7..13 modules")
        required_spawn_cells = _validate_first_visit_enemy_spawn(
            ctx,
            path,
            f"{field}.first_visit_enemy_spawn",
            world.get("first_visit_enemy_spawn"),
            enemy_ids,
        )

        fixed_slots = _require_list(ctx, path, f"{field}.fixed_slots", world.get("fixed_slots"))
        fixed_assignment = _validate_module_assignment_entries(
            ctx,
            path,
            f"{field}.fixed_slots",
            fixed_slots,
            templates,
            exact_49=False,
            allow_technical_sealed=False,
        )
        _validate_module_fixed_anchor_roles(
            ctx, path, f"{field}.fixed_slots", fixed_assignment, templates, anchors
        )
        for template_id, _rotation in fixed_assignment.values():
            template = templates.get(template_id)
            if template is None or template.get("role") == "module_role_start":
                continue
            if _module_spawnable_cell_count(template) < required_spawn_cells:
                ctx.error(
                    path,
                    f"{field}.fixed_slots",
                    f"non-start fixed templates need at least {required_spawn_cells} spawnable floor cells",
                )

        template_pool = _require_list(ctx, path, f"{field}.template_pool", world.get("template_pool"))
        seen_pool: set[str] = set()
        for pool_index, value in enumerate(template_pool):
            pool_field = f"{field}.template_pool[{pool_index}]"
            template_id = _require_non_empty_string(ctx, path, pool_field, value)
            if template_id is None:
                continue
            if template_id in seen_pool:
                ctx.error(path, pool_field, f"duplicate template id {template_id}")
            seen_pool.add(template_id)
            template = templates.get(template_id)
            if template is None:
                ctx.error(path, pool_field, f"template is not defined in module_templates.json: {template_id}")
            elif template["review_status"] != "module_review_approved":
                ctx.error(path, pool_field, f"formal template pool requires approved template: {template_id}")
            elif template["role"] == "module_role_sealed":
                ctx.error(path, pool_field, "formal template pool cannot contain sealed templates")
            elif _module_spawnable_cell_count(template) < required_spawn_cells:
                ctx.error(
                    path,
                    pool_field,
                    f"formal template needs at least {required_spawn_cells} spawnable floor cells",
                )
        _validate_module_limited_template_groups(
            ctx,
            path,
            f"{field}.limited_template_groups",
            world.get("limited_template_groups"),
            templates,
            required_spawn_cells,
            49 - len(fixed_assignment) - 1,
        )

        for assignment_name, technical in (("fallback_assignment", False), ("technical_slice_assignment", True)):
            entries = _require_list(ctx, path, f"{field}.{assignment_name}", world.get(assignment_name))
            assignment = _validate_module_assignment_entries(
                ctx,
                path,
                f"{field}.{assignment_name}",
                entries,
                templates,
                exact_49=True,
                allow_technical_sealed=technical,
            )
            if not technical:
                for template_id, _rotation in assignment.values():
                    template = templates.get(template_id)
                    if template is None or template.get("role") == "module_role_start":
                        continue
                    if _module_spawnable_cell_count(template) < required_spawn_cells:
                        ctx.error(
                            path,
                            f"{field}.{assignment_name}",
                            "non-start fallback templates need at least "
                            f"{required_spawn_cells} spawnable floor cells",
                        )
            if technical:
                _validate_module_assignment_world(
                    ctx,
                    path,
                    f"{field}.{assignment_name}",
                    assignment,
                    templates,
                    anchors,
                    {},
                    True,
                )
            else:
                for candidate_index, candidate in enumerate(objective_spawn.get("candidate_slots", [])):
                    candidate_assignment = dict(assignment)
                    candidate_assignment[candidate] = (
                        objective_spawn.get("template_id", ""),
                        objective_spawn.get("rotation", 0),
                    )
                    candidate_anchors = dict(anchors)
                    candidate_anchors["objective_slot"] = candidate
                    _validate_module_assignment_world(
                        ctx,
                        path,
                        f"{field}.{assignment_name}.objective_candidate[{candidate_index}]",
                        candidate_assignment,
                        templates,
                        candidate_anchors,
                        route_budget,
                        False,
                    )


def _validate_module_limited_template_groups(
    ctx: ValidationContext,
    path: Path,
    field: str,
    value: Any,
    templates: dict[str, dict[str, Any]],
    required_spawn_cells: int,
    available_slots: int,
) -> None:
    groups = _require_list(ctx, path, field, value)
    if not groups:
        ctx.error(path, field, "must be a non-empty array")
    seen_group_ids: set[str] = set()
    seen_template_ids: set[str] = set()
    selected_slots = 0
    for group_index, group in enumerate(groups):
        group_field = f"{field}[{group_index}]"
        if not isinstance(group, dict):
            ctx.error(path, group_field, "must be an object")
            continue
        if set(group) != {"id", "pick_distinct", "entries"}:
            ctx.error(path, group_field, "must define exactly id, pick_distinct, and entries")
        group_id = _require_non_empty_string(ctx, path, f"{group_field}.id", group.get("id"))
        if group_id:
            if group_id in seen_group_ids:
                ctx.error(path, f"{group_field}.id", f"duplicate group id {group_id}")
            seen_group_ids.add(group_id)
        entries = _require_list(ctx, path, f"{group_field}.entries", group.get("entries"))
        pick_distinct = _require_int(
            ctx, path, f"{group_field}.pick_distinct", group.get("pick_distinct"), minimum=1
        )
        if pick_distinct is not None and pick_distinct > len(entries):
            ctx.error(path, f"{group_field}.pick_distinct", "must not exceed entries length")
        counts: list[int] = []
        for entry_index, entry in enumerate(entries):
            entry_field = f"{group_field}.entries[{entry_index}]"
            if not isinstance(entry, dict):
                ctx.error(path, entry_field, "must be an object")
                continue
            if set(entry) != {"template_id", "weight", "count_per_floor"}:
                ctx.error(
                    path,
                    entry_field,
                    "must define exactly template_id, weight, and count_per_floor",
                )
            template_id = _require_non_empty_string(
                ctx, path, f"{entry_field}.template_id", entry.get("template_id")
            )
            if template_id:
                if template_id in seen_template_ids:
                    ctx.error(
                        path,
                        f"{entry_field}.template_id",
                        f"duplicate limited template id {template_id}",
                    )
                seen_template_ids.add(template_id)
            _require_number(
                ctx,
                path,
                f"{entry_field}.weight",
                entry.get("weight"),
                minimum=0.0,
                exclusive_minimum=True,
            )
            count = _require_int(
                ctx,
                path,
                f"{entry_field}.count_per_floor",
                entry.get("count_per_floor"),
                minimum=1,
            )
            counts.append(count if count is not None else available_slots + 1)
            template = templates.get(template_id or "")
            if template is None:
                ctx.error(
                    path,
                    f"{entry_field}.template_id",
                    f"template is not defined in module_templates.json: {template_id}",
                )
                continue
            if template.get("review_status") != "module_review_approved":
                ctx.error(path, f"{entry_field}.template_id", "template must be approved")
            if template.get("role") != "module_role_world_event":
                ctx.error(path, f"{entry_field}.template_id", "template must use module_role_world_event")
            if _module_spawnable_cell_count(template) < required_spawn_cells:
                ctx.error(
                    path,
                    f"{entry_field}.template_id",
                    f"template needs at least {required_spawn_cells} spawnable floor cells",
                )
        if pick_distinct is not None:
            selected_slots += sum(sorted(counts, reverse=True)[:pick_distinct])
    if selected_slots > available_slots:
        ctx.error(path, field, f"selected templates exceed {available_slots} available slots")


def _validate_first_visit_enemy_spawn(
    ctx: ValidationContext,
    path: Path,
    field: str,
    value: Any,
    enemy_ids: set[str],
) -> int:
    if not isinstance(value, dict):
        ctx.error(path, field, "must be an object")
        return 0
    count_min = _require_int(
        ctx, path, f"{field}.count_min", value.get("count_min"), minimum=1
    )
    count_max = _require_int(
        ctx, path, f"{field}.count_max", value.get("count_max"), minimum=1
    )
    if count_min is not None and count_max is not None and count_min > count_max:
        ctx.error(path, field, "count_min must be <= count_max")
    _require_number(
        ctx,
        path,
        f"{field}.telegraph_duration",
        value.get("telegraph_duration"),
        minimum=0.0,
        exclusive_minimum=True,
    )
    enemy_pool = _require_list(ctx, path, f"{field}.enemy_pool", value.get("enemy_pool"))
    if not enemy_pool:
        ctx.error(path, f"{field}.enemy_pool", "must be a non-empty array")
    seen_enemy_ids: set[str] = set()
    previous_unlock_time = -1.0
    for index, raw_entry in enumerate(enemy_pool):
        entry_field = f"{field}.enemy_pool[{index}]"
        if not isinstance(raw_entry, dict):
            ctx.error(path, entry_field, "must be an object")
            continue
        enemy_id = _require_non_empty_string(
            ctx, path, f"{entry_field}.enemy_id", raw_entry.get("enemy_id")
        )
        if enemy_id is not None:
            if enemy_id in seen_enemy_ids:
                ctx.error(path, f"{entry_field}.enemy_id", f"duplicate enemy id {enemy_id}")
            seen_enemy_ids.add(enemy_id)
            if enemy_id not in enemy_ids:
                ctx.error(
                    path,
                    f"{entry_field}.enemy_id",
                    f"enemy is not defined in enemies.csv: {enemy_id}",
                )
        unlock_time = _require_number(
            ctx,
            path,
            f"{entry_field}.unlock_time",
            raw_entry.get("unlock_time"),
            minimum=0.0,
        )
        if unlock_time is not None:
            if unlock_time < previous_unlock_time:
                ctx.error(
                    path,
                    f"{entry_field}.unlock_time",
                    "unlock times must be non-decreasing",
                )
            previous_unlock_time = unlock_time
        _require_number(
            ctx,
            path,
            f"{entry_field}.weight",
            raw_entry.get("weight"),
            minimum=0.0,
            exclusive_minimum=True,
        )
    if enemy_pool:
        first_entry = enemy_pool[0]
        first_unlock = first_entry.get("unlock_time") if isinstance(first_entry, dict) else None
        if not isinstance(first_unlock, (int, float)) or isinstance(first_unlock, bool) or float(first_unlock) != 0.0:
            ctx.error(path, f"{field}.enemy_pool[0].unlock_time", "must be 0")
    return count_max or 0


def _module_spawnable_cell_count(template: dict[str, Any]) -> int:
    module_data = template.get("data")
    if not isinstance(module_data, dict):
        return 0
    occupied: set[tuple[int, int]] = set()
    placements = module_data.get("placements")
    if isinstance(placements, list):
        for placement in placements:
            if not isinstance(placement, dict):
                continue
            cell = placement.get("cell")
            if not isinstance(cell, dict):
                continue
            x = cell.get("x")
            y = cell.get("y")
            if not isinstance(x, int) or isinstance(x, bool) or not isinstance(y, int) or isinstance(y, bool):
                continue
            footprint = placement.get("footprint")
            width = footprint.get("width", 1) if isinstance(footprint, dict) else 1
            height = footprint.get("height", 1) if isinstance(footprint, dict) else 1
            if not isinstance(width, int) or isinstance(width, bool) or width < 1:
                width = 1
            if not isinstance(height, int) or isinstance(height, bool) or height < 1:
                height = 1
            occupied.update(
                (x + offset_x, y + offset_y)
                for offset_y in range(height)
                for offset_x in range(width)
            )
    terrain_rows = module_data.get("terrain_rows")
    if not isinstance(terrain_rows, list):
        return 0
    return sum(
        1
        for y, row in enumerate(terrain_rows)
        if isinstance(row, list)
        for x, token in enumerate(row)
        if token == "module_cell_floor" and (x, y) not in occupied
    )


def _validate_module_templates(
    ctx: ValidationContext,
    hazard_ids: set[str],
    world_event_ids: set[str],
    module_tile_catalog: dict[str, str],
) -> dict[str, dict[str, Any]]:
    path = MODULE_TEMPLATES_JSON
    data = _load_json(path, ctx)
    if not isinstance(data, dict):
        return {}
    _require_exact_int(ctx, path, "schema_version", data.get("schema_version"), 2)
    entries = _require_list(ctx, path, "templates", data.get("templates"))
    if not entries:
        ctx.error(path, "templates", "must be a non-empty array")
    templates: dict[str, dict[str, Any]] = {}
    seen_paths: set[Path] = set()
    for index, entry in enumerate(entries):
        field = f"templates[{index}]"
        if not isinstance(entry, dict):
            ctx.error(path, field, "must be an object")
            continue
        template_id = _require_non_empty_string(ctx, path, f"{field}.id", entry.get("id"))
        role = _require_registered(ctx, path, f"{field}.role", entry.get("role"), "module_roles")
        source = _require_non_empty_string(ctx, path, f"{field}.source", entry.get("source"))
        if source is not None and source != "ai":
            ctx.error(path, f"{field}.source", "must be ai")
        review_status = _require_registered(
            ctx, path, f"{field}.review_status", entry.get("review_status"), "module_review_statuses"
        )
        approved_gameplay_hash = entry.get("approved_gameplay_hash")
        if "approved_source_hash" in entry:
            ctx.error(path, f"{field}.approved_source_hash", "field was replaced by approved_gameplay_hash in schema v2")
        if review_status == "module_review_approved":
            if not isinstance(approved_gameplay_hash, str) or re.fullmatch(r"[0-9a-f]{64}", approved_gameplay_hash) is None:
                ctx.error(path, f"{field}.approved_gameplay_hash", "approved template must store a gameplay approval sha256")
        elif "approved_gameplay_hash" in entry:
            ctx.error(path, f"{field}.approved_gameplay_hash", "must be omitted unless the template is approved")
        _validate_content_tags(ctx, path, f"{field}.tags", entry.get("tags", []))
        rotations = _require_list(ctx, path, f"{field}.allowed_rotations", entry.get("allowed_rotations"))
        allowed_rotations: set[int] = set()
        if not rotations:
            ctx.error(path, f"{field}.allowed_rotations", "must be a non-empty array")
        for rotation_index, rotation in enumerate(rotations):
            rotation_field = f"{field}.allowed_rotations[{rotation_index}]"
            if not isinstance(rotation, int) or isinstance(rotation, bool) or rotation not in (0, 90, 180, 270):
                ctx.error(path, rotation_field, "rotation must be one of 0, 90, 180, 270")
                continue
            if rotation in allowed_rotations:
                ctx.error(path, rotation_field, f"duplicate rotation {rotation}")
            allowed_rotations.add(rotation)

        module_path = _resolve_module_template_path(ctx, path, f"{field}.path", entry.get("path"))
        module_data: dict[str, Any] | None = None
        if module_path is not None:
            if module_path in seen_paths:
                ctx.error(path, f"{field}.path", f"duplicate module path {_rel(module_path)}")
            seen_paths.add(module_path)
            loaded = _load_json(module_path, ctx)
            if isinstance(loaded, dict):
                module_data = loaded
                _validate_module_file(
                    ctx,
                    module_path,
                    loaded,
                    template_id,
                    role,
                    hazard_ids,
                    world_event_ids,
                    module_tile_catalog,
                )
        if template_id:
            if template_id in templates:
                ctx.error(path, f"{field}.id", f"duplicate template id {template_id}")
            templates[template_id] = {
                "role": role,
                "review_status": review_status,
                "allowed_rotations": allowed_rotations,
                "data": module_data,
            }
    return templates


def _resolve_module_template_path(ctx: ValidationContext, registry_path: Path, field: str, value: Any) -> Path | None:
    resource_path = _require_non_empty_string(ctx, registry_path, field, value)
    if resource_path is None:
        return None
    if not resource_path.startswith("res://data/modules/") or not resource_path.endswith(".json"):
        ctx.error(registry_path, field, "must be a res://data/modules/*.json path")
        return None
    resolved = (ROOT / "client" / resource_path.removeprefix("res://")).resolve()
    try:
        resolved.relative_to(MODULES_DIR.resolve())
    except ValueError:
        ctx.error(registry_path, field, "module path must stay inside client/data/modules")
        return None
    if not resolved.is_file():
        ctx.error(registry_path, field, f"module file is missing: {resource_path}")
        return None
    return resolved


def _validate_module_file(
    ctx: ValidationContext,
    path: Path,
    data: dict[str, Any],
    expected_id: str | None,
    role: str | None,
    hazard_ids: set[str],
    world_event_ids: set[str],
    module_tile_catalog: dict[str, str],
) -> None:
    schema_version = _require_int(ctx, path, "schema_version", data.get("schema_version"), minimum=4)
    if schema_version != 4:
        ctx.error(path, "schema_version", "must be 4")
    module_id = _require_non_empty_string(ctx, path, "id", data.get("id"))
    if module_id and expected_id and module_id != expected_id:
        ctx.error(path, "id", f"must match registry template id {expected_id}")
    _require_exact_int(ctx, path, "columns", data.get("columns"), 11)
    _require_exact_int(ctx, path, "rows", data.get("rows"), 11)
    terrain_rows = _require_list(ctx, path, "terrain_rows", data.get("terrain_rows"))
    if len(terrain_rows) != 11:
        ctx.error(path, "terrain_rows", "must contain exactly 11 rows")
    for y, row in enumerate(terrain_rows):
        row_field = f"terrain_rows[{y}]"
        cells = _require_list(ctx, path, row_field, row)
        if len(cells) != 11:
            ctx.error(path, row_field, "must contain exactly 11 terrain tokens")
        for x, token in enumerate(cells):
            _require_registered(ctx, path, f"{row_field}[{x}]", token, "module_cell_tokens")

    derived_sockets = _derive_module_edge_sockets(terrain_rows)
    if schema_version == 4:
        if "edge_sockets" in data:
            ctx.error(path, "edge_sockets", "must be omitted in schema v4 because sockets are derived")
        _validate_module_visual_layers(ctx, path, data.get("visual_layers"), module_tile_catalog)
        data["edge_sockets"] = derived_sockets

    placements = _require_list(ctx, path, "placements", data.get("placements"))
    placement_counts: dict[str, int] = {}
    footprint_by_type: list[tuple[str, set[tuple[int, int]]]] = []
    start_cell: tuple[int, int] | None = None
    danger_cells: set[tuple[int, int]] = set()
    for index, placement in enumerate(placements):
        field = f"placements[{index}]"
        if not isinstance(placement, dict):
            ctx.error(path, field, "must be an object")
            continue
        placement_type = _require_registered(
            ctx, path, f"{field}.type", placement.get("type"), "module_placement_types"
        )
        cell = _validate_module_cell(ctx, path, f"{field}.cell", placement.get("cell"), 11, 11)
        footprint = _validate_module_footprint(ctx, path, f"{field}.footprint", placement.get("footprint"), cell)
        if placement_type:
            placement_counts[placement_type] = placement_counts.get(placement_type, 0) + 1
            footprint_by_type.append((placement_type, footprint))
        if placement_type == "module_place_player_start":
            start_cell = cell
        elif placement_type == "module_place_hazard":
            hazard_id = _require_non_empty_string(ctx, path, f"{field}.hazard_id", placement.get("hazard_id"))
            if hazard_id and hazard_id not in hazard_ids:
                ctx.error(path, f"{field}.hazard_id", f"hazard is not defined in hazards.csv: {hazard_id}")
            danger_cells.update(footprint)
        elif placement_type == "module_place_reward_cache":
            has_gold_reward = "gold_reward_amount" in placement
            has_mod_pool = "gear_mod_pool_id" in placement
            has_mod_rolls = "gear_mod_rolls" in placement
            if has_gold_reward:
                _require_int(ctx, path, f"{field}.gold_reward_amount", placement.get("gold_reward_amount"), minimum=1)
            if has_mod_pool != has_mod_rolls:
                ctx.error(path, field, "must define gear_mod_pool_id and gear_mod_rolls together")
            if has_mod_pool:
                _require_registered(
                    ctx,
                    path,
                    f"{field}.gear_mod_pool_id",
                    placement.get("gear_mod_pool_id"),
                    "world_event_mod_pool_ids",
                )
            if has_mod_rolls:
                _require_int(ctx, path, f"{field}.gear_mod_rolls", placement.get("gear_mod_rolls"), minimum=1)
            if not has_gold_reward and not (has_mod_pool and has_mod_rolls):
                ctx.error(path, field, "must define a gold reward or Gear Mod pool reward")
            if "resource_rewards" in placement:
                ctx.error(path, f"{field}.resource_rewards", "was removed; use gold_reward_amount or Gear Mod pool fields")
            _require_number(ctx, path, f"{field}.claim_radius", placement.get("claim_radius"), minimum=0.0, exclusive_minimum=True)
        elif placement_type == "module_place_objective":
            _require_number(ctx, path, f"{field}.target_hp", placement.get("target_hp"), minimum=0.0, exclusive_minimum=True)
            _require_number(ctx, path, f"{field}.target_hit_radius", placement.get("target_hit_radius"), minimum=0.0, exclusive_minimum=True)
        elif placement_type == "module_place_world_event":
            if set(placement) != {"type", "cell", "world_event_id"}:
                ctx.error(path, field, "must define exactly type, cell, and world_event_id")
            world_event_id = _require_registered(
                ctx,
                path,
                f"{field}.world_event_id",
                placement.get("world_event_id"),
                "world_event_ids",
            )
            if world_event_id and world_event_id not in world_event_ids:
                ctx.error(
                    path,
                    f"{field}.world_event_id",
                    f"world event is not defined in world_events.json: {world_event_id}",
                )

    protected_types = {
        "module_place_player_start",
        "module_place_reward_cache",
        "module_place_objective",
        "module_place_world_event",
    }
    danger_types = {"module_place_hazard"}
    for left_index, (left_type, left_cells) in enumerate(footprint_by_type):
        for right_type, right_cells in footprint_by_type[left_index + 1:]:
            if ((left_type in danger_types and right_type in protected_types) or
                    (right_type in danger_types and left_type in protected_types)) and left_cells & right_cells:
                ctx.error(path, "placements", "danger placement overlaps player start, objective, or reward")

    _validate_module_role_budget(ctx, path, role, placement_counts)
    if role == "module_role_start" and start_cell is not None:
        if any(max(abs(cell[0] - start_cell[0]), abs(cell[1] - start_cell[1])) <= 2 for cell in danger_cells):
            ctx.error(path, "placements", "player start must have a 2-cell danger-free safe radius")


def _derive_module_edge_sockets(terrain_rows: list[Any]) -> dict[str, list[int]]:
    floor = "module_cell_floor"
    if len(terrain_rows) != 11 or any(not isinstance(row, list) or len(row) != 11 for row in terrain_rows):
        return {"edge_north": [], "edge_south": [], "edge_east": [], "edge_west": []}
    return {
        "edge_north": [index for index in range(11) if terrain_rows[0][index] == floor],
        "edge_south": [index for index in range(11) if terrain_rows[10][index] == floor],
        "edge_east": [index for index in range(11) if terrain_rows[index][10] == floor],
        "edge_west": [index for index in range(11) if terrain_rows[index][0] == floor],
    }


def _validate_module_visual_layers(
    ctx: ValidationContext,
    path: Path,
    value: Any,
    module_tile_catalog: dict[str, str],
) -> None:
    if not isinstance(value, dict):
        ctx.error(path, "visual_layers", "must be an object")
        return
    if set(value) != {"ground", "obstacles", "decoration"}:
        ctx.error(path, "visual_layers", "must define exactly ground, obstacles, and decoration")
    for layer in ("ground", "obstacles"):
        layer_value = value.get(layer)
        field = f"visual_layers.{layer}"
        if not isinstance(layer_value, dict):
            ctx.error(path, field, "must be an object")
            continue
        if set(layer_value) != {"default_tile_id", "overrides"}:
            ctx.error(path, field, "must define exactly default_tile_id and overrides")
        _validate_module_tile_reference(
            ctx,
            path,
            f"{field}.default_tile_id",
            layer_value.get("default_tile_id"),
            layer,
            module_tile_catalog,
        )
        overrides = _require_list(ctx, path, f"{field}.overrides", layer_value.get("overrides"))
        _validate_module_visual_cells(ctx, path, f"{field}.overrides", overrides, layer, module_tile_catalog)
    decoration = value.get("decoration")
    if not isinstance(decoration, dict):
        ctx.error(path, "visual_layers.decoration", "must be an object")
        return
    if set(decoration) != {"cells"}:
        ctx.error(path, "visual_layers.decoration", "must define exactly cells")
    cells = _require_list(ctx, path, "visual_layers.decoration.cells", decoration.get("cells"))
    _validate_module_visual_cells(
        ctx,
        path,
        "visual_layers.decoration.cells",
        cells,
        "decoration",
        module_tile_catalog,
    )


def _validate_module_visual_cells(
    ctx: ValidationContext,
    path: Path,
    field: str,
    cells: list[Any],
    layer: str,
    module_tile_catalog: dict[str, str],
) -> None:
    seen: set[tuple[int, int]] = set()
    previous_sort_key = (-1, -1)
    for index, item in enumerate(cells):
        item_field = f"{field}[{index}]"
        if not isinstance(item, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        if set(item) != {"cell", "tile_id", "rotation", "flip_h", "flip_v"}:
            ctx.error(path, item_field, "must define exactly cell, tile_id, rotation, flip_h, and flip_v")
        cell = _validate_module_cell(ctx, path, f"{item_field}.cell", item.get("cell"), 11, 11)
        if cell is not None:
            if cell in seen:
                ctx.error(path, f"{item_field}.cell", "must be unique within the visual layer")
            seen.add(cell)
            sort_key = (cell[1], cell[0])
            if sort_key < previous_sort_key:
                ctx.error(path, field, "cells must be sorted by y then x")
            previous_sort_key = sort_key
        _validate_module_tile_reference(
            ctx,
            path,
            f"{item_field}.tile_id",
            item.get("tile_id"),
            layer,
            module_tile_catalog,
        )
        rotation = _require_int(ctx, path, f"{item_field}.rotation", item.get("rotation", 0), minimum=0)
        if rotation not in {0, 90, 180, 270}:
            ctx.error(path, f"{item_field}.rotation", "must be 0, 90, 180, or 270")
        _require_bool(ctx, path, f"{item_field}.flip_h", item.get("flip_h", False))
        _require_bool(ctx, path, f"{item_field}.flip_v", item.get("flip_v", False))


def _validate_module_tile_reference(
    ctx: ValidationContext,
    path: Path,
    field: str,
    value: Any,
    expected_layer: str,
    module_tile_catalog: dict[str, str],
) -> None:
    tile_id = _require_registered(ctx, path, field, value, "module_tile_ids")
    if tile_id and module_tile_catalog.get(tile_id) != expected_layer:
        ctx.error(path, field, f"tile must belong to the {expected_layer} layer")


def _validate_module_footprint(
    ctx: ValidationContext, path: Path, field: str, value: Any, cell: tuple[int, int] | None
) -> set[tuple[int, int]]:
    if cell is None:
        return set()
    width = 1
    height = 1
    if value is not None:
        if not isinstance(value, dict):
            ctx.error(path, field, "must be an object")
            return {cell}
        parsed_width = _require_int(ctx, path, f"{field}.width", value.get("width"), minimum=1)
        parsed_height = _require_int(ctx, path, f"{field}.height", value.get("height"), minimum=1)
        if parsed_width is not None:
            width = parsed_width
        if parsed_height is not None:
            height = parsed_height
    cells = {(cell[0] + x, cell[1] + y) for y in range(height) for x in range(width)}
    if any(x < 0 or x >= 11 or y < 0 or y >= 11 for x, y in cells):
        ctx.error(path, field, "footprint must stay inside the 11x11 module")
    return cells


def _validate_module_role_budget(
    ctx: ValidationContext, path: Path, role: str | None, counts: dict[str, int]
) -> None:
    hazards = counts.get("module_place_hazard", 0)
    rewards = counts.get("module_place_reward_cache", 0)
    if role == "module_role_start":
        if hazards != 0:
            ctx.error(path, "placements", "start module cannot contain hazards")
        if counts.get("module_place_player_start", 0) != 1:
            ctx.error(path, "placements", "start module requires exactly one player_start")
    elif role == "module_role_connector":
        _validate_budget_range(ctx, path, hazards, 0, 1, "connector hazard count")
    elif role == "module_role_combat":
        _validate_budget_range(ctx, path, hazards, 0, 2, "combat hazard count")
    elif role == "module_role_resource":
        if rewards != 1:
            ctx.error(path, "placements", "resource module requires exactly one reward_cache")
    elif role == "module_role_hazard":
        _validate_budget_range(ctx, path, hazards, 2, 4, "hazard module hazard count")
    elif role == "module_role_objective" and counts.get("module_place_objective", 0) != 1:
        ctx.error(path, "placements", "objective module requires exactly one objective")
    elif role == "module_role_world_event":
        if counts.get("module_place_world_event", 0) != 1 or len(counts) != 1:
            ctx.error(path, "placements", "world event module requires exactly one world event placement")
    elif role == "module_role_sealed" and (hazards or any(counts.values())):
        ctx.error(path, "placements", "sealed module cannot contain placements")


def _validate_budget_range(ctx: ValidationContext, path: Path, value: int, minimum: int, maximum: int, label: str) -> None:
    if value < minimum or value > maximum:
        ctx.error(path, "placements", f"{label} must be between {minimum} and {maximum}; got {value}")


def _validate_module_route_budget(ctx: ValidationContext, path: Path, field: str, value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        ctx.error(path, field, "must be an object")
        return {}
    result: dict[str, Any] = {}
    for segment in ("start_to_objective",):
        segment_value = value.get(segment)
        segment_field = f"{field}.{segment}"
        if not isinstance(segment_value, dict):
            ctx.error(path, segment_field, "must be an object")
            continue
        minimum = _require_int(ctx, path, f"{segment_field}.min_crossings", segment_value.get("min_crossings"), minimum=0)
        maximum = _require_int(ctx, path, f"{segment_field}.max_crossings", segment_value.get("max_crossings"), minimum=0)
        if minimum is not None and maximum is not None and minimum > maximum:
            ctx.error(path, segment_field, "min_crossings must be <= max_crossings")
        result[segment] = (minimum, maximum)
    main_route = value.get("main_route_modules")
    if not isinstance(main_route, dict):
        ctx.error(path, f"{field}.main_route_modules", "must be an object")
    else:
        minimum = _require_int(ctx, path, f"{field}.main_route_modules.min", main_route.get("min"), minimum=1)
        maximum = _require_int(ctx, path, f"{field}.main_route_modules.max", main_route.get("max"), minimum=1)
        if minimum is not None and maximum is not None and minimum > maximum:
            ctx.error(path, f"{field}.main_route_modules", "min must be <= max")
        result["main_route_modules"] = (minimum, maximum)
    optional = value.get("optional_exploration_modules")
    if not isinstance(optional, dict):
        ctx.error(path, f"{field}.optional_exploration_modules", "must be an object")
    else:
        result["optional_exploration_modules"] = _require_int(
            ctx, path, f"{field}.optional_exploration_modules.max", optional.get("max"), minimum=0, maximum=14
        )
    return result


def _validate_module_objective_spawn(
    ctx: ValidationContext,
    path: Path,
    field: str,
    value: Any,
    templates: dict[str, dict[str, Any]],
    start_slot: tuple[int, int] | None,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "template_id": "",
        "rotation": 0,
        "candidate_slots": [],
    }
    if not isinstance(value, dict):
        ctx.error(path, field, "must be an object")
        return result
    if set(value) != {"template_id", "rotation", "candidate_slots"}:
        ctx.error(path, field, "must define exactly template_id, rotation, and candidate_slots")
    template_id = _require_non_empty_string(
        ctx, path, f"{field}.template_id", value.get("template_id")
    )
    if template_id is not None:
        result["template_id"] = template_id
    rotation = value.get("rotation")
    if not isinstance(rotation, int) or isinstance(rotation, bool) or rotation not in (0, 90, 180, 270):
        ctx.error(path, f"{field}.rotation", "rotation must be one of 0, 90, 180, 270")
    else:
        result["rotation"] = rotation
    template = templates.get(template_id or "")
    if template_id and template is None:
        ctx.error(
            path,
            f"{field}.template_id",
            f"template is not defined in module_templates.json: {template_id}",
        )
    elif template is not None:
        if template.get("review_status") != "module_review_approved":
            ctx.error(path, f"{field}.template_id", "objective template must be approved")
        if template.get("role") != "module_role_objective":
            ctx.error(path, f"{field}.template_id", "template must use module_role_objective")
        if isinstance(rotation, int) and rotation not in template.get("allowed_rotations", set()):
            ctx.error(path, f"{field}.rotation", f"rotation is not allowed by template {template_id}: {rotation}")
    candidate_values = _require_list(
        ctx, path, f"{field}.candidate_slots", value.get("candidate_slots")
    )
    if len(candidate_values) != 3:
        ctx.error(path, f"{field}.candidate_slots", "must contain exactly 3 candidate slots")
    seen: set[tuple[int, int]] = set()
    for index, candidate_value in enumerate(candidate_values):
        candidate = _validate_module_cell(
            ctx,
            path,
            f"{field}.candidate_slots[{index}]",
            candidate_value,
            7,
            7,
        )
        if candidate is None:
            continue
        if candidate in seen:
            ctx.error(
                path,
                f"{field}.candidate_slots[{index}]",
                f"duplicate slot {candidate[0]},{candidate[1]}",
            )
            continue
        seen.add(candidate)
        result["candidate_slots"].append(candidate)
        if candidate == start_slot:
            ctx.error(path, f"{field}.candidate_slots[{index}]", "must not overlap start_slot")
    expected_candidates = {(0, 0), (6, 0), (6, 6)}
    if seen != expected_candidates:
        ctx.error(
            path,
            f"{field}.candidate_slots",
            "must equal the top-left, top-right, and bottom-right corners",
        )
    return result


def _validate_module_assignment_entries(
    ctx: ValidationContext,
    path: Path,
    field: str,
    entries: list[Any],
    templates: dict[str, dict[str, Any]],
    *,
    exact_49: bool,
    allow_technical_sealed: bool,
) -> dict[tuple[int, int], tuple[str, int]]:
    if exact_49 and len(entries) != 49:
        ctx.error(path, field, "must contain exactly 49 slot assignments")
    assignment: dict[tuple[int, int], tuple[str, int]] = {}
    for index, entry in enumerate(entries):
        item_field = f"{field}[{index}]"
        if not isinstance(entry, dict):
            ctx.error(path, item_field, "must be an object")
            continue
        slot = _validate_module_cell(ctx, path, f"{item_field}.slot", entry.get("slot"), 7, 7)
        template_id = _require_non_empty_string(ctx, path, f"{item_field}.template_id", entry.get("template_id"))
        rotation = entry.get("rotation")
        if not isinstance(rotation, int) or isinstance(rotation, bool) or rotation not in (0, 90, 180, 270):
            ctx.error(path, f"{item_field}.rotation", "rotation must be one of 0, 90, 180, 270")
            rotation_value = 0
        else:
            rotation_value = rotation
        template = templates.get(template_id or "")
        if template_id and template is None:
            ctx.error(path, f"{item_field}.template_id", f"template is not defined in module_templates.json: {template_id}")
        elif template is not None:
            if rotation_value not in template["allowed_rotations"]:
                ctx.error(path, f"{item_field}.rotation", f"rotation is not allowed by template {template_id}: {rotation_value}")
            approved = template["review_status"] == "module_review_approved"
            sealed = template["role"] == "module_role_sealed"
            technical_exception = allow_technical_sealed and sealed and slot is not None and not (2 <= slot[0] <= 4 and 2 <= slot[1] <= 4)
            if not approved and not technical_exception:
                ctx.error(path, f"{item_field}.template_id", f"assignment requires approved template: {template_id}")
            if exact_49 and not allow_technical_sealed and sealed:
                ctx.error(path, f"{item_field}.template_id", "fallback assignment cannot contain sealed templates")
            if exact_49 and allow_technical_sealed and slot is not None:
                inside_slice = 2 <= slot[0] <= 4 and 2 <= slot[1] <= 4
                if inside_slice and sealed:
                    ctx.error(path, f"{item_field}.template_id", "technical slice center 3x3 cannot be sealed")
                elif not inside_slice and not sealed:
                    ctx.error(path, f"{item_field}.template_id", "technical slice outer 40 slots must be sealed")
        if slot is not None:
            if slot in assignment:
                ctx.error(path, f"{item_field}.slot", f"duplicate slot {slot[0]},{slot[1]}")
            elif template_id:
                assignment[slot] = (template_id, rotation_value)
    if exact_49:
        expected = {(x, y) for y in range(7) for x in range(7)}
        missing = sorted(expected - set(assignment))
        if missing:
            ctx.error(path, field, f"assignment is missing slots: {missing[:4]}")
    return assignment


def _validate_module_fixed_anchor_roles(
    ctx: ValidationContext,
    path: Path,
    field: str,
    assignment: dict[tuple[int, int], tuple[str, int]],
    templates: dict[str, dict[str, Any]],
    anchors: dict[str, tuple[int, int] | None],
) -> None:
    start_slots = [
        role_slot
        for role_slot, (template_id, _rotation) in assignment.items()
        if templates.get(template_id, {}).get("role") == "module_role_start"
    ]
    if len(start_slots) != 1:
        ctx.error(path, field, "must contain exactly one module_role_start")
    objective_slots = [
        role_slot
        for role_slot, (template_id, _rotation) in assignment.items()
        if templates.get(template_id, {}).get("role") == "module_role_objective"
    ]
    if objective_slots:
        ctx.error(path, field, "must not contain module_role_objective; objective_spawn selects it")
    start_slot = anchors.get("start_slot")
    if start_slot is None:
        return
    if start_slot not in assignment:
        ctx.error(path, field, "must assign configured start_slot")
        return
    template = templates.get(assignment[start_slot][0])
    if template is not None and template["role"] != "module_role_start":
        ctx.error(path, field, "start_slot must use role module_role_start")


def _validate_module_assignment_world(
    ctx: ValidationContext,
    path: Path,
    field: str,
    assignment: dict[tuple[int, int], tuple[str, int]],
    templates: dict[str, dict[str, Any]],
    anchors: dict[str, tuple[int, int] | None],
    route_budget: dict[str, Any],
    technical: bool,
) -> None:
    if len(assignment) != 49:
        return
    effective_anchors = dict(anchors)
    for role in ("module_role_start", "module_role_objective"):
        role_slots = [
            slot for slot, (template_id, _rotation) in assignment.items()
            if templates.get(template_id, {}).get("role") == role
        ]
        if len(role_slots) != 1:
            ctx.error(path, field, f"must contain exactly one {role}")
    if technical:
        for anchor_name, role in (
            ("start_slot", "module_role_start"),
            ("objective_slot", "module_role_objective"),
        ):
            role_slots = [
                slot for slot, (template_id, _rotation) in assignment.items()
                if templates.get(template_id, {}).get("role") == role
            ]
            if len(role_slots) != 1:
                ctx.error(path, field, f"technical slice requires exactly one {role}")
            else:
                effective_anchors[anchor_name] = role_slots[0]
    for anchor_name, expected_role in (
        ("start_slot", "module_role_start"),
        ("objective_slot", "module_role_objective"),
    ):
        slot = effective_anchors.get(anchor_name)
        if slot is None or slot not in assignment:
            continue
        template = templates.get(assignment[slot][0])
        if template is not None and template["role"] != expected_role:
            ctx.error(path, field, f"{anchor_name} must use role {expected_role}")

    graph: dict[tuple[int, int], set[tuple[int, int]]] = {slot: set() for slot in assignment}
    for y in range(7):
        for x in range(7):
            slot = (x, y)
            for neighbor, edge, opposite in (((x + 1, y), "edge_east", "edge_west"), ((x, y + 1), "edge_south", "edge_north")):
                if neighbor not in assignment:
                    continue
                left_role = templates.get(assignment[slot][0], {}).get("role")
                right_role = templates.get(assignment[neighbor][0], {}).get("role")
                if left_role == "module_role_sealed" or right_role == "module_role_sealed":
                    continue
                left_sockets = _effective_module_sockets(assignment[slot], templates, edge)
                right_sockets = _effective_module_sockets(assignment[neighbor], templates, opposite)
                if not left_sockets & right_sockets:
                    ctx.error(
                        path,
                        field,
                        f"no shared open socket between slot {slot} {edge} and {neighbor} {opposite}",
                    )
                    continue
                graph[slot].add(neighbor)
                graph[neighbor].add(slot)

    non_sealed = {
        slot for slot, (template_id, _rotation) in assignment.items()
        if templates.get(template_id, {}).get("role") != "module_role_sealed"
    }
    start = effective_anchors.get("start_slot")
    if start not in non_sealed:
        return
    reachable = _module_graph_distances(graph, start)
    missing = non_sealed - set(reachable)
    if missing:
        ctx.error(path, field, f"all non-sealed slots must be reachable from start; unreachable: {sorted(missing)[:4]}")
    objective = effective_anchors.get("objective_slot")
    if objective not in reachable:
        ctx.error(path, field, "critical route start -> objective is unreachable")
        return
    if technical:
        return
    start_distance = reachable[objective]
    _validate_route_distance(ctx, path, field, "start_to_objective", start_distance, route_budget.get("start_to_objective"))
    main_range = route_budget.get("main_route_modules")
    if isinstance(main_range, tuple) and None not in main_range:
        module_count = start_distance + 1
        if module_count < main_range[0] or module_count > main_range[1]:
            ctx.error(path, field, f"main route module count {module_count} is outside {main_range[0]}..{main_range[1]}")


def _effective_module_sockets(
    assignment: tuple[str, int], templates: dict[str, dict[str, Any]], requested_edge: str
) -> set[int]:
    template = templates.get(assignment[0])
    if template is None or not isinstance(template.get("data"), dict):
        return set()
    sockets = template["data"].get("edge_sockets")
    if not isinstance(sockets, dict):
        return set()
    rotation = assignment[1]
    result: set[int] = set()
    for source_edge in ("edge_north", "edge_south", "edge_east", "edge_west"):
        values = sockets.get(source_edge)
        if not isinstance(values, list):
            continue
        for value in values:
            if not isinstance(value, int) or isinstance(value, bool) or value < 0 or value > 10:
                continue
            edge, index = _rotate_module_socket(source_edge, value, rotation)
            if edge == requested_edge:
                result.add(index)
    return result


def _rotate_module_socket(edge: str, index: int, rotation: int) -> tuple[str, int]:
    if edge == "edge_north":
        point = (index, 0)
    elif edge == "edge_south":
        point = (index, 10)
    elif edge == "edge_east":
        point = (10, index)
    else:
        point = (0, index)
    x, y = point
    for _ in range((rotation // 90) % 4):
        x, y = 10 - y, x
    if y == 0:
        return "edge_north", x
    if y == 10:
        return "edge_south", x
    if x == 10:
        return "edge_east", y
    return "edge_west", y


def _module_graph_distances(
    graph: dict[tuple[int, int], set[tuple[int, int]]], start: tuple[int, int]
) -> dict[tuple[int, int], int]:
    distances = {start: 0}
    queue = [start]
    for slot in queue:
        for neighbor in graph.get(slot, set()):
            if neighbor not in distances:
                distances[neighbor] = distances[slot] + 1
                queue.append(neighbor)
    return distances


def _validate_route_distance(
    ctx: ValidationContext, path: Path, field: str, label: str, distance: int, budget: Any
) -> None:
    if not isinstance(budget, tuple) or None in budget:
        return
    if distance < budget[0] or distance > budget[1]:
        ctx.error(path, field, f"{label} crossings {distance} is outside {budget[0]}..{budget[1]}")


def _validate_module_cell(
    ctx: ValidationContext, path: Path, field: str, value: Any, columns: int, rows: int
) -> tuple[int, int] | None:
    if not isinstance(value, dict):
        ctx.error(path, field, "must be an object with integer x/y")
        return None
    x = _require_int(ctx, path, f"{field}.x", value.get("x"), minimum=0)
    y = _require_int(ctx, path, f"{field}.y", value.get("y"), minimum=0)
    if x is None or y is None:
        return None
    if x >= columns:
        ctx.error(path, f"{field}.x", f"must be < {columns}")
    if y >= rows:
        ctx.error(path, f"{field}.y", f"must be < {rows}")
    if x >= columns or y >= rows:
        return None
    return x, y


def _require_exact_int(
    ctx: ValidationContext, path: Path, field: str, value: Any, expected: int
) -> int | None:
    parsed = _require_int(ctx, path, field, value)
    if parsed is not None and parsed != expected:
        ctx.error(path, field, f"must equal {expected}")
    return parsed


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


def _parse_csv_bool(
    ctx: ValidationContext,
    path: Path,
    field: str,
    value: Any,
) -> bool | None:
    if isinstance(value, str) and not value.strip():
        return True
    if not isinstance(value, str) or value.strip().lower() not in {"true", "false"}:
        ctx.error(path, field, "must be true or false")
        return None
    return value.strip().lower() == "true"


def _validate_codex_icon_path(
    ctx: ValidationContext,
    path: Path,
    field: str,
    value: Any,
) -> None:
    if value in {None, ""}:
        return
    if (
        not isinstance(value, str)
        or not value.startswith("res://")
        or "\\" in value
        or ".." in value.split("/")
    ):
        ctx.error(path, field, "must be an empty value or a valid res:// resource path")
        return
    resource_path = ROOT / "client" / value.removeprefix("res://")
    if not resource_path.is_file():
        ctx.error(path, field, f"resource does not exist: {value}")


def _validate_actor_scene_path(
    ctx: ValidationContext,
    path: Path,
    field: str,
    value: Any,
    required_prefix: str,
) -> str | None:
    if not isinstance(value, str) or not value:
        ctx.error(path, field, "must be a non-empty actor scene path")
        return None
    parts = value.split("/")
    if (
        not value.startswith(required_prefix)
        or not value.endswith(".tscn")
        or "\\" in value
        or ".." in parts
    ):
        ctx.error(path, field, f"must be a project actor .tscn under {required_prefix}")
        return None
    if value in {
        "res://scenes/gameplay/actors/player_base.tscn",
        "res://scenes/gameplay/actors/enemy_base.tscn",
    }:
        ctx.error(path, field, "must reference a dedicated actor scene, not a base scene")
        return None
    scene_file = ROOT / "client" / value.removeprefix("res://")
    if not scene_file.is_file():
        ctx.error(path, field, f"actor scene does not exist: {value}")
        return None
    try:
        first_line = scene_file.read_text(encoding="utf-8-sig").splitlines()[0]
    except (OSError, UnicodeError, IndexError):
        ctx.error(path, field, f"actor scene is not a readable PackedScene: {value}")
        return None
    if not first_line.startswith("[gd_scene "):
        ctx.error(path, field, f"actor scene is not a PackedScene: {value}")
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


def _reject_removed_field(
    ctx: ValidationContext,
    path: Path,
    parent_field: str,
    payload: dict[str, Any],
    key: str,
    *,
    schema_version: int,
) -> None:
    if key in payload:
        ctx.error(path, f"{parent_field}.{key}", f"field was removed in schema v{schema_version}")


def _require_int(
    ctx: ValidationContext,
    path: Path,
    field: str,
    value: Any,
    *,
    minimum: int | None = None,
    maximum: int | None = None,
) -> int | None:
    if not isinstance(value, int) or isinstance(value, bool):
        ctx.error(path, field, "must be int")
        return None
    if minimum is not None and value < minimum:
        ctx.error(path, field, f"must be >= {minimum}")
    if maximum is not None and value > maximum:
        ctx.error(path, field, f"must be <= {maximum}")
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
    if not math.isfinite(numeric):
        ctx.error(path, field, "must be finite")
        return None
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
    if not math.isfinite(parsed):
        ctx.error(path, field, "must be finite")
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


def _load_csv_rows(path: Path, ctx: ValidationContext) -> list[dict[str, str]]:
    if not path.exists():
        ctx.error(path, "$", "missing CSV file")
        return []
    try:
        with path.open(encoding="utf-8-sig", newline="") as handle:
            return list(csv.DictReader(handle))
    except OSError as exc:
        ctx.error(path, "$", f"failed to read CSV: {exc}")
        return []


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
