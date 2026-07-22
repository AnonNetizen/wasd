#!/usr/bin/env python3
"""Regression tests for DataLoader-facing project data schema validation."""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import csv
from collections.abc import Callable
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]


JsonMutator = Callable[[dict[str, Any]], None]
CsvMutator = Callable[[list[dict[str, str]]], None]
RepoMutator = Callable[[Path], None]


def main() -> int:
    cases: list[tuple[str, RepoMutator | None, list[str]]] = [
        ("golden data passes", None, []),
        (
            "module world must be 9x9",
            _mutate_json("client/data/module_worlds.json", _set_module_world_columns(8)),
            ["client/data/module_worlds.json:worlds[0].columns", "must equal 9"],
        ),
        (
            "module world cell size is configurable",
            _mutate_json("client/data/module_worlds.json", _set_module_world_cell_size(192.0)),
            [],
        ),
        (
            "module world cell size must be positive",
            _mutate_json("client/data/module_worlds.json", _set_module_world_cell_size(0.0)),
            ["client/data/module_worlds.json:worlds[0].cell_size", "must be > 0.0"],
        ),
        (
            "fixed slots must cover configured anchors",
            _mutate_json("client/data/module_worlds.json", _remove_fixed_objective_slot),
            ["client/data/module_worlds.json:worlds[0].fixed_slots", "must assign configured objective_slot"],
        ),
        (
            "fixed anchor must use its required role",
            _mutate_json("client/data/module_worlds.json", _replace_fixed_objective_with_connector),
            ["client/data/module_worlds.json:worlds[0].fixed_slots", "objective_slot must use role module_role_objective"],
        ),
        (
            "fixed slots require unique critical roles",
            _mutate_json("client/data/module_worlds.json", _add_duplicate_fixed_start_role),
            ["client/data/module_worlds.json:worlds[0].fixed_slots", "must contain exactly one module_role_start"],
        ),
        (
            "optional exploration budget is capped",
            _mutate_json("client/data/module_worlds.json", _set_optional_exploration_max(15)),
            ["client/data/module_worlds.json:worlds[0].route_budget.optional_exploration_modules.max", "must be <= 14"],
        ),
        (
            "module terrain must be 11x11",
            _mutate_json("client/data/modules/module_start_cross.json", _remove_module_terrain_row),
            ["client/data/modules/module_start_cross.json:terrain_rows", "must contain exactly 11 rows"],
        ),
        (
            "candidate template cannot enter formal pool",
            _mutate_json("client/data/module_templates.json", _make_first_pool_template_candidate),
            ["client/data/module_worlds.json:worlds[0].template_pool[0]", "formal template pool requires approved template"],
        ),
        (
            "fallback assignment must contain 81 slots",
            _mutate_json("client/data/module_worlds.json", _remove_fallback_assignment),
            ["client/data/module_worlds.json:worlds[0].fallback_assignment", "must contain exactly 81 slot assignments"],
        ),
        (
            "fallback assignment slots must be unique",
            _mutate_json("client/data/module_worlds.json", _duplicate_fallback_slot),
            ["client/data/module_worlds.json:worlds[0].fallback_assignment[1].slot", "duplicate slot 0,0"],
        ),
        (
            "module sockets must match across assignments",
            _mutate_json("client/data/modules/module_connector_cross.json", _close_module_east_socket),
            ["client/data/module_worlds.json:worlds[0].fallback_assignment", "socket mismatch between slot"],
        ),
        (
            "module terrain token must be registered",
            _mutate_json("client/data/modules/module_start_cross.json", _set_unknown_module_token),
            ["client/data/modules/module_start_cross.json:terrain_rows[0][0]", "unknown id module_cell_unknown; expected one of module_cell_tokens"],
        ),
        (
            "module placement type must be registered",
            _mutate_json("client/data/modules/module_start_cross.json", _set_unknown_module_placement),
            ["client/data/modules/module_start_cross.json:placements[0].type", "unknown id module_place_unknown; expected one of module_placement_types"],
        ),
        (
            "module placement cell must stay in bounds",
            _mutate_json("client/data/modules/module_start_cross.json", _set_module_placement_out_of_bounds),
            ["client/data/modules/module_start_cross.json:placements[0].cell.x", "must be < 11"],
        ),
        (
            "module enemy spawn must use floor terrain",
            _mutate_json("client/data/modules/module_combat_arena.json", _set_module_enemy_spawn_on_blocked_cell),
            ["client/data/modules/module_combat_arena.json:placements[", "enemy spawn footprint must use module_cell_floor terrain"],
        ),
        (
            "module role content budget must be enforced",
            _mutate_json("client/data/modules/module_combat_arena.json", _exceed_combat_enemy_budget),
            ["client/data/modules/module_combat_arena.json:placements", "combat enemy count must be between 6 and 12"],
        ),
        (
            "critical module route must be reachable",
            _mutate_json("client/data/modules/module_objective_core.json", _close_all_module_sockets),
            ["client/data/module_worlds.json:worlds[0].fallback_assignment", "critical route start -> objective is unreachable"],
        ),
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
                "must be number",
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
            "missing growth entry locale key fails",
            _mutate_json("client/data/growth_pools.json", _set_growth_entry_name_key("ui_growth_missing_name")),
            [
                "client/data/growth_pools.json:pools[0].entries[0].name_key",
                "locale key is missing from client/locale/strings.csv: ui_growth_missing_name",
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
                "client/data/characters.json:characters[0].starting_loadout.weapon_id",
                "weapon is not defined in weapons.json: weapon_missing",
            ],
        ),
        (
            "character starting active item reference must exist",
            _mutate_json("client/data/characters.json", _set_character_starting_active_item("active_item_missing")),
            [
                "client/data/characters.json:characters[0].starting_loadout.active_item_id",
                "active item is not defined in active_items.json: active_item_missing",
            ],
        ),
        (
            "character starting consumable reference must exist",
            _mutate_json("client/data/characters.json", _set_character_starting_consumable("consumable_missing")),
            [
                "client/data/characters.json:characters[0].starting_loadout.consumable_ids[0]",
                "consumable is not defined in consumables.json: consumable_missing",
            ],
        ),
        (
            "character starting skill id must be registered",
            _mutate_json("client/data/characters.json", _set_character_starting_skill("skill_missing")),
            [
                "client/data/characters.json:characters[0].starting_loadout.skill_ids[0]",
                "unknown id skill_missing; expected one of skill_ids",
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
        (
            "mode skill id must be registered",
            _mutate_json("client/data/game_modes.json", _set_mode_skill("skill_missing")),
            [
                "client/data/game_modes.json:modes[0].resource_pools.skills[0].id",
                "unknown id skill_missing; expected one of skill_ids",
            ],
        ),
        (
            "enemy must include enemy tag",
            _mutate_csv("client/data/enemies.csv", _set_enemy_tags("")),
            [
                "client/data/enemies.csv:line 2.tags",
                "must include tag_enemy",
            ],
        ),
        (
            "enemy damage type must be registered",
            _mutate_csv("client/data/enemies.csv", _set_enemy_damage_type("arcane")),
            [
                "client/data/enemies.csv:line 2.contact_damage_type",
                "unknown id arcane; expected one of damage_types",
            ],
        ),
        (
            "enemy AI action must be registered",
            _mutate_json("client/data/enemy_ai_profiles.json", _set_enemy_ai_action("ai_action_missing")),
            [
                "client/data/enemy_ai_profiles.json:profiles[0].actions[0].id",
                "unknown id ai_action_missing; expected one of enemy_ai_actions",
            ],
        ),
        (
            "removed enemy ecology action must stay rejected",
            _mutate_json("client/data/enemy_ai_profiles.json", _set_enemy_ai_action("ai_action_flee_threat")),
            [
                "client/data/enemy_ai_profiles.json:profiles[0].actions[0].id",
                "unknown id ai_action_flee_threat; expected one of enemy_ai_actions",
            ],
        ),
        (
            "removed enemy ecology tag must stay rejected",
            _mutate_csv("client/data/enemies.csv", _set_enemy_tags("tag_enemy|tag_enemy_prey")),
            [
                "client/data/enemies.csv:line 2.tags[1]",
                "unknown id tag_enemy_prey; expected one of content_tags",
            ],
        ),
        (
            "enemy AI schema v3 is required",
            _mutate_json("client/data/enemy_ai_profiles.json", _set_schema_version(2)),
            [
                "client/data/enemy_ai_profiles.json:schema_version",
                "must be >= 3",
            ],
        ),
        (
            "enemy AI sense radius was removed",
            _mutate_json("client/data/enemy_ai_profiles.json", _add_enemy_ai_legacy_sense_radius),
            [
                "client/data/enemy_ai_profiles.json:profiles[0].sense_radius",
                "field was removed in schema v3",
            ],
        ),
        (
            "enemy AI perception is required",
            _mutate_json("client/data/enemy_ai_profiles.json", _remove_enemy_ai_perception),
            [
                "client/data/enemy_ai_profiles.json:profiles[0].perception",
                "must be an object",
            ],
        ),
        (
            "enemy AI sight radius must be positive",
            _mutate_json("client/data/enemy_ai_profiles.json", _set_enemy_ai_perception_value("sight_radius", 0.0)),
            [
                "client/data/enemy_ai_profiles.json:profiles[0].perception.sight_radius",
                "must be > 0",
            ],
        ),
        (
            "enemy AI path awareness cannot exceed sight",
            _mutate_json("client/data/enemy_ai_profiles.json", _set_enemy_ai_perception_value("path_awareness_radius", 9999.0)),
            [
                "client/data/enemy_ai_profiles.json:profiles[0].perception.path_awareness_radius",
                "must be <= sight_radius",
            ],
        ),
        (
            "enemy AI memory duration cannot be negative",
            _mutate_json("client/data/enemy_ai_profiles.json", _set_enemy_ai_perception_value("memory_duration", -0.1)),
            [
                "client/data/enemy_ai_profiles.json:profiles[0].perception.memory_duration",
                "must be >= 0",
            ],
        ),
        (
            "enemy AI contact interval was removed",
            _mutate_json("client/data/enemy_ai_profiles.json", _add_enemy_ai_legacy_contact_interval),
            [
                "client/data/enemy_ai_profiles.json:profiles[0].contact_interval",
                "field was removed in schema v2",
            ],
        ),
        (
            "enemy AI hunt tags were removed",
            _mutate_json("client/data/enemy_ai_profiles.json", _add_enemy_ai_legacy_hunt_tags),
            [
                "client/data/enemy_ai_profiles.json:profiles[0].targeting.hunt_tags",
                "field was removed in schema v2",
            ],
        ),
        (
            "enemy AI flee tags were removed",
            _mutate_json("client/data/enemy_ai_profiles.json", _add_enemy_ai_legacy_flee_tags),
            [
                "client/data/enemy_ai_profiles.json:profiles[0].targeting.flee_tags",
                "field was removed in schema v2",
            ],
        ),
        (
            "enemy AI flee distance was removed",
            _mutate_json("client/data/enemy_ai_profiles.json", _add_enemy_ai_legacy_flee_distance),
            [
                "client/data/enemy_ai_profiles.json:profiles[0].movement.flee_distance",
                "field was removed in schema v2",
            ],
        ),
        (
            "enemy AI profile reference must exist",
            _mutate_csv("client/data/enemies.csv", _set_enemy_ai_profile("enemy_ai_missing")),
            [
                "client/data/enemies.csv:line 2.ai_profile_id",
                "profile is not defined in enemy_ai_profiles.json: enemy_ai_missing",
            ],
        ),
        (
            "mode enemy reference must exist",
            _mutate_json("client/data/game_modes.json", _set_mode_enemy("enemy_missing")),
            [
                "client/data/game_modes.json:modes[0].resource_pools.enemies[0].id",
                "enemy is not defined in enemies.csv: enemy_missing",
            ],
        ),
        (
            "gear mod id must be registered",
            _mutate_json("client/data/gear_mods.json", _set_gear_mod_id("gear_mod_missing")),
            [
                "client/data/gear_mods.json:mods[0].id",
                "unknown id gear_mod_missing; expected one of gear_mod_ids",
            ],
        ),
        (
            "gear mod locale key must exist",
            _mutate_json("client/data/gear_mods.json", _set_gear_mod_name_key("gear_mod_missing_name")),
            [
                "client/data/gear_mods.json:mods[0].name_key",
                "locale key is missing from client/locale/strings.csv: gear_mod_missing_name",
            ],
        ),
        (
            "gear mod modifier stat must be registered",
            _mutate_json("client/data/gear_mods.json", _set_gear_mod_modifier_stat("stat_missing")),
            [
                "client/data/gear_mods.json:mods[0].rank_modifiers[0].stat",
                "unknown id stat_missing; expected one of stats",
            ],
        ),
        (
            "gear mod drop enemy reference must exist",
            _mutate_csv("client/data/gear_mod_drop_tables.csv", _set_gear_mod_drop_enemy("enemy_missing")),
            [
                "client/data/gear_mod_drop_tables.csv:line 2.source_enemy_id",
                "enemy is not defined in enemies.csv: enemy_missing",
            ],
        ),
        (
            "gear mod drop chance must be a ratio",
            _mutate_csv("client/data/gear_mod_drop_tables.csv", _set_gear_mod_drop_chance("1.5")),
            [
                "client/data/gear_mod_drop_tables.csv:line 2.drop_chance",
                "must be <= 1.0",
            ],
        ),
        (
            "gear mod fusion resource must be registered",
            _mutate_csv("client/data/gear_mod_fusion_costs.csv", _set_gear_mod_fusion_resource("gear_mod_resource_missing")),
            [
                "client/data/gear_mod_fusion_costs.csv:line 2.resource_id",
                "unknown id gear_mod_resource_missing; expected one of gear_mod_resources",
            ],
        ),
        (
            "gear mod fusion costs must cover max rank",
            _mutate_csv("client/data/gear_mod_fusion_costs.csv", _remove_gear_mod_fusion_rank("5")),
            [
                "client/data/gear_mod_fusion_costs.csv:common.rank_5",
                "missing fusion cost for gear mod rarity/rank",
            ],
        ),
        (
            "hazard must include hazard tag",
            _mutate_csv("client/data/hazards.csv", _set_hazard_tags("")),
            [
                "client/data/hazards.csv:line 2.tags",
                "must include tag_hazard",
            ],
        ),
        (
            "hazard damage type must be registered",
            _mutate_csv("client/data/hazards.csv", _set_hazard_damage_type("arcane")),
            [
                "client/data/hazards.csv:line 2.damage_type",
                "unknown id arcane; expected one of damage_types",
            ],
        ),
        (
            "hazard radius tiles must be positive",
            _mutate_csv("client/data/hazards.csv", _set_hazard_radius_tiles("0")),
            [
                "client/data/hazards.csv:line 2.radius_tiles",
                "must be >= 1",
            ],
        ),
        (
            "mode hazard reference must exist",
            _mutate_json("client/data/game_modes.json", _set_mode_hazard("hazard_missing")),
            [
                "client/data/game_modes.json:modes[0].resource_pools.hazards[0].id",
                "hazard is not defined in hazards.csv: hazard_missing",
            ],
        ),
        (
            "map layout mode reference must exist",
            _mutate_json("client/data/map_layouts.json", _set_map_layout_mode("mode_unregistered")),
            [
                "client/data/map_layouts.json:layouts[0].mode_id",
                "unknown id mode_unregistered; expected one of game_modes",
            ],
        ),
        (
            "map layout grid width must be positive",
            _mutate_json("client/data/map_layouts.json", _set_map_layout_grid_cell_width(0.0)),
            [
                "client/data/map_layouts.json:layouts[0].grid.cell_width",
                "must be > 0",
            ],
        ),
        (
            "map layout bounds must align to rectangular grid",
            _mutate_json("client/data/map_layouts.json", _set_map_layout_bounds_size(3841.0, 2400.0)),
            [
                "client/data/map_layouts.json:layouts[0].bounds.width",
                "must be an integer multiple of grid.cell_width",
            ],
        ),
        (
            "map layout hazard reference must exist",
            _mutate_json("client/data/map_layouts.json", _set_map_layout_pcg_hazard("hazard_missing")),
            [
                "client/data/map_layouts.json:layouts[0].pcg.hazards[0].id",
                "hazard is not defined in hazards.csv: hazard_missing",
            ],
        ),
        (
            "even radius manual hazard must use rectangular grid vertex",
            _mutate_json("client/data/map_layouts.json", _set_manual_hazard_position(0, 480.0, -240.0)),
            [
                "client/data/map_layouts.json:layouts[0].manual_hazards[0]",
                "must be a rectangular grid vertex for even radius_tiles",
            ],
        ),
        (
            "spawn wave enemy reference must exist",
            _mutate_csv("client/data/spawn_waves.csv", _set_spawn_wave_enemy("enemy_missing")),
            [
                "client/data/spawn_waves.csv:line 2.enemy_id",
                "enemy is not defined in enemies.csv: enemy_missing",
            ],
        ),
        (
            "spawn wave mode reference must exist",
            _mutate_csv("client/data/spawn_waves.csv", _set_spawn_wave_mode("mode_unregistered")),
            [
                "client/data/spawn_waves.csv:line 2.mode_id",
                "unknown id mode_unregistered; expected one of game_modes",
            ],
        ),
        (
            "spawn wave time window must be valid",
            _mutate_csv("client/data/spawn_waves.csv", _set_spawn_wave_end_time("0.0")),
            [
                "client/data/spawn_waves.csv:line 2.end_time",
                "must be greater than start_time",
            ],
        ),
        (
            "spawn wave hazard weight requires hazard id",
            _mutate_csv("client/data/spawn_waves.csv", _set_spawn_wave_hazard("", "10")),
            [
                "client/data/spawn_waves.csv:line 2.hazard_id",
                "must be non-empty when hazard_weight > 0",
            ],
        ),
        (
            "warzone director wave reference must exist",
            _mutate_json("client/data/warzone_directors.json", _set_warzone_phase_wave("wave_missing")),
            [
                "client/data/warzone_directors.json:directors[0].phases[0].wave_ids[0]",
                "wave is not defined in spawn_waves.csv for mode mode_standard_survival: wave_missing",
            ],
        ),
        (
            "warzone director schema v2 is required",
            _mutate_json("client/data/warzone_directors.json", _set_schema_version(1)),
            [
                "client/data/warzone_directors.json:schema_version",
                "must be >= 2",
            ],
        ),
        (
            "warzone encounters were removed",
            _mutate_json("client/data/warzone_directors.json", _add_warzone_legacy_encounters),
            [
                "client/data/warzone_directors.json:directors[0].encounters",
                "field was removed in schema v2",
            ],
        ),
        (
            "warzone phase encounter ids were removed",
            _mutate_json("client/data/warzone_directors.json", _add_warzone_legacy_phase_encounter_ids),
            [
                "client/data/warzone_directors.json:directors[0].phases[0].encounter_ids",
                "field was removed in schema v2",
            ],
        ),
        (
            "warzone interest point hazards must be non-empty",
            _mutate_json("client/data/warzone_directors.json", _set_warzone_interest_point_hazards([])),
            [
                "client/data/warzone_directors.json:directors[0].interest_points[0].hazard_ids",
                "must be a non-empty array",
            ],
        ),
        (
            "warzone interest point hazard reference must exist",
            _mutate_json("client/data/warzone_directors.json", _set_warzone_interest_point_hazards(["hazard_missing"])),
            [
                "client/data/warzone_directors.json:directors[0].interest_points[0].hazard_ids[0]",
                "hazard is not defined in hazards.csv: hazard_missing",
            ],
        ),
        (
            "warzone resource reward must use registered resource",
            _mutate_json("client/data/warzone_directors.json", _set_warzone_resource_reward("resource_missing")),
            [
                "client/data/warzone_directors.json:directors[0].interest_points[0].resource_rewards[0].resource_id",
                "unknown id resource_missing; expected one of gear_mod_resources",
            ],
        ),
        (
            "warzone gear mod reward must reference existing mod",
            _mutate_json("client/data/warzone_directors.json", _set_warzone_gear_mod_reward("gear_mod_missing")),
            [
                "client/data/warzone_directors.json:directors[0].interest_points[0].gear_mod_rewards[0].mod_id",
                "unknown id gear_mod_missing; expected one of gear_mod_ids",
            ],
        ),
        (
            "warzone interest point interaction flag must be bool",
            _mutate_json("client/data/warzone_directors.json", _set_warzone_interest_point_requires_interaction("yes")),
            [
                "client/data/warzone_directors.json:directors[0].interest_points[0].requires_interaction",
                "must be bool",
            ],
        ),
        (
            "warzone interest point target hp must be positive",
            _mutate_json("client/data/warzone_directors.json", _set_warzone_interest_point_target_hp(0)),
            [
                "client/data/warzone_directors.json:directors[0].interest_points[0].target_hp",
                "must be > 0",
            ],
        ),
        (
            "warzone completion point extraction radius must be positive",
            _mutate_json("client/data/warzone_directors.json", _set_warzone_completion_extraction_radius(0)),
            [
                "client/data/warzone_directors.json:directors[0].interest_points[3].extraction_radius",
                "must be > 0",
            ],
        ),
        (
            "warzone completion point extraction hold time must be positive",
            _mutate_json("client/data/warzone_directors.json", _set_warzone_completion_extraction_hold_time(0)),
            [
                "client/data/warzone_directors.json:directors[0].interest_points[3].extraction_hold_time",
                "must be > 0",
            ],
        ),
        (
            "relic must include relic tag",
            _mutate_json("client/data/relics.json", _set_relic_tags([])),
            [
                "client/data/relics.json:relics[0].tags",
                "must include tag_relic",
            ],
        ),
        (
            "relic behavior effect must be registered",
            _mutate_json("client/data/relics.json", _set_relic_behavior_effect("arcane")),
            [
                "client/data/relics.json:relics[0].behaviors[0].effect",
                "unknown id arcane; expected one of effects",
            ],
        ),
        (
            "relic must have modifier or behavior",
            _mutate_json("client/data/relics.json", _clear_relic_effects),
            [
                "client/data/relics.json:relics[0]",
                "must contain at least one modifier or behavior",
            ],
        ),
        (
            "mode relic reference must exist",
            _mutate_json("client/data/game_modes.json", _set_mode_relic("relic_missing")),
            [
                "client/data/game_modes.json:modes[0].resource_pools.relics[0].id",
                "relic is not defined in relics.json: relic_missing",
            ],
        ),
        (
            "active item must include active item tag",
            _mutate_json("client/data/active_items.json", _set_active_item_tags([])),
            [
                "client/data/active_items.json:active_items[0].tags",
                "must include tag_active_item",
            ],
        ),
        (
            "active item effect must be registered",
            _mutate_json("client/data/active_items.json", _set_active_item_effect("arcane")),
            [
                "client/data/active_items.json:active_items[0].use_effects[0].effect",
                "unknown id arcane; expected one of effects",
            ],
        ),
        (
            "active item start charges cannot exceed max charges",
            _mutate_json("client/data/active_items.json", _set_active_item_start_charges(2)),
            [
                "client/data/active_items.json:active_items[0].charge.start_charges",
                "must be <= max_charges",
            ],
        ),
        (
            "mode active item reference must exist",
            _mutate_json("client/data/game_modes.json", _set_mode_active_item("active_item_missing")),
            [
                "client/data/game_modes.json:modes[0].resource_pools.active_items[0].id",
                "active item is not defined in active_items.json: active_item_missing",
            ],
        ),
        (
            "skill resource must be registered",
            _mutate_json("client/data/skills.json", _set_skill_cost_resource("arcane")),
            [
                "client/data/skills.json:skills[0].costs[0].resource",
                "unknown id arcane; expected one of skill_resources",
            ],
        ),
        (
            "skill ability tag must be registered",
            _mutate_json("client/data/skills.json", _set_skill_ability_tag("ability_tag_missing")),
            [
                "client/data/skills.json:skills[0].ability_tags[0]",
                "unknown id ability_tag_missing; expected one of ability_tags",
            ],
        ),
        (
            "skill activation blocked tag must be registered",
            _mutate_json("client/data/skills.json", _set_skill_activation_blocked_tag("ability_tag_missing")),
            [
                "client/data/skills.json:skills[0].activation.blocked_tags[0]",
                "unknown id ability_tag_missing; expected one of ability_tags",
            ],
        ),
        (
            "skill apply status id must be registered",
            _mutate_json("client/data/skills.json", _set_skill_apply_status_param("status", "status_missing")),
            [
                "client/data/skills.json:skills[0].effects[0].params.status",
                "unknown id status_missing; expected one of status_effects",
            ],
        ),
        (
            "skill apply status stack rule must be registered",
            _mutate_json("client/data/skills.json", _set_skill_apply_status_param("stack_rule", "STACK_MISSING")),
            [
                "client/data/skills.json:skills[0].effects[0].params.stack_rule",
                "unknown id STACK_MISSING; expected one of status_stack_rules",
            ],
        ),
        (
            "skill apply status granted ability tag must be registered",
            _mutate_json("client/data/skills.json", _set_skill_apply_status_granted_tag("ability_tag_missing")),
            [
                "client/data/skills.json:skills[0].effects[0].params.granted_ability_tags[0]",
                "unknown id ability_tag_missing; expected one of ability_tags",
            ],
        ),
        (
            "skill apply status damage type must be registered",
            _mutate_json("client/data/skills.json", _set_skill_apply_status_param("damage_type", "arcane")),
            [
                "client/data/skills.json:skills[0].effects[0].params.damage_type",
                "unknown id arcane; expected one of damage_types",
            ],
        ),
        (
            "skill apply status dot requires damage type",
            _mutate_json("client/data/skills.json", _set_skill_apply_status_dot_without_damage_type),
            [
                "client/data/skills.json:skills[0].effects[0].params.damage_type",
                "is required when magnitude and tick_interval are positive",
            ],
        ),
        (
            "skill damage type must be registered",
            _mutate_json("client/data/skills.json", _set_skill_damage_type("arcane")),
            [
                "client/data/skills.json:skills[0].effects[0].params.damage_type",
                "unknown id arcane; expected one of damage_types",
            ],
        ),
        (
            "skill weapon modifier duration must be positive",
            _mutate_json("client/data/skills.json", _set_skill_weapon_modifier_duration(0.0)),
            [
                "client/data/skills.json:skills[0].effects[0].params.duration",
                "must be > 0",
            ],
        ),
        (
            "skill weapon modifier stat must be registered",
            _mutate_json("client/data/skills.json", _set_skill_weapon_modifier_stat("stat_missing")),
            [
                "client/data/skills.json:skills[0].effects[0].params.modifiers[0].stat",
                "unknown id stat_missing; expected one of stats",
            ],
        ),
        (
            "consumable must include consumable tag",
            _mutate_json("client/data/consumables.json", _set_consumable_tags([])),
            [
                "client/data/consumables.json:consumables[0].tags",
                "must include tag_consumable",
            ],
        ),
        (
            "consumable effect must be registered",
            _mutate_json("client/data/consumables.json", _set_consumable_effect("arcane")),
            [
                "client/data/consumables.json:consumables[0].use_effects[0].effect",
                "unknown id arcane; expected one of effects",
            ],
        ),
        (
            "consumable start count cannot exceed max stack",
            _mutate_json("client/data/consumables.json", _set_consumable_start_count(4)),
            [
                "client/data/consumables.json:consumables[0].stack.start_count",
                "must be <= max_stack",
            ],
        ),
        (
            "mode consumable reference must exist",
            _mutate_json("client/data/game_modes.json", _set_mode_consumable("consumable_missing")),
            [
                "client/data/game_modes.json:modes[0].resource_pools.consumables[0].id",
                "consumable is not defined in consumables.json: consumable_missing",
            ],
        ),
        (
            "credits section title locale key must exist",
            _mutate_json("client/data/credits.json", _set_credit_section_title_key("ui_credits_missing_section")),
            [
                "client/data/credits.json:sections[0].title_key",
                "locale key is missing from client/locale/strings.csv: ui_credits_missing_section",
            ],
        ),
        (
            "external credit license must be present",
            _mutate_json("client/data/credits.json", _clear_first_external_credit_license),
            [
                "client/data/credits.json:sections[0].entries[1].license",
                "must be a non-empty string",
            ],
        ),
        (
            "camera shake amplitude must be non-negative",
            _mutate_json("client/data/camera_feedback.json", _set_camera_feedback_value("amplitude", -1.0)),
            [
                "client/data/camera_feedback.json:player_damage_shake.amplitude",
                "must be >= 0.0",
            ],
        ),
        (
            "camera shake duration must be positive",
            _mutate_json("client/data/camera_feedback.json", _set_camera_feedback_value("duration", 0.0)),
            [
                "client/data/camera_feedback.json:player_damage_shake.duration",
                "must be > 0.0",
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


def _mutate_csv(relative_path: str, mutator: CsvMutator) -> RepoMutator:
    def mutate_repo(root: Path) -> None:
        path = root / relative_path
        with path.open(encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle)
            rows = list(reader)
            fieldnames = reader.fieldnames or []
        mutator(rows)
        with path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)

    return mutate_repo


def _set_character_id(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["characters"][0]["id"] = value

    return mutate


def _set_camera_feedback_value(field: str, value: object) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["player_damage_shake"][field] = value

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


def _set_game_mode_id(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["modes"][0]["id"] = value

    return mutate


def _set_mode_growth_pool(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["modes"][0]["resource_pools"]["growth_pools"] = [{"id": value, "weight": 100}]

    return mutate


def _set_warzone_phase_wave(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["directors"][0]["phases"][0]["wave_ids"][0] = value

    return mutate


def _add_warzone_legacy_encounters(payload: dict[str, Any]) -> None:
    payload["directors"][0]["encounters"] = [
        {
            "id": "encounter_legacy",
            "kind": "enemy_ecology",
            "enemy_tags": ["tag_enemy"],
        }
    ]


def _add_warzone_legacy_phase_encounter_ids(payload: dict[str, Any]) -> None:
    payload["directors"][0]["phases"][0]["encounter_ids"] = ["encounter_legacy"]


def _set_warzone_interest_point_hazards(value: list[str]) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["directors"][0]["interest_points"][0]["hazard_ids"] = value

    return mutate


def _set_warzone_resource_reward(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["directors"][0]["interest_points"][0]["resource_rewards"] = [{"resource_id": value, "amount": 10}]

    return mutate


def _set_warzone_gear_mod_reward(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["directors"][0]["interest_points"][0]["gear_mod_rewards"] = [{"mod_id": value, "count": 1}]

    return mutate


def _set_warzone_interest_point_requires_interaction(value: Any) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["directors"][0]["interest_points"][0]["requires_interaction"] = value

    return mutate


def _set_warzone_interest_point_target_hp(value: int) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["directors"][0]["interest_points"][0]["target_hp"] = value

    return mutate


def _set_warzone_completion_extraction_radius(value: int) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["directors"][0]["interest_points"][3]["extraction_radius"] = value

    return mutate


def _set_warzone_completion_extraction_hold_time(value: int) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["directors"][0]["interest_points"][3]["extraction_hold_time"] = value

    return mutate


def _set_growth_entry_name_key(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["pools"][0]["entries"][0]["name_key"] = value

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
        payload["characters"][0]["starting_loadout"]["weapon_id"] = value

    return mutate


def _set_character_starting_active_item(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["characters"][0]["starting_loadout"]["active_item_id"] = value

    return mutate


def _set_character_starting_consumable(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["characters"][0]["starting_loadout"]["consumable_ids"][0] = value

    return mutate


def _set_character_starting_skill(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["characters"][0]["starting_loadout"]["skill_ids"][0] = value

    return mutate


def _set_mode_weapon(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["modes"][0]["resource_pools"]["weapons"][0]["id"] = value

    return mutate


def _set_mode_skill(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["modes"][0]["resource_pools"]["skills"][0]["id"] = value

    return mutate


def _set_enemy_tags(value: str) -> CsvMutator:
    def mutate(rows: list[dict[str, str]]) -> None:
        rows[0]["tags"] = value

    return mutate


def _set_enemy_damage_type(value: str) -> CsvMutator:
    def mutate(rows: list[dict[str, str]]) -> None:
        rows[0]["contact_damage_type"] = value

    return mutate


def _set_enemy_ai_action(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["profiles"][0]["actions"][0]["id"] = value

    return mutate


def _set_schema_version(value: int) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["schema_version"] = value

    return mutate


def _add_enemy_ai_legacy_contact_interval(payload: dict[str, Any]) -> None:
    payload["profiles"][0]["contact_interval"] = 0.45


def _add_enemy_ai_legacy_sense_radius(payload: dict[str, Any]) -> None:
    payload["profiles"][0]["sense_radius"] = 760.0


def _remove_enemy_ai_perception(payload: dict[str, Any]) -> None:
    payload["profiles"][0].pop("perception", None)


def _set_enemy_ai_perception_value(key: str, value: Any) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["profiles"][0]["perception"][key] = value

    return mutate


def _add_enemy_ai_legacy_hunt_tags(payload: dict[str, Any]) -> None:
    payload["profiles"][0]["targeting"]["hunt_tags"] = [{"tag": "tag_enemy", "weight": 1.0}]


def _add_enemy_ai_legacy_flee_tags(payload: dict[str, Any]) -> None:
    payload["profiles"][0]["targeting"]["flee_tags"] = [{"tag": "tag_enemy", "weight": 1.0}]


def _add_enemy_ai_legacy_flee_distance(payload: dict[str, Any]) -> None:
    payload["profiles"][0]["movement"]["flee_distance"] = 260.0


def _set_enemy_ai_profile(value: str) -> CsvMutator:
    def mutate(rows: list[dict[str, str]]) -> None:
        rows[0]["ai_profile_id"] = value

    return mutate


def _set_mode_enemy(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["modes"][0]["resource_pools"]["enemies"][0]["id"] = value

    return mutate


def _set_gear_mod_id(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["mods"][0]["id"] = value

    return mutate


def _set_gear_mod_name_key(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["mods"][0]["name_key"] = value

    return mutate


def _set_gear_mod_modifier_stat(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["mods"][0]["rank_modifiers"][0]["stat"] = value

    return mutate


def _set_gear_mod_drop_enemy(value: str) -> CsvMutator:
    def mutate(rows: list[dict[str, str]]) -> None:
        rows[0]["source_enemy_id"] = value

    return mutate


def _set_gear_mod_drop_chance(value: str) -> CsvMutator:
    def mutate(rows: list[dict[str, str]]) -> None:
        rows[0]["drop_chance"] = value

    return mutate


def _set_gear_mod_fusion_resource(value: str) -> CsvMutator:
    def mutate(rows: list[dict[str, str]]) -> None:
        rows[0]["resource_id"] = value

    return mutate


def _remove_gear_mod_fusion_rank(value: str) -> CsvMutator:
    def mutate(rows: list[dict[str, str]]) -> None:
        rows[:] = [row for row in rows if row.get("rank") != value]

    return mutate


def _set_hazard_tags(value: str) -> CsvMutator:
    def mutate(rows: list[dict[str, str]]) -> None:
        rows[0]["tags"] = value

    return mutate


def _set_hazard_damage_type(value: str) -> CsvMutator:
    def mutate(rows: list[dict[str, str]]) -> None:
        rows[0]["damage_type"] = value

    return mutate


def _set_hazard_radius_tiles(value: str) -> CsvMutator:
    def mutate(rows: list[dict[str, str]]) -> None:
        rows[0]["radius_tiles"] = value

    return mutate


def _set_mode_hazard(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["modes"][0]["resource_pools"]["hazards"][0]["id"] = value

    return mutate


def _set_map_layout_mode(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["layouts"][0]["mode_id"] = value

    return mutate


def _set_map_layout_pcg_hazard(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["layouts"][0]["pcg"]["hazards"][0]["id"] = value

    return mutate


def _set_map_layout_grid_cell_width(value: float) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["layouts"][0]["grid"]["cell_width"] = value

    return mutate


def _set_map_layout_bounds_height(value: float) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["layouts"][0]["bounds"]["height"] = value

    return mutate


def _set_map_layout_bounds_size(width: float, height: float) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["layouts"][0]["bounds"]["width"] = width
        payload["layouts"][0]["bounds"]["height"] = height

    return mutate


def _set_manual_hazard_position(index: int, x: float, y: float) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        manual_hazards = payload["layouts"][0].setdefault("manual_hazards", [])
        while len(manual_hazards) <= index:
            manual_hazards.append({"id": "hazard_fea_12_pulse", "x": 480.0, "y": -200.0})
        manual_hazards[index]["x"] = x
        manual_hazards[index]["y"] = y

    return mutate


def _set_spawn_wave_enemy(value: str) -> CsvMutator:
    def mutate(rows: list[dict[str, str]]) -> None:
        rows[0]["enemy_id"] = value

    return mutate


def _set_spawn_wave_mode(value: str) -> CsvMutator:
    def mutate(rows: list[dict[str, str]]) -> None:
        rows[0]["mode_id"] = value

    return mutate


def _set_spawn_wave_end_time(value: str) -> CsvMutator:
    def mutate(rows: list[dict[str, str]]) -> None:
        rows[0]["end_time"] = value

    return mutate


def _set_spawn_wave_hazard(hazard_id: str, hazard_weight: str) -> CsvMutator:
    def mutate(rows: list[dict[str, str]]) -> None:
        rows[0]["hazard_id"] = hazard_id
        rows[0]["hazard_weight"] = hazard_weight

    return mutate


def _set_relic_tags(value: list[str]) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["relics"][0]["tags"] = value

    return mutate


def _set_relic_behavior_effect(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["relics"][0]["behaviors"] = [
            {
                "event": "on_hit",
                "effect": value,
                "params": {},
            }
        ]

    return mutate


def _clear_relic_effects(payload: dict[str, Any]) -> None:
    payload["relics"][0]["modifiers"] = []
    payload["relics"][0]["behaviors"] = []


def _set_mode_relic(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["modes"][0]["resource_pools"]["relics"][0]["id"] = value

    return mutate


def _set_active_item_tags(value: list[str]) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["active_items"][0]["tags"] = value

    return mutate


def _set_active_item_effect(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["active_items"][0]["use_effects"][0]["effect"] = value

    return mutate


def _set_active_item_start_charges(value: int) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["active_items"][0]["charge"]["start_charges"] = value

    return mutate


def _set_mode_active_item(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["modes"][0]["resource_pools"]["active_items"][0]["id"] = value

    return mutate


def _set_skill_cost_resource(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["skills"][0]["costs"][0]["resource"] = value

    return mutate


def _set_skill_ability_tag(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["skills"][0]["ability_tags"][0] = value

    return mutate


def _set_skill_activation_blocked_tag(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["skills"][0]["activation"]["blocked_tags"][0] = value

    return mutate


def _set_skill_apply_status_param(field: str, value: Any) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["skills"][0]["effects"][0] = _apply_status_effect_payload()
        payload["skills"][0]["effects"][0]["params"][field] = value

    return mutate


def _set_skill_apply_status_granted_tag(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["skills"][0]["effects"][0] = _apply_status_effect_payload()
        payload["skills"][0]["effects"][0]["params"]["granted_ability_tags"][0] = value

    return mutate


def _set_skill_apply_status_dot_without_damage_type(payload: dict[str, Any]) -> None:
    payload["skills"][0]["effects"][0] = _apply_status_effect_payload()
    params = payload["skills"][0]["effects"][0]["params"]
    params["status"] = "poison"
    params["magnitude"] = 2.0
    params["tick_interval"] = 0.5
    params.pop("damage_type", None)


def _apply_status_effect_payload() -> dict[str, Any]:
    return {
        "effect": "skill_effect_apply_status",
        "params": {
            "status": "silence",
            "duration": 1.0,
            "stack_rule": "REFRESH",
            "granted_ability_tags": ["ability_tag_silenced"],
        },
    }


def _set_skill_damage_type(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["skills"][0]["effects"][0] = {
            "effect": "skill_effect_damage",
            "params": {
                "amount": 8.0,
                "damage_type": "physical",
            },
        }
        payload["skills"][0]["effects"][0]["params"]["damage_type"] = value

    return mutate


def _set_skill_weapon_modifier_duration(value: float) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["skills"][0]["effects"][0]["params"]["duration"] = value

    return mutate


def _set_skill_weapon_modifier_stat(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["skills"][0]["effects"][0]["params"]["modifiers"][0]["stat"] = value

    return mutate


def _set_consumable_tags(value: list[str]) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["consumables"][0]["tags"] = value

    return mutate


def _set_consumable_effect(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["consumables"][0]["use_effects"][0]["effect"] = value

    return mutate


def _set_consumable_start_count(value: int) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["consumables"][0]["stack"]["start_count"] = value

    return mutate


def _set_mode_consumable(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["modes"][0]["resource_pools"]["consumables"][0]["id"] = value

    return mutate


def _set_credit_section_title_key(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["sections"][0]["title_key"] = value

    return mutate


def _clear_first_external_credit_license(payload: dict[str, Any]) -> None:
    payload["sections"][0]["entries"][1]["license"] = ""


def _set_module_world_columns(value: int) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["worlds"][0]["columns"] = value

    return mutate


def _set_module_world_cell_size(value: float) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["worlds"][0]["cell_size"] = value

    return mutate


def _remove_fixed_objective_slot(payload: dict[str, Any]) -> None:
    world = payload["worlds"][0]
    objective_slot = world["objective_slot"]
    world["fixed_slots"] = [
        entry for entry in world["fixed_slots"] if entry["slot"] != objective_slot
    ]


def _replace_fixed_objective_with_connector(payload: dict[str, Any]) -> None:
    world = payload["worlds"][0]
    objective_slot = world["objective_slot"]
    for entry in world["fixed_slots"]:
        if entry["slot"] == objective_slot:
            entry["template_id"] = "module_connector_cross"
            entry["rotation"] = 0
            return


def _add_duplicate_fixed_start_role(payload: dict[str, Any]) -> None:
    payload["worlds"][0]["fixed_slots"].append(
        {"slot": {"x": 1, "y": 1}, "template_id": "module_start_cross", "rotation": 0}
    )


def _set_optional_exploration_max(value: int) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["worlds"][0]["route_budget"]["optional_exploration_modules"]["max"] = value

    return mutate


def _remove_module_terrain_row(payload: dict[str, Any]) -> None:
    payload["terrain_rows"].pop()


def _make_first_pool_template_candidate(payload: dict[str, Any]) -> None:
    for template in payload["templates"]:
        if template["id"] == "module_connector_cross":
            template["review_status"] = "module_review_candidate"
            return


def _remove_fallback_assignment(payload: dict[str, Any]) -> None:
    payload["worlds"][0]["fallback_assignment"].pop()


def _duplicate_fallback_slot(payload: dict[str, Any]) -> None:
    assignment = payload["worlds"][0]["fallback_assignment"]
    assignment[1]["slot"] = dict(assignment[0]["slot"])


def _close_module_east_socket(payload: dict[str, Any]) -> None:
    payload["edge_sockets"]["edge_east"] = []


def _set_unknown_module_token(payload: dict[str, Any]) -> None:
    payload["terrain_rows"][0][0] = "module_cell_unknown"


def _set_unknown_module_placement(payload: dict[str, Any]) -> None:
    payload["placements"][0]["type"] = "module_place_unknown"


def _set_module_placement_out_of_bounds(payload: dict[str, Any]) -> None:
    payload["placements"][0]["cell"]["x"] = 11


def _set_module_enemy_spawn_on_blocked_cell(payload: dict[str, Any]) -> None:
    for placement in payload["placements"]:
        if placement["type"] == "module_place_enemy_spawn":
            placement["cell"] = {"x": 0, "y": 0}
            return


def _exceed_combat_enemy_budget(payload: dict[str, Any]) -> None:
    for placement in payload["placements"]:
        if placement["type"] == "module_place_enemy_spawn":
            placement["count"] = 13
            return


def _close_all_module_sockets(payload: dict[str, Any]) -> None:
    for direction in payload["edge_sockets"]:
        payload["edge_sockets"][direction] = []


def _format_failure(name: str, output: str, reason: str) -> str:
    return f"[data-loader-schema-test] {name}: failed; {reason}\n{output.rstrip()}"


if __name__ == "__main__":
    sys.exit(main())
