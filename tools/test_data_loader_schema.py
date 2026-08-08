#!/usr/bin/env python3
"""Regression tests for DataLoader-facing project data schema validation."""

from __future__ import annotations

import json
import math
import shutil
import subprocess
import sys
import tempfile
import csv
from collections.abc import Callable
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DIFFICULTY_PROFILE_PATH = ROOT / "client" / "data" / "difficulty_profiles.json"


JsonMutator = Callable[[dict[str, Any]], None]
CsvMutator = Callable[[list[dict[str, str]]], None]
RepoMutator = Callable[[Path], None]


def main() -> int:
    cases: list[tuple[str, RepoMutator | None, list[str]]] = [
        ("golden data passes", None, []),
        (
            "player schema v4 is required",
            _mutate_json("client/data/player.json", _set_schema_version(1)),
            [
                "client/data/player.json:schema_version",
                "must be >= 4",
                "must equal 4",
            ],
        ),
        (
            "player body is required",
            _mutate_json("client/data/player.json", _remove_player_body),
            [
                "client/data/player.json:body",
                "must be an object",
            ],
        ),
        (
            "player body radius must be positive",
            _mutate_json("client/data/player.json", _set_player_body_radius(0.0)),
            [
                "client/data/player.json:body.radius",
                "must be > 0",
            ],
        ),
        (
            "player schema v3 rejects pickup orb speed",
            _mutate_json("client/data/player.json", _add_legacy_pickup_orb_speed),
            [
                "client/data/player.json:base_stats.pickup_orb_speed",
                "was removed in schema_version 3",
            ],
        ),
        (
            "dash distance must match speed and duration",
            _mutate_json("client/data/player.json", _set_dash_distance(121.0)),
            [
                "client/data/player.json:dash.distance",
                "must equal dash.speed * dash.duration",
            ],
        ),
        (
            "energy drop pool must be registered",
            _mutate_json("client/data/player.json", _set_energy_drop_pool("pool_missing")),
            [
                "client/data/player.json:energy_drop.pool_id",
                "unknown id pool_missing; expected one of pool_ids",
            ],
        ),
        (
            "gold drop pickup speed must be positive",
            _mutate_json("client/data/player.json", _set_drop_pickup_speed("gold_drop", 0.0)),
            [
                "client/data/player.json:gold_drop.pickup_speed",
                "must be > 0",
            ],
        ),
        (
            "energy drop pickup speed must be positive",
            _mutate_json("client/data/player.json", _set_drop_pickup_speed("energy_drop", 0.0)),
            [
                "client/data/player.json:energy_drop.pickup_speed",
                "must be > 0",
            ],
        ),
        (
            "level progression first cost must be positive",
            _mutate_json("client/data/level_progression.json", _set_level_progression_field("first_level_cost", 0)),
            [
                "client/data/level_progression.json:first_level_cost",
                "must be >= 1",
            ],
        ),
        (
            "level progression denominator must be positive",
            _mutate_json("client/data/level_progression.json", _set_level_progression_field("multiplier_denominator", 0)),
            [
                "client/data/level_progression.json:multiplier_denominator",
                "must be >= 1",
            ],
        ),
        (
            "level progression multiplier must grow",
            _mutate_json("client/data/level_progression.json", _set_level_progression_field("multiplier_numerator", 10)),
            [
                "client/data/level_progression.json:multiplier_numerator",
                "must be greater than multiplier_denominator",
            ],
        ),
        (
            "element combinations are symmetric and unique",
            _mutate_json("client/data/elements.json", _duplicate_reversed_element_combination),
            [
                "client/data/elements.json:combinations[3]",
                "duplicate symmetric combination",
            ],
        ),
        (
            "composite elements do not become combination inputs",
            _mutate_json("client/data/elements.json", _set_composite_combination_input),
            [
                "client/data/elements.json:combinations[0]",
                "combination inputs must be primary elements",
            ],
        ),
        (
            "visual effect ids must be unique",
            _mutate_json("client/data/visual_effects.json", _duplicate_visual_effect_id),
            [
                "client/data/visual_effects.json:effects[1].id",
                "duplicate effect id",
            ],
        ),
        (
            "high-frequency visual effects require pools",
            _mutate_json(
                "client/data/visual_effects.json",
                _remove_high_frequency_visual_effect_pool,
            ),
            [
                "client/data/visual_effects.json:effects[0].pool_id",
                "required for high-frequency effects",
            ],
        ),
        (
            "visual effects schema v3 is required",
            _mutate_json(
                "client/data/visual_effects.json",
                _set_schema_version(2),
            ),
            [
                "client/data/visual_effects.json:schema_version",
                "must equal 3",
            ],
        ),
        (
            "visual effects reject retired quality variants",
            _mutate_json(
                "client/data/visual_effects.json",
                _add_legacy_quality_variants,
            ),
            [
                "client/data/visual_effects.json:effects[0].quality_variants",
                "removed in schema v3",
            ],
        ),
        (
            "visual effects reject retired reduced-motion fields",
            _mutate_json(
                "client/data/visual_effects.json",
                _add_legacy_reduced_motion,
            ),
            [
                "client/data/visual_effects.json:effects[0].reduced_motion",
                "removed in schema v2",
            ],
        ),
        (
            "presentation profile inheritance must be acyclic",
            _mutate_json(
                "client/data/presentation_profiles.json",
                _create_presentation_profile_cycle,
            ),
            [
                "client/data/presentation_profiles.json:presentation_gameplay_default.parent_profile_id",
                "profile inheritance must be acyclic",
            ],
        ),
        (
            "module world schema v5 is required",
            _mutate_json("client/data/module_worlds.json", _set_schema_version(4)),
            [
                "client/data/module_worlds.json:schema_version",
                "must equal 5",
            ],
        ),
        (
            "world event schema v2 is required",
            _mutate_json("client/data/world_events.json", _set_schema_version(1)),
            [
                "client/data/world_events.json:schema_version",
                "must equal 2",
            ],
        ),
        (
            "defense world event target hit radius is required",
            _mutate_json(
                "client/data/world_events.json",
                _remove_defense_target_hit_radius,
            ),
            [
                "client/data/world_events.json:events[0]",
                "fields must exactly match world_event_kind_defense schema",
                "client/data/world_events.json:events[0].target_hit_radius",
                "must be number",
            ],
        ),
        (
            "world event kind rejects surplus fields",
            _mutate_json("client/data/world_events.json", _add_world_event_surplus_field),
            [
                "client/data/world_events.json:events[1]",
                "fields must exactly match world_event_kind_survival schema",
            ],
        ),
        (
            "gold shrine chance must stay below one",
            _mutate_json("client/data/world_events.json", _set_gold_shrine_chance_one),
            [
                "client/data/world_events.json:events[3].success_chance",
                "must be < 1.0",
            ],
        ),
        (
            "world event wave cannot exceed duration",
            _mutate_json("client/data/world_events.json", _set_defense_wave_after_duration),
            [
                "client/data/world_events.json:events[0].waves[2].trigger",
                "must be <= 45.0",
            ],
        ),
        (
            "limited template group pick cannot exceed entries",
            _mutate_json("client/data/module_worlds.json", _set_limited_group_pick_too_high),
            [
                "client/data/module_worlds.json:worlds[0].limited_template_groups[0].pick_distinct",
                "must not exceed entries length",
            ],
        ),
        (
            "limited template group requires world event role",
            _mutate_json("client/data/module_worlds.json", _set_limited_group_flat_template),
            [
                "client/data/module_worlds.json:worlds[0].limited_template_groups[0].entries[0].template_id",
                "template must use module_role_world_event",
            ],
        ),
        (
            "module world must be 7x7",
            _mutate_json("client/data/module_worlds.json", _set_module_world_columns(8)),
            ["client/data/module_worlds.json:worlds[0].columns", "must equal 7"],
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
            "first visit enemy pool rejects unknown enemies",
            _mutate_json("client/data/module_worlds.json", _set_first_visit_enemy_unknown),
            [
                "client/data/module_worlds.json:worlds[0].first_visit_enemy_spawn.enemy_pool[0].enemy_id",
                "enemy is not defined in enemies.csv",
            ],
        ),
        (
            "first visit unlock time cannot be negative",
            _mutate_json("client/data/module_worlds.json", _set_first_visit_unlock_negative),
            [
                "client/data/module_worlds.json:worlds[0].first_visit_enemy_spawn.enemy_pool[0].unlock_time",
                "must be >= 0.0",
            ],
        ),
        (
            "first visit enemy weight must be positive",
            _mutate_json("client/data/module_worlds.json", _set_first_visit_weight_zero),
            [
                "client/data/module_worlds.json:worlds[0].first_visit_enemy_spawn.enemy_pool[0].weight",
                "must be > 0.0",
            ],
        ),
        (
            "fixed slots must cover configured start",
            _mutate_json("client/data/module_worlds.json", _remove_fixed_start_slot),
            ["client/data/module_worlds.json:worlds[0].fixed_slots", "must assign configured start_slot"],
        ),
        (
            "objective spawn must use its required role",
            _mutate_json("client/data/module_worlds.json", _replace_objective_spawn_with_connector),
            ["client/data/module_worlds.json:worlds[0].objective_spawn.template_id", "template must use module_role_objective"],
        ),
        (
            "fixed slots require unique critical roles",
            _mutate_json("client/data/module_worlds.json", _add_duplicate_fixed_start_role),
            ["client/data/module_worlds.json:worlds[0].fixed_slots", "must contain exactly one module_role_start"],
        ),
        (
            "objective spawn requires three candidates",
            _mutate_json("client/data/module_worlds.json", _remove_objective_candidate),
            ["client/data/module_worlds.json:worlds[0].objective_spawn.candidate_slots", "must contain exactly 3 candidate slots"],
        ),
        (
            "objective spawn candidates must be unique",
            _mutate_json("client/data/module_worlds.json", _duplicate_objective_candidate),
            ["client/data/module_worlds.json:worlds[0].objective_spawn.candidate_slots[1]", "duplicate slot 0,0"],
        ),
        (
            "objective spawn candidates stay inside 7x7",
            _mutate_json("client/data/module_worlds.json", _move_objective_candidate_out_of_bounds),
            ["client/data/module_worlds.json:worlds[0].objective_spawn.candidate_slots[2].x", "must be < 7"],
        ),
        (
            "objective spawn candidates use only the three required corners",
            _mutate_json("client/data/module_worlds.json", _move_objective_candidate_inside_bounds),
            ["client/data/module_worlds.json:worlds[0].objective_spawn.candidate_slots", "must equal the top-left, top-right, and bottom-right corners"],
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
            "module schema v4 derives sockets and accepts visual layers",
            _mutate_json("client/data/modules/module_start_cross.json", _upgrade_module_to_v4),
            [],
        ),
        (
            "module schema v3 is no longer accepted",
            _mutate_json("client/data/modules/module_start_cross.json", _downgrade_module_to_v3),
            [
                "client/data/modules/module_start_cross.json:schema_version",
                "must be >= 4",
                "must be 4",
            ],
        ),
        (
            "module schema v4 must omit derived sockets",
            _mutate_json("client/data/modules/module_start_cross.json", _upgrade_module_to_v4_keep_sockets),
            [
                "client/data/modules/module_start_cross.json:edge_sockets",
                "must be omitted in schema v4 because sockets are derived",
            ],
        ),
        (
            "module visual tile id must be registered",
            _mutate_json("client/data/modules/module_start_cross.json", _set_v4_unknown_visual_tile),
            [
                "client/data/modules/module_start_cross.json:visual_layers.ground.overrides[0].tile_id",
                "unknown id module_tile_unknown; expected one of module_tile_ids",
            ],
        ),
        (
            "module visual tile must belong to its layer",
            _mutate_json("client/data/modules/module_start_cross.json", _set_v4_wrong_layer_tile),
            [
                "client/data/modules/module_start_cross.json:visual_layers.ground.default_tile_id",
                "tile must belong to the ground layer",
            ],
        ),
        (
            "module visual transform rotation must be orthogonal",
            _mutate_json("client/data/modules/module_start_cross.json", _set_v4_invalid_visual_rotation),
            [
                "client/data/modules/module_start_cross.json:visual_layers.decoration.cells[0].rotation",
                "must be 0, 90, 180, or 270",
            ],
        ),
        (
            "module decoration layer must remain sparse",
            _mutate_json("client/data/modules/module_start_cross.json", _set_v4_decoration_default_tile),
            [
                "client/data/modules/module_start_cross.json:visual_layers.decoration",
                "must define exactly cells",
            ],
        ),
        (
            "module tile catalog id must be stable and registered",
            _mutate_json("client/data/module_tile_catalog.json", _set_unknown_module_tile_catalog_id),
            [
                "client/data/module_tile_catalog.json:tiles[0].id",
                "unknown id module_tile_unknown; expected one of module_tile_ids",
                "must define every registered module_tile_id exactly once",
            ],
        ),
        (
            "candidate template cannot enter formal pool",
            _mutate_json("client/data/module_templates.json", _make_first_pool_template_candidate),
            ["client/data/module_worlds.json:worlds[0].template_pool[0]", "formal template pool requires approved template"],
        ),
        (
            "approved module template requires gameplay approval hash",
            _mutate_json("client/data/module_templates.json", _remove_first_approved_gameplay_hash),
            ["client/data/module_templates.json:templates[0].approved_gameplay_hash", "approved template must store a gameplay approval sha256"],
        ),
        (
            "candidate module template cannot keep gameplay approval hash",
            _mutate_json("client/data/module_templates.json", _make_sealed_template_keep_approved_hash),
            ["client/data/module_templates.json:templates[", ".approved_gameplay_hash", "must be omitted unless the template is approved"],
        ),
        (
            "fallback assignment must contain 49 slots",
            _mutate_json("client/data/module_worlds.json", _remove_fallback_assignment),
            ["client/data/module_worlds.json:worlds[0].fallback_assignment", "must contain exactly 49 slot assignments"],
        ),
        (
            "fallback assignment slots must be unique",
            _mutate_json("client/data/module_worlds.json", _duplicate_fallback_slot),
            ["client/data/module_worlds.json:worlds[0].fallback_assignment[1].slot", "duplicate slot 0,0"],
        ),
        (
            "adjacent modules require a shared open socket",
            _mutate_json("client/data/modules/module_world_event_defense.json", _close_module_east_socket),
            [
                "client/data/module_worlds.json:worlds[0].technical_slice_assignment",
                "no shared open socket between slot",
            ],
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
            "module reward cache gold must be positive",
            _mutate_json("client/data/modules/module_resource_cache.json", _set_module_reward_gold_zero),
            [
                "client/data/modules/module_resource_cache.json:placements[0].gold_reward_amount",
                "must be >= 1",
            ],
        ),
        (
            "module reward cache rejects retired resource rewards",
            _mutate_json("client/data/modules/module_resource_cache.json", _add_legacy_module_resource_rewards),
            [
                "client/data/modules/module_resource_cache.json:placements[0].resource_rewards",
                "was removed; use gold_reward_amount or Gear Mod pool fields",
            ],
        ),
        (
            "world event placement requires a registered event id",
            _mutate_json(
                "client/data/modules/module_world_event_defense.json",
                _set_unknown_world_event_placement_id,
            ),
            [
                "client/data/modules/module_world_event_defense.json:placements[0].world_event_id",
                "unknown id world_event_unknown; expected one of world_event_ids",
            ],
        ),
        (
            "world event placement rejects surplus fields",
            _mutate_json(
                "client/data/modules/module_world_event_defense.json",
                _add_world_event_placement_surplus_field,
            ),
            [
                "client/data/modules/module_world_event_defense.json:placements[0]",
                "must define exactly type, cell, and world_event_id",
            ],
        ),
        (
            "legacy module enemy placement is rejected",
            _mutate_json(
                "client/data/modules/module_flat_ground.json",
                _add_legacy_module_enemy_spawn,
            ),
            [
                "client/data/modules/module_flat_ground.json:placements[0].type",
                "unknown id module_place_enemy_spawn; expected one of module_placement_types",
            ],
        ),
        (
            "formal templates need enough spawnable floor cells",
            _mutate_json(
                "client/data/modules/module_flat_ground.json",
                _leave_five_spawnable_floor_cells,
            ),
            [
                "client/data/module_worlds.json:worlds[0].template_pool[0]",
                "formal template needs at least 6 spawnable floor cells",
            ],
        ),
        (
            "fallback templates need enough spawnable floor cells",
            _make_fallback_template_insufficient,
            [
                "client/data/module_worlds.json:worlds[0].fallback_assignment",
                "at least 6 spawnable floor cells",
            ],
        ),
        (
            "critical module route must be reachable",
            _mutate_json("client/data/modules/module_objective_core.json", _close_all_module_sockets),
            ["client/data/module_worlds.json:worlds[0].fallback_assignment.objective_candidate[0]", "critical route start -> objective is unreachable"],
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
            "character schema v4 is required",
            _mutate_json("client/data/characters.json", _set_schema_version(1)),
            [
                "client/data/characters.json:schema_version",
                "must be >= 4",
                "must equal 4",
            ],
        ),
        (
            "character palette primary is required",
            _mutate_json(
                "client/data/characters.json",
                _remove_character_palette_primary,
            ),
            [
                "client/data/characters.json:characters[0].palette",
                "must contain exactly ['primary']",
            ],
        ),
        (
            "character palette primary must be a color",
            _mutate_json(
                "client/data/characters.json",
                _set_character_palette_primary("blue"),
            ),
            [
                "client/data/characters.json:characters[0].palette.primary",
                "must be a #RRGGBB or #RRGGBBAA color",
            ],
        ),
        (
            "character palette rejects legacy secondary",
            _mutate_json(
                "client/data/characters.json",
                _add_character_palette_key("secondary", "#000000"),
            ),
            [
                "client/data/characters.json:characters[0].palette",
                "must contain exactly ['primary']",
            ],
        ),
        (
            "character palette rejects extra keys",
            _mutate_json(
                "client/data/characters.json",
                _add_character_palette_key("extra", "#FFFFFF"),
            ),
            [
                "client/data/characters.json:characters[0].palette",
                "must contain exactly ['primary']",
            ],
        ),
        (
            "character scene path is required",
            _mutate_json("client/data/characters.json", _remove_character_scene_path),
            [
                "client/data/characters.json:characters[0].scene_path",
                "must be a non-empty actor scene path",
            ],
        ),
        (
            "character scene must stay in the dedicated actor directory",
            _mutate_json(
                "client/data/characters.json",
                _set_character_scene_path("res://scenes/gameplay/actors/player_base.tscn"),
            ),
            [
                "client/data/characters.json:characters[0].scene_path",
                "must be a project actor .tscn under res://scenes/gameplay/actors/characters/",
            ],
        ),
        (
            "character scene must exist",
            _mutate_json(
                "client/data/characters.json",
                _set_character_scene_path(
                    "res://scenes/gameplay/actors/characters/character_missing.tscn"
                ),
            ),
            [
                "client/data/characters.json:characters[0].scene_path",
                "actor scene does not exist",
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
                "character is not defined in characters.json: character_primary_a",
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
            "difficulty profile schema v1 is rejected",
            _mutate_json(
                "client/data/difficulty_profiles.json",
                _set_schema_version(1),
            ),
            [
                "client/data/difficulty_profiles.json:schema_version",
                "must equal 2",
            ],
        ),
        (
            "difficulty coefficient must be positive",
            _mutate_json(
                "client/data/difficulty_profiles.json",
                _set_difficulty_profile_field(
                    "difficulty_coefficient",
                    0.0,
                ),
            ),
            [
                "client/data/difficulty_profiles.json:profiles[0].difficulty_coefficient",
                "must be > 0.0",
            ],
        ),
        (
            "difficulty profiles reject extra fields",
            _mutate_json(
                "client/data/difficulty_profiles.json",
                _set_difficulty_profile_field("surplus", True),
            ),
            [
                "client/data/difficulty_profiles.json:profiles[0].surplus",
                "is not allowed",
            ],
        ),
        (
            "enemy reward schema v1 is required",
            _mutate_json(
                "client/data/enemy_rewards.json",
                _set_schema_version(0),
            ),
            [
                "client/data/enemy_rewards.json:schema_version",
                "must equal 1",
            ],
        ),
        (
            "enemy reward fields are required",
            _mutate_json(
                "client/data/enemy_rewards.json",
                _remove_enemy_reward_field("base_coefficient"),
            ),
            [
                "client/data/enemy_rewards.json:root.base_coefficient",
                "is required",
            ],
        ),
        (
            "enemy reward rejects extra fields",
            _mutate_json(
                "client/data/enemy_rewards.json",
                _set_enemy_reward_field("surplus", 1.0),
            ),
            [
                "client/data/enemy_rewards.json:root.surplus",
                "is not allowed",
            ],
        ),
        (
            "enemy reward base coefficient must be positive",
            _mutate_json(
                "client/data/enemy_rewards.json",
                _set_enemy_reward_field("base_coefficient", 0.0),
            ),
            [
                "client/data/enemy_rewards.json:base_coefficient",
                "must be > 0.0",
            ],
        ),
        (
            "enemy reward time growth cannot be negative",
            _mutate_json(
                "client/data/enemy_rewards.json",
                _set_enemy_reward_field("time_growth_per_tier", -0.01),
            ),
            [
                "client/data/enemy_rewards.json:time_growth_per_tier",
                "must be >= 0.0",
            ],
        ),
        (
            "enemy reward random interval must be ordered",
            _mutate_json(
                "client/data/enemy_rewards.json",
                _set_enemy_reward_random_interval(1.2, 1.1),
            ),
            [
                "client/data/enemy_rewards.json:random_multiplier_min",
                "must be <= random_multiplier_max",
            ],
        ),
        (
            "enemy reward random bounds must be positive",
            _mutate_json(
                "client/data/enemy_rewards.json",
                _set_enemy_reward_random_interval(0.0, 1.1),
            ),
            [
                "client/data/enemy_rewards.json:random_multiplier_min",
                "must be > 0.0",
            ],
        ),
        (
            "legacy enemy gold reward column is rejected",
            _replace_enemy_reward_header_with_legacy,
            [
                "client/data/enemies.csv:header",
                "missing required columns ['gold_value_multiplier']",
            ],
        ),
        (
            "enemy gold value multiplier must be positive",
            _mutate_csv(
                "client/data/enemies.csv",
                _set_enemy_gold_value_multiplier("0"),
            ),
            [
                "client/data/enemies.csv:line 2.gold_value_multiplier",
                "must be > 0",
            ],
        ),
        (
            "game mode schema v3 is required",
            _mutate_json("client/data/game_modes.json", _set_schema_version(1)),
            [
                "client/data/game_modes.json:schema_version",
                "must equal 3",
            ],
        ),
        (
            "game mode difficulty profile reference must exist",
            _mutate_json(
                "client/data/game_modes.json",
                _set_mode_difficulty_profile("difficulty_missing"),
            ),
            [
                "client/data/game_modes.json:modes[0].difficulty_profile_id",
                "profile is not defined in difficulty_profiles.json: difficulty_missing",
            ],
        ),
        (
            "difficulty tier interval must be positive",
            _mutate_json(
                "client/data/difficulty_profiles.json",
                _set_difficulty_profile_field("tier_interval_seconds", 0.0),
            ),
            [
                "client/data/difficulty_profiles.json:profiles[0].tier_interval_seconds",
                "must be > 0.0",
            ],
        ),
        (
            "difficulty growth values must stay in range",
            _mutate_json(
                "client/data/difficulty_profiles.json",
                _set_difficulty_profile_field(
                    "continuous_growth_per_interval",
                    -0.01,
                ),
            ),
            [
                "client/data/difficulty_profiles.json:profiles[0].continuous_growth_per_interval",
                "must be >= 0.0",
            ],
        ),
        (
            "difficulty stage names require nine entries",
            _mutate_json(
                "client/data/difficulty_profiles.json",
                _remove_last_difficulty_stage_name,
            ),
            [
                "client/data/difficulty_profiles.json:profiles[0].stage_name_keys",
                "must contain exactly 9 entries",
            ],
        ),
        (
            "difficulty stage names must be localized",
            _mutate_json(
                "client/data/difficulty_profiles.json",
                _set_difficulty_stage_name_key("ui_difficulty_stage_missing"),
            ),
            [
                "client/data/difficulty_profiles.json:profiles[0].stage_name_keys[0]",
                "locale key is missing from client/locale/strings.csv: ui_difficulty_stage_missing",
            ],
        ),
        (
            "game mode rejects retired growth pools",
            _mutate_json("client/data/game_modes.json", _add_legacy_growth_pool),
            [
                "client/data/game_modes.json:modes[0].resource_pools.growth_pools",
                "was removed in schema_version 3",
            ],
        ),
        (
            "weapon schema v4 is rejected",
            _mutate_json(
                "client/data/weapons.json",
                _set_schema_version(4),
            ),
            [
                "client/data/weapons.json:schema_version",
                "must be >= 5",
            ],
        ),
        (
            "weapon legacy ammo object is rejected",
            _mutate_json(
                "client/data/weapons.json",
                _add_legacy_weapon_ammo,
            ),
            [
                "client/data/weapons.json:weapons[0].ammo",
                "is not allowed",
            ],
        ),
        (
            "missing reward entry locale key fails",
            _mutate_json("client/data/reward_choice_pools.json", _set_reward_entry_name_key("ui_reward_missing_name")),
            [
                "client/data/reward_choice_pools.json:pools[0].entries[0].name_key",
                "locale key is missing from client/locale/strings.csv: ui_reward_missing_name",
            ],
        ),
        (
            "unknown weapon element fails",
            _mutate_json("client/data/weapons.json", _set_weapon_element("element_missing")),
            [
                "client/data/weapons.json:weapons[0].projectile.element_id",
                "unknown id element_missing; expected one of elements",
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
            "invalid weapon wall pierce fails",
            _mutate_json("client/data/weapons.json", _set_weapon_stat("wall_pierce", -1.0)),
            [
                "client/data/weapons.json:weapons[0].base_stats.wall_pierce",
                "must be >= 0",
            ],
        ),
        (
            "weapon recoil cannot exceed recoil model",
            _mutate_json("client/data/weapons.json", _set_weapon_stat("recoil", 101.0)),
            [
                "client/data/weapons.json:weapons[0].base_stats.recoil",
                "must be <= 100.0",
            ],
        ),
        (
            "base weapon spread cannot exceed 60 degrees",
            _mutate_json("client/data/weapons.json", _set_weapon_stat("spread_angle_max", 61.0)),
            [
                "client/data/weapons.json:weapons[0].base_stats.spread_angle_max",
                "must be <= 60.0",
            ],
        ),
        (
            "runtime spread cap cannot exceed 180 degrees",
            _mutate_json(
                "client/data/weapons.json",
                _set_weapon_recoil_model_value("runtime_spread_cap", 181.0),
            ),
            [
                "client/data/weapons.json:recoil_model.runtime_spread_cap",
                "must be <= 180.0",
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
            "character hero skill id must be registered",
            _mutate_json("client/data/characters.json", _set_character_hero_skill("skill_missing")),
            [
                "client/data/characters.json:characters[0].hero_skill_ids[0]",
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
            "enemy scene path can be shared by multiple content ids",
            _mutate_csv("client/data/enemies.csv", _reuse_first_enemy_scene),
            [],
        ),
        (
            "enemy scene path is required",
            _mutate_csv("client/data/enemies.csv", _set_enemy_scene_path("")),
            [
                "client/data/enemies.csv:line 2.scene_path",
                "must be a non-empty actor scene path",
            ],
        ),
        (
            "enemy scene must use a TSCN resource",
            _mutate_csv(
                "client/data/enemies.csv",
                _set_enemy_scene_path(
                    "res://scenes/gameplay/actors/enemies/enemy_chaser.tres"
                ),
            ),
            [
                "client/data/enemies.csv:line 2.scene_path",
                "must be a project actor .tscn under res://scenes/gameplay/actors/enemies/",
            ],
        ),
        (
            "enemy scene must exist",
            _mutate_csv(
                "client/data/enemies.csv",
                _set_enemy_scene_path(
                    "res://scenes/gameplay/actors/enemies/enemy_missing.tscn"
                ),
            ),
            [
                "client/data/enemies.csv:line 2.scene_path",
                "actor scene does not exist",
            ],
        ),
        (
            "enemy pool ids must be unique",
            _mutate_csv("client/data/enemies.csv", _duplicate_enemy_pool_id),
            [
                "client/data/enemies.csv:line 3.pool_id",
                "duplicate enemy pool id enemy_chaser",
            ],
        ),
        (
            "removed enemy_ranged pool id stays rejected",
            _mutate_csv("client/data/enemies.csv", _set_enemy_pool_id("enemy_ranged")),
            [
                "client/data/enemies.csv:line 2.pool_id",
                "unknown id enemy_ranged; expected one of pool_ids",
            ],
        ),
        (
            "enemy pool prewarm must be non-negative",
            _mutate_csv("client/data/enemies.csv", _set_enemy_pool_prewarm("-1")),
            [
                "client/data/enemies.csv:line 2.pool_prewarm",
                "must be >= 0",
            ],
        ),
        (
            "legacy enemy visual color column stays rejected",
            _add_enemy_legacy_visual_color_column,
            [
                "client/data/enemies.csv:header",
                "unexpected columns ['visual_color']",
            ],
        ),
        (
            "legacy enemy contact columns stay rejected",
            _add_enemy_legacy_contact_columns,
            [
                "client/data/enemies.csv:header",
                "contact_damage",
                "contact_interval",
                "element_id",
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
            "enemy AI schema v5 is required",
            _mutate_json("client/data/enemy_ai_profiles.json", _set_schema_version(4)),
            [
                "client/data/enemy_ai_profiles.json:schema_version",
                "must be >= 5",
            ],
        ),
        (
            "ranged burst count is required",
            _mutate_json(
                "client/data/enemy_ai_profiles.json",
                _remove_profile_attack_value(4, 0, "burst_count"),
            ),
            [
                "client/data/enemy_ai_profiles.json:profiles[4].actions[0].attack.burst_count",
                "is required",
            ],
        ),
        (
            "ranged burst count must be positive",
            _mutate_json(
                "client/data/enemy_ai_profiles.json",
                _set_profile_attack_value(4, 0, "burst_count", 0),
            ),
            [
                "client/data/enemy_ai_profiles.json:profiles[4].actions[0].attack.burst_count",
                "must be >= 1",
            ],
        ),
        (
            "ranged windup must be positive",
            _mutate_json(
                "client/data/enemy_ai_profiles.json",
                _set_profile_attack_value(4, 0, "windup", 0.0),
            ),
            [
                "client/data/enemy_ai_profiles.json:profiles[4].actions[0].attack.windup",
                "must be > 0",
            ],
        ),
        (
            "ranged shot interval must be positive",
            _mutate_json(
                "client/data/enemy_ai_profiles.json",
                _set_profile_attack_value(4, 0, "shot_interval", 0.0),
            ),
            [
                "client/data/enemy_ai_profiles.json:profiles[4].actions[0].attack.shot_interval",
                "must be > 0",
            ],
        ),
        (
            "ranged attack rejects surplus fields",
            _mutate_json(
                "client/data/enemy_ai_profiles.json",
                _set_profile_attack_value(4, 0, "magazine_size", 4),
            ),
            [
                "client/data/enemy_ai_profiles.json:profiles[4].actions[0].attack.magazine_size",
                "is not allowed",
            ],
        ),
        (
            "attack action requires attack payload",
            _mutate_json("client/data/enemy_ai_profiles.json", _remove_enemy_ai_attack),
            [
                "client/data/enemy_ai_profiles.json:profiles[0].actions[0].attack",
                "must be an object",
            ],
        ),
        (
            "non attack action rejects attack payload",
            _mutate_json("client/data/enemy_ai_profiles.json", _add_attack_to_non_attack_action),
            [
                "client/data/enemy_ai_profiles.json:profiles[0].actions[1].attack",
                "forbidden for non-attack actions",
            ],
        ),
        (
            "legacy movement attack parameters stay rejected",
            _mutate_json("client/data/enemy_ai_profiles.json", _add_enemy_ai_legacy_charge_range),
            [
                "client/data/enemy_ai_profiles.json:profiles[0].movement.charge_range",
                "was removed from movement in schema v4",
            ],
        ),
        (
            "exploder damage must be positive",
            _mutate_json("client/data/enemy_ai_profiles.json", _set_enemy_ai_attack_value(0, "damage", 0.0)),
            [
                "client/data/enemy_ai_profiles.json:profiles[0].actions[0].attack.damage",
                "must be > 0",
            ],
        ),
        (
            "exploder radius must be positive",
            _mutate_json("client/data/enemy_ai_profiles.json", _set_enemy_ai_attack_value(0, "radius", -1.0)),
            [
                "client/data/enemy_ai_profiles.json:profiles[0].actions[0].attack.radius",
                "must be > 0",
            ],
        ),
        (
            "melee angle must stay within 360 degrees",
            _mutate_json("client/data/enemy_ai_profiles.json", _set_profile_attack_value(1, 0, "arc_degrees", 361.0)),
            [
                "client/data/enemy_ai_profiles.json:profiles[1].actions[0].attack.arc_degrees",
                "must be <= 360",
            ],
        ),
        (
            "attack element must be registered",
            _mutate_json("client/data/enemy_ai_profiles.json", _set_enemy_ai_attack_value(0, "element_id", "element_missing")),
            [
                "client/data/enemy_ai_profiles.json:profiles[0].actions[0].attack.element_id",
                "unknown id element_missing; expected one of elements",
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
            "gear mod schema v4 is required",
            _mutate_json("client/data/gear_mods.json", _set_gear_mod_schema_version(3)),
            [
                "client/data/gear_mods.json:schema_version",
                "must equal 4",
            ],
        ),
        (
            "gear mod pickup requires exact fields",
            _mutate_json("client/data/gear_mods.json", _remove_gear_mod_pickup_field("spawn_spread")),
            [
                "client/data/gear_mods.json:pickup",
                "must define exactly pool_id, interaction_radius, spawn_vertical_offset, and spawn_spread",
            ],
        ),
        (
            "gear mod pickup uses the dedicated pool",
            _mutate_json("client/data/gear_mods.json", _set_gear_mod_pickup_field("pool_id", "gold_orb")),
            [
                "client/data/gear_mods.json:pickup.pool_id",
                "must equal gear_mod_pickup",
            ],
        ),
        (
            "gear mod pickup interaction radius must be positive",
            _mutate_json("client/data/gear_mods.json", _set_gear_mod_pickup_field("interaction_radius", 0)),
            [
                "client/data/gear_mods.json:pickup.interaction_radius",
                "must be > 0",
            ],
        ),
        (
            "gear mod pickup spread cannot be negative",
            _mutate_json("client/data/gear_mods.json", _set_gear_mod_pickup_field("spawn_spread", -1)),
            [
                "client/data/gear_mods.json:pickup.spawn_spread",
                "must be >= 0",
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
                "client/data/gear_mods.json:mods[0].modifiers[0].stat",
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
            "gear mod legacy overflow reward is rejected",
            _mutate_json("client/data/gear_mods.json", _add_gear_mod_legacy_overflow_gold),
            [
                "client/data/gear_mods.json:root.overflow_gold",
                "is not allowed",
            ],
        ),
        (
            "gear mod legacy max rank is rejected",
            _mutate_json("client/data/gear_mods.json", _add_gear_mod_legacy_max_rank),
            [
                "client/data/gear_mods.json:mods[0].max_rank",
                "is not allowed",
            ],
        ),
        (
            "gear mod legacy rank modifiers are rejected",
            _mutate_json("client/data/gear_mods.json", _add_gear_mod_legacy_rank_modifiers),
            [
                "client/data/gear_mods.json:mods[0].rank_modifiers",
                "is not allowed",
            ],
        ),
        (
            "gear mod legacy base value is rejected",
            _mutate_json("client/data/gear_mods.json", _add_gear_mod_legacy_base_value),
            [
                "client/data/gear_mods.json:mods[0].modifiers[0].base_value",
                "is not allowed",
            ],
        ),
        (
            "gear mod legacy value per rank is rejected",
            _mutate_json("client/data/gear_mods.json", _add_gear_mod_legacy_value_per_rank),
            [
                "client/data/gear_mods.json:mods[0].modifiers[0].value_per_rank",
                "is not allowed",
            ],
        ),
        (
            "gear mod reward pool ids must be registered",
            _mutate_json("client/data/gear_mods.json", _set_gear_mod_reward_pool_id("world_event_mod_pool_missing")),
            [
                "client/data/gear_mods.json:reward_pools[0].id",
                "unknown id world_event_mod_pool_missing; expected one of world_event_mod_pool_ids",
            ],
        ),
        (
            "locked content must reference an unlock rule",
            _mutate_json(
                "client/data/gear_mods.json",
                _lock_first_gear_mod_without_rule,
            ),
            [
                "client/data/content_unlock_rules.json:gear_mod.gear_mod_weapon_damage_test.unlock_rule_id",
                "locked content must reference an unlock rule",
            ],
        ),
        (
            "blank enemy default unlock cell stays open",
            _mutate_csv(
                "client/data/enemies.csv",
                _set_first_enemy_default_unlocked(""),
            ),
            [],
        ),
        (
            "default content must not reference unlock rules",
            _mutate_json(
                "client/data/gear_mods.json",
                _set_first_gear_mod_unlock_rule("missing_rule"),
            ),
            [
                "client/data/content_unlock_rules.json:gear_mod.gear_mod_weapon_damage_test.unlock_rule_id",
                "default-unlocked content must not reference an unlock rule",
            ],
        ),
        (
            "unused unlock rules are rejected",
            _mutate_json(
                "client/data/content_unlock_rules.json",
                _add_unused_content_unlock_rule,
            ),
            [
                "client/data/content_unlock_rules.json:rules.unused_rule",
                "unlock rule is not referenced by content",
            ],
        ),
        (
            "skills cannot define independent locked state",
            _mutate_json(
                "client/data/skills.json",
                _lock_first_skill,
            ),
            [
                "client/data/skills.json:skills[0].default_unlocked",
                "skills inherit their character unlock",
            ],
        ),
        (
            "skills may omit inherited default unlock state",
            _mutate_json(
                "client/data/skills.json",
                _remove_first_skill_default_unlocked,
            ),
            [],
        ),
        (
            "codex icon paths must exist",
            _mutate_json(
                "client/data/gear_mods.json",
                _set_first_gear_mod_codex_icon("res://assets/missing_codex_icon.svg"),
            ),
            [
                "client/data/gear_mods.json:mods[0].codex_icon_path",
                "resource does not exist",
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
            "hazard element must be registered",
            _mutate_csv("client/data/hazards.csv", _set_hazard_element("element_missing")),
            [
                "client/data/hazards.csv:line 2.element_id",
                "unknown id element_missing; expected one of elements",
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
            "warzone director schema v3 is required",
            _mutate_json("client/data/warzone_directors.json", _set_schema_version(2)),
            [
                "client/data/warzone_directors.json:schema_version",
                "must be >= 3",
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
            "warzone legacy resource rewards were removed",
            _mutate_json("client/data/warzone_directors.json", _add_warzone_legacy_resource_rewards),
            [
                "client/data/warzone_directors.json:directors[0].interest_points[0].resource_rewards",
                "field was removed in schema v3",
            ],
        ),
        (
            "warzone mod cache pool must be registered",
            _mutate_json("client/data/warzone_directors.json", _set_warzone_gear_mod_pool("world_event_mod_pool_missing")),
            [
                "client/data/warzone_directors.json:directors[0].interest_points[1].gear_mod_pool_id",
                "unknown id world_event_mod_pool_missing; expected one of world_event_mod_pool_ids",
            ],
        ),
        (
            "warzone mod cache rolls must be positive",
            _mutate_json("client/data/warzone_directors.json", _set_warzone_gear_mod_rolls(0)),
            [
                "client/data/warzone_directors.json:directors[0].interest_points[1].gear_mod_rolls",
                "must be >= 1",
            ],
        ),
        (
            "warzone gold reward must be positive",
            _mutate_json("client/data/warzone_directors.json", _set_warzone_gold_reward(0)),
            [
                "client/data/warzone_directors.json:directors[0].interest_points[0].gold_reward_amount",
                "must be >= 1",
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
            "warzone legacy extraction metadata was removed",
            _mutate_json("client/data/warzone_directors.json", _add_warzone_legacy_extraction_radius),
            [
                "client/data/warzone_directors.json:directors[0].interest_points[3].extraction_radius",
                "field was removed in schema v3",
            ],
        ),
        (
            "warzone completion point cannot grant rewards",
            _mutate_json("client/data/warzone_directors.json", _add_warzone_completion_reward),
            [
                "client/data/warzone_directors.json:directors[0].interest_points[3]",
                "run completion point must not define a reward payload",
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
            "skill description placeholders must resolve from config",
            _mutate_locale_description_placeholder(
                "skill_deploy_projectile_barrier_desc",
                "{effect_1_missing}",
            ),
            [
                "client/data/skills.json:skills[0].desc_key",
                "unsupported config description placeholders",
                "{effect_1_missing}",
            ],
        ),
        (
            "passive description placeholders must resolve from config",
            _mutate_locale_description_placeholder(
                "passive_primary_a_guard_desc",
                "{param_missing}",
            ),
            [
                "client/data/hero_passives.json:passives[0].desc_key",
                "unsupported config description placeholders",
                "{param_missing}",
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
            "skill apply status element must be registered",
            _mutate_json("client/data/skills.json", _set_skill_apply_status_param("element_id", "element_missing")),
            [
                "client/data/skills.json:skills[0].effects[0].params.element_id",
                "unknown id element_missing; expected one of elements",
            ],
        ),
        (
            "skill apply status dot requires element",
            _mutate_json("client/data/skills.json", _set_skill_apply_status_dot_without_element),
            [
                "client/data/skills.json:skills[0].effects[0].params.element_id",
                "is required when magnitude and tick_interval are positive",
            ],
        ),
        (
            "skill damage element must be registered",
            _mutate_json("client/data/skills.json", _set_skill_damage_element("element_missing")),
            [
                "client/data/skills.json:skills[0].effects[0].params.element_id",
                "unknown id element_missing; expected one of elements",
            ],
        ),
        (
            "skill weapon modifier duration must be positive",
            _mutate_json("client/data/skills.json", _set_skill_weapon_modifier_duration(0.0)),
            [
                "client/data/skills.json:skills[2].effects[0].params.duration",
                "must be > 0",
            ],
        ),
        (
            "skill weapon modifier stat must be registered",
            _mutate_json("client/data/skills.json", _set_skill_weapon_modifier_stat("stat_missing")),
            [
                "client/data/skills.json:skills[2].effects[0].params.modifiers[0].stat",
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
            "camera aim look profile must be present",
            _mutate_json("client/data/camera_feedback.json", _remove_camera_aim_look),
            [
                "client/data/camera_feedback.json:aim_look",
                "must be an object",
            ],
        ),
        (
            "camera pointer offset ratio must be positive",
            _mutate_json(
                "client/data/camera_feedback.json",
                _set_camera_aim_look_value("pointer_offset_ratio", 0.0),
            ),
            [
                "client/data/camera_feedback.json:aim_look.pointer_offset_ratio",
                "must be > 0.0",
            ],
        ),
        (
            "camera pointer offset ratio cannot exceed one",
            _mutate_json(
                "client/data/camera_feedback.json",
                _set_camera_aim_look_value("pointer_offset_ratio", 1.1),
            ),
            [
                "client/data/camera_feedback.json:aim_look.pointer_offset_ratio",
                "must be <= 1.0",
            ],
        ),
        (
            "camera aim look maximum offset must be non-negative",
            _mutate_json(
                "client/data/camera_feedback.json",
                _set_camera_aim_look_value("max_offset_px", -1.0),
            ),
            [
                "client/data/camera_feedback.json:aim_look.max_offset_px",
                "must be >= 0.0",
            ],
        ),
        (
            "camera pointer dead zone must be non-negative",
            _mutate_json(
                "client/data/camera_feedback.json",
                _set_camera_aim_look_value("pointer_dead_zone_px", -1.0),
            ),
            [
                "client/data/camera_feedback.json:aim_look.pointer_dead_zone_px",
                "must be >= 0.0",
            ],
        ),
        (
            "camera aim look smoothing time must be positive",
            _mutate_json(
                "client/data/camera_feedback.json",
                _set_camera_aim_look_value("smoothing_time_seconds", 0.0),
            ),
            [
                "client/data/camera_feedback.json:aim_look.smoothing_time_seconds",
                "must be > 0.0",
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
        (
            "weapon recoil shake exponent must be non-negative",
            _mutate_json(
                "client/data/camera_feedback.json",
                _set_camera_feedback_profile_value(
                    "weapon_recoil_shake",
                    "amplitude_exponent",
                    -0.1,
                ),
            ),
            [
                "client/data/camera_feedback.json:weapon_recoil_shake.amplitude_exponent",
                "must be >= 0.0",
            ],
        ),
        (
            "presentation camera feedback must reference a profile",
            _mutate_json(
                "client/data/presentation_profiles.json",
                _set_weapon_camera_feedback("missing_camera_feedback"),
            ),
            [
                "client/data/presentation_profiles.json:profiles[9].bindings.weapon_fire.camera_feedback_id",
                "must reference a profile in camera_feedback.json",
            ],
        ),
    ]

    failures: list[str] = []
    difficulty_curve_failure = _run_difficulty_curve_cases()
    if difficulty_curve_failure:
        failures.append(difficulty_curve_failure)
    else:
        print("[data-loader-schema-test] difficulty curve boundaries: passed")
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


def _run_difficulty_curve_cases() -> str | None:
    payload = json.loads(DIFFICULTY_PROFILE_PATH.read_text(encoding="utf-8"))
    profiles = payload.get("profiles", [])
    if not profiles or not isinstance(profiles[0], dict):
        return "[data-loader-schema-test] difficulty curve boundaries: missing profile"
    profile = profiles[0]
    interval = float(profile["tier_interval_seconds"])
    continuous_growth = float(profile["continuous_growth_per_interval"])
    tier_step_growth = float(profile["tier_step_growth"])
    damage_growth_ratio = float(profile["damage_growth_ratio"])
    stage_name_keys = profile["stage_name_keys"]
    expected_cases = (
        (0.0, 0, 0.0, 1.0, 1.0, 1, "ui_difficulty_stage_dormant"),
        (
            89.999,
            0,
            89.999 / 90.0,
            1.0399995555555555,
            1.0191997866666666,
            1,
            "ui_difficulty_stage_dormant",
        ),
        (90.0, 1, 0.0, 1.13, 1.0624, 2, "ui_difficulty_stage_alert"),
        (
            719.999,
            7,
            89.999 / 90.0,
            1.9499995555555556,
            1.4559997866666668,
            8,
            "ui_difficulty_stage_collapse",
        ),
        (720.0, 8, 0.0, 2.04, 1.4992, 9, "ui_difficulty_stage_nestfall"),
        (
            1800.0,
            20,
            0.0,
            3.6,
            2.248,
            21,
            "ui_difficulty_stage_nestfall",
        ),
    )
    for (
        elapsed,
        expected_tier,
        expected_progress,
        expected_health,
        expected_damage,
        expected_level,
        expected_name_key,
    ) in expected_cases:
        tier = math.floor(elapsed / interval)
        progress = (elapsed % interval) / interval
        coefficient = (
            1.0
            + continuous_growth * (elapsed / interval)
            + tier_step_growth * tier
        )
        damage_multiplier = 1.0 + damage_growth_ratio * (coefficient - 1.0)
        name_key = stage_name_keys[min(tier, len(stage_name_keys) - 1)]
        actual = (
            tier,
            progress,
            coefficient,
            damage_multiplier,
            tier + 1,
            name_key,
        )
        expected = (
            expected_tier,
            expected_progress,
            expected_health,
            expected_damage,
            expected_level,
            expected_name_key,
        )
        if actual[0] != expected[0] or actual[4:] != expected[4:]:
            return (
                "[data-loader-schema-test] difficulty curve boundaries: "
                f"{elapsed}s expected {expected}, got {actual}"
            )
        for actual_value, expected_value in zip(actual[1:4], expected[1:4]):
            if not math.isclose(
                actual_value,
                expected_value,
                rel_tol=0.0,
                abs_tol=1e-9,
            ):
                return (
                    "[data-loader-schema-test] difficulty curve boundaries: "
                    f"{elapsed}s expected {expected}, got {actual}"
                )
    return None


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
    _copy_tree(
        ROOT / "client" / "scenes" / "gameplay" / "actors",
        temp_root / "client" / "scenes" / "gameplay" / "actors",
    )
    _copy_file(
        ROOT / "client" / "scenes" / "gameplay" / "hit_spark.tscn",
        temp_root / "client" / "scenes" / "gameplay" / "hit_spark.tscn",
    )
    _copy_file(
        ROOT / "client" / "scenes" / "gameplay" / "damage_number.tscn",
        temp_root / "client" / "scenes" / "gameplay" / "damage_number.tscn",
    )
    _copy_tree(
        ROOT / "client" / "scenes" / "vfx",
        temp_root / "client" / "scenes" / "vfx",
    )
    _copy_tree(
        ROOT / "client" / "resources" / "vfx",
        temp_root / "client" / "resources" / "vfx",
    )
    _copy_file(
        ROOT / "client" / "resources" / "modules" / "module_placeholder_tileset.tres",
        temp_root / "client" / "resources" / "modules" / "module_placeholder_tileset.tres",
    )
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


def _make_fallback_template_insufficient(root: Path) -> None:
    module_path = root / "client/data/modules/module_connector_cross.json"
    module_payload = json.loads(module_path.read_text(encoding="utf-8"))
    _leave_five_spawnable_floor_cells(module_payload)
    module_path.write_text(
        json.dumps(module_payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    world_path = root / "client/data/module_worlds.json"
    world_payload = json.loads(world_path.read_text(encoding="utf-8"))
    for entry in world_payload["worlds"][0]["fallback_assignment"]:
        slot = entry.get("slot", {})
        if slot.get("x") == 1 and slot.get("y") == 0:
            entry["template_id"] = "module_connector_cross"
            entry["rotation"] = 0
            break
    world_path.write_text(
        json.dumps(world_payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def _mutate_locale_description_placeholder(
    key: str,
    placeholder: str,
) -> RepoMutator:
    def mutate_repo(root: Path) -> None:
        path = root / "client/locale/strings.csv"
        lines = path.read_text(encoding="utf-8-sig").splitlines()
        for index, line in enumerate(lines):
            if not line.startswith(f"{key},"):
                continue
            lines[index] = f"{key},{placeholder},{placeholder}"
            path.write_text(
                "\n".join(lines) + "\n",
                encoding="utf-8",
                newline="\n",
            )
            return
        raise AssertionError(f"missing locale key {key}")

    return mutate_repo


def _set_character_id(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["characters"][0]["id"] = value

    return mutate


def _remove_character_palette_primary(payload: dict[str, Any]) -> None:
    payload["characters"][0]["palette"].pop("primary", None)


def _set_character_palette_primary(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["characters"][0]["palette"]["primary"] = value

    return mutate


def _add_character_palette_key(key: str, value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["characters"][0]["palette"][key] = value

    return mutate


def _set_camera_feedback_value(field: str, value: object) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["player_damage_shake"][field] = value

    return mutate


def _remove_camera_aim_look(payload: dict[str, Any]) -> None:
    payload.pop("aim_look", None)


def _set_camera_aim_look_value(field: str, value: object) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["aim_look"][field] = value

    return mutate


def _set_camera_feedback_profile_value(
    profile_id: str, field: str, value: object
) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload[profile_id][field] = value

    return mutate


def _set_character_name_key(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["characters"][0]["name_key"] = value

    return mutate


def _remove_character_scene_path(payload: dict[str, Any]) -> None:
    payload["characters"][0].pop("scene_path", None)


def _set_character_scene_path(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["characters"][0]["scene_path"] = value

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


def _set_mode_difficulty_profile(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["modes"][0]["difficulty_profile_id"] = value

    return mutate


def _set_difficulty_profile_field(field: str, value: object) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["profiles"][0][field] = value

    return mutate


def _set_enemy_reward_field(field: str, value: object) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload[field] = value

    return mutate


def _remove_enemy_reward_field(field: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload.pop(field, None)

    return mutate


def _set_enemy_reward_random_interval(
    minimum: float,
    maximum: float,
) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["random_multiplier_min"] = minimum
        payload["random_multiplier_max"] = maximum

    return mutate


def _replace_enemy_reward_header_with_legacy(root: Path) -> None:
    path = root / "client/data/enemies.csv"
    text = path.read_text(encoding="utf-8-sig")
    path.write_text(
        text.replace(
            "gold_value_multiplier",
            "gold_reward",
            1,
        ),
        encoding="utf-8",
        newline="\n",
    )


def _set_enemy_gold_value_multiplier(value: str) -> CsvMutator:
    def mutate(rows: list[dict[str, str]]) -> None:
        rows[0]["gold_value_multiplier"] = value

    return mutate


def _remove_last_difficulty_stage_name(payload: dict[str, Any]) -> None:
    payload["profiles"][0]["stage_name_keys"].pop()


def _set_difficulty_stage_name_key(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["profiles"][0]["stage_name_keys"][0] = value

    return mutate


def _add_legacy_growth_pool(payload: dict[str, Any]) -> None:
    payload["modes"][0]["resource_pools"]["growth_pools"] = [
        {"id": "default_level_up", "weight": 100}
    ]


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


def _add_warzone_legacy_resource_rewards(payload: dict[str, Any]) -> None:
    payload["directors"][0]["interest_points"][0]["resource_rewards"] = [
        {"resource_id": "gear_mod_dust", "amount": 10}
    ]


def _set_warzone_gear_mod_pool(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["directors"][0]["interest_points"][1]["gear_mod_pool_id"] = value

    return mutate


def _set_warzone_gear_mod_rolls(value: int) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["directors"][0]["interest_points"][1]["gear_mod_rolls"] = value

    return mutate


def _set_warzone_gold_reward(value: int) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["directors"][0]["interest_points"][0]["gold_reward_amount"] = value

    return mutate


def _set_warzone_interest_point_requires_interaction(value: Any) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["directors"][0]["interest_points"][0]["requires_interaction"] = value

    return mutate


def _set_warzone_interest_point_target_hp(value: int) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["directors"][0]["interest_points"][0]["target_hp"] = value

    return mutate


def _add_warzone_legacy_extraction_radius(payload: dict[str, Any]) -> None:
    payload["directors"][0]["interest_points"][3]["extraction_radius"] = 220


def _add_warzone_completion_reward(payload: dict[str, Any]) -> None:
    payload["directors"][0]["interest_points"][3]["gold_reward_amount"] = 1


def _set_reward_entry_name_key(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["pools"][0]["entries"][0]["name_key"] = value

    return mutate


def _add_legacy_weapon_ammo(payload: dict[str, Any]) -> None:
    payload["weapons"][0]["ammo"] = {
        "magazine_size": 30,
        "starting_reserve": 150,
        "total_capacity": 240,
        "reload_duration": 1.2,
        "depleted_fire_rate_multiplier": 0.5,
        "depleted_bullet_speed_multiplier": 0.5,
    }


def _set_weapon_element(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["weapons"][0]["projectile"]["element_id"] = value

    return mutate


def _duplicate_reversed_element_combination(payload: dict[str, Any]) -> None:
    first = payload["combinations"][0]
    payload["combinations"].append(
        {
            "left": first["right"],
            "right": first["left"],
            "result": first["result"],
        }
    )


def _set_composite_combination_input(payload: dict[str, Any]) -> None:
    payload["combinations"][0]["left"] = "element_composite_ab"


def _set_weapon_stat(stat: str, value: object) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["weapons"][0]["base_stats"][stat] = value

    return mutate


def _set_weapon_recoil_model_value(field: str, value: object) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["recoil_model"][field] = value

    return mutate


def _set_weapon_camera_feedback(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        for profile in payload["profiles"]:
            if profile.get("id") == "presentation_weapon_default":
                profile["bindings"]["weapon_fire"]["camera_feedback_id"] = value
                return
        raise AssertionError("missing presentation_weapon_default")

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


def _set_character_hero_skill(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["characters"][0]["hero_skill_ids"][0] = value

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


def _set_enemy_element(value: str) -> CsvMutator:
    def mutate(rows: list[dict[str, str]]) -> None:
        rows[0]["element_id"] = value

    return mutate


def _set_enemy_ai_action(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["profiles"][0]["actions"][0]["id"] = value

    return mutate


def _remove_enemy_ai_attack(payload: dict[str, Any]) -> None:
    payload["profiles"][0]["actions"][0].pop("attack", None)


def _add_attack_to_non_attack_action(payload: dict[str, Any]) -> None:
    payload["profiles"][0]["actions"][1]["attack"] = {
        "damage": 1.0,
    }


def _add_enemy_ai_legacy_charge_range(payload: dict[str, Any]) -> None:
    payload["profiles"][0]["movement"]["charge_range"] = 80.0


def _set_enemy_ai_attack_value(action_index: int, key: str, value: Any) -> JsonMutator:
    return _set_profile_attack_value(0, action_index, key, value)


def _set_profile_attack_value(
    profile_index: int,
    action_index: int,
    key: str,
    value: Any,
) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["profiles"][profile_index]["actions"][action_index]["attack"][key] = value

    return mutate


def _remove_profile_attack_value(
    profile_index: int,
    action_index: int,
    key: str,
) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["profiles"][profile_index]["actions"][action_index]["attack"].pop(key, None)

    return mutate


def _set_schema_version(value: int) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["schema_version"] = value

    return mutate


def _remove_player_body(payload: dict[str, Any]) -> None:
    payload.pop("body", None)


def _set_player_body_radius(value: float) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["body"]["radius"] = value

    return mutate


def _set_dash_distance(value: float) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["dash"]["distance"] = value

    return mutate


def _set_energy_drop_pool(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["energy_drop"]["pool_id"] = value

    return mutate


def _add_legacy_pickup_orb_speed(payload: dict[str, Any]) -> None:
    payload["base_stats"]["pickup_orb_speed"] = 360.0


def _set_drop_pickup_speed(drop_field: str, value: float) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload[drop_field]["pickup_speed"] = value

    return mutate


def _set_level_progression_field(field: str, value: int) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload[field] = value

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


def _set_enemy_scene_path(value: str) -> CsvMutator:
    def mutate(rows: list[dict[str, str]]) -> None:
        rows[0]["scene_path"] = value

    return mutate


def _reuse_first_enemy_scene(rows: list[dict[str, str]]) -> None:
    rows[1]["scene_path"] = rows[0]["scene_path"]


def _duplicate_enemy_pool_id(rows: list[dict[str, str]]) -> None:
    rows[1]["pool_id"] = rows[0]["pool_id"]


def _set_enemy_pool_id(value: str) -> CsvMutator:
    def mutate(rows: list[dict[str, str]]) -> None:
        rows[0]["pool_id"] = value

    return mutate


def _set_enemy_pool_prewarm(value: str) -> CsvMutator:
    def mutate(rows: list[dict[str, str]]) -> None:
        rows[0]["pool_prewarm"] = value

    return mutate


def _add_enemy_legacy_visual_color_column(root: Path) -> None:
    path = root / "client/data/enemies.csv"
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)
        fieldnames = list(reader.fieldnames or [])
    fieldnames.append("visual_color")
    for row in rows:
        row["visual_color"] = "#ff6152"
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def _add_enemy_legacy_contact_columns(root: Path) -> None:
    path = root / "client/data/enemies.csv"
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)
        fieldnames = list(reader.fieldnames or [])
    fieldnames.extend(["contact_damage", "contact_interval", "element_id"])
    for row in rows:
        row["contact_damage"] = "100"
        row["contact_interval"] = "0.7"
        row["element_id"] = "element_neutral"
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def _set_mode_enemy(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["modes"][0]["resource_pools"]["enemies"][0]["id"] = value

    return mutate


def _set_gear_mod_id(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["mods"][0]["id"] = value

    return mutate


def _set_gear_mod_schema_version(value: int) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["schema_version"] = value

    return mutate


def _remove_gear_mod_pickup_field(field: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["pickup"].pop(field, None)

    return mutate


def _set_gear_mod_pickup_field(field: str, value: Any) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["pickup"][field] = value

    return mutate


def _set_gear_mod_name_key(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["mods"][0]["name_key"] = value

    return mutate


def _set_gear_mod_modifier_stat(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["mods"][0]["modifiers"][0]["stat"] = value

    return mutate


def _set_gear_mod_drop_enemy(value: str) -> CsvMutator:
    def mutate(rows: list[dict[str, str]]) -> None:
        rows[0]["source_enemy_id"] = value

    return mutate


def _set_gear_mod_drop_chance(value: str) -> CsvMutator:
    def mutate(rows: list[dict[str, str]]) -> None:
        rows[0]["drop_chance"] = value

    return mutate


def _add_gear_mod_legacy_overflow_gold(payload: dict[str, Any]) -> None:
    payload["overflow_gold"] = 75


def _add_gear_mod_legacy_max_rank(payload: dict[str, Any]) -> None:
    payload["mods"][0]["max_rank"] = 5


def _add_gear_mod_legacy_rank_modifiers(payload: dict[str, Any]) -> None:
    payload["mods"][0]["rank_modifiers"] = [
        {
            "stat": "damage",
            "type": "mult",
            "base_value": 1.1,
            "value_per_rank": 0.05,
        }
    ]


def _add_gear_mod_legacy_base_value(payload: dict[str, Any]) -> None:
    payload["mods"][0]["modifiers"][0]["base_value"] = 1.1


def _add_gear_mod_legacy_value_per_rank(payload: dict[str, Any]) -> None:
    payload["mods"][0]["modifiers"][0]["value_per_rank"] = 0.05


def _set_gear_mod_reward_pool_id(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["reward_pools"][0]["id"] = value

    return mutate


def _lock_first_gear_mod_without_rule(payload: dict[str, Any]) -> None:
    payload["mods"][0]["default_unlocked"] = False
    payload["mods"][0].pop("unlock_rule_id", None)


def _set_first_gear_mod_unlock_rule(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["mods"][0]["unlock_rule_id"] = value

    return mutate


def _add_unused_content_unlock_rule(payload: dict[str, Any]) -> None:
    payload["rules"].append(
        {
            "id": "unused_rule",
            "mode": "all",
            "conditions": [
                {
                    "counter_id": "runs_completed",
                    "target": 1,
                }
            ],
        }
    )


def _lock_first_skill(payload: dict[str, Any]) -> None:
    payload["skills"][0]["default_unlocked"] = False


def _remove_first_skill_default_unlocked(payload: dict[str, Any]) -> None:
    payload["skills"][0].pop("default_unlocked", None)


def _set_first_enemy_default_unlocked(value: str) -> CsvMutator:
    def mutate(rows: list[dict[str, str]]) -> None:
        rows[0]["default_unlocked"] = value

    return mutate


def _set_first_gear_mod_codex_icon(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["mods"][0]["codex_icon_path"] = value

    return mutate


def _set_hazard_tags(value: str) -> CsvMutator:
    def mutate(rows: list[dict[str, str]]) -> None:
        rows[0]["tags"] = value

    return mutate


def _set_hazard_element(value: str) -> CsvMutator:
    def mutate(rows: list[dict[str, str]]) -> None:
        rows[0]["element_id"] = value

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


def _set_skill_apply_status_dot_without_element(payload: dict[str, Any]) -> None:
    payload["skills"][0]["effects"][0] = _apply_status_effect_payload()
    params = payload["skills"][0]["effects"][0]["params"]
    params["status"] = "poison"
    params["magnitude"] = 2.0
    params["tick_interval"] = 0.5
    params.pop("element_id", None)


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


def _set_skill_damage_element(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["skills"][0]["effects"][0] = {
            "effect": "skill_effect_damage",
            "params": {
                "amount": 8.0,
                "element_id": "element_neutral",
            },
        }
        payload["skills"][0]["effects"][0]["params"]["element_id"] = value

    return mutate


def _set_skill_weapon_modifier_duration(value: float) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["skills"][2]["effects"][0]["params"]["duration"] = value

    return mutate


def _set_skill_weapon_modifier_stat(value: str) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["skills"][2]["effects"][0]["params"]["modifiers"][0]["stat"] = value

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


def _set_first_visit_enemy_unknown(payload: dict[str, Any]) -> None:
    payload["worlds"][0]["first_visit_enemy_spawn"]["enemy_pool"][0][
        "enemy_id"
    ] = "enemy_unknown"


def _set_first_visit_unlock_negative(payload: dict[str, Any]) -> None:
    payload["worlds"][0]["first_visit_enemy_spawn"]["enemy_pool"][0][
        "unlock_time"
    ] = -1.0


def _set_first_visit_weight_zero(payload: dict[str, Any]) -> None:
    payload["worlds"][0]["first_visit_enemy_spawn"]["enemy_pool"][0][
        "weight"
    ] = 0.0


def _set_module_world_cell_size(value: float) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["worlds"][0]["cell_size"] = value

    return mutate


def _remove_defense_target_hit_radius(payload: dict[str, Any]) -> None:
    payload["events"][0].pop("target_hit_radius", None)


def _add_world_event_surplus_field(payload: dict[str, Any]) -> None:
    payload["events"][1]["surplus"] = True


def _set_gold_shrine_chance_one(payload: dict[str, Any]) -> None:
    payload["events"][3]["success_chance"] = 1.0


def _set_defense_wave_after_duration(payload: dict[str, Any]) -> None:
    payload["events"][0]["waves"][2]["trigger"] = 46.0


def _set_limited_group_pick_too_high(payload: dict[str, Any]) -> None:
    payload["worlds"][0]["limited_template_groups"][0]["pick_distinct"] = 6


def _set_limited_group_flat_template(payload: dict[str, Any]) -> None:
    payload["worlds"][0]["limited_template_groups"][0]["entries"][0][
        "template_id"
    ] = "module_flat_ground"


def _remove_fixed_start_slot(payload: dict[str, Any]) -> None:
    world = payload["worlds"][0]
    start_slot = world["start_slot"]
    world["fixed_slots"] = [
        entry for entry in world["fixed_slots"] if entry["slot"] != start_slot
    ]


def _duplicate_visual_effect_id(payload: dict[str, Any]) -> None:
    payload["effects"][1]["id"] = payload["effects"][0]["id"]


def _remove_high_frequency_visual_effect_pool(payload: dict[str, Any]) -> None:
    payload["effects"][0].pop("pool_id", None)


def _add_legacy_quality_variants(payload: dict[str, Any]) -> None:
    payload["effects"][0]["quality_variants"] = {}


def _add_legacy_reduced_motion(payload: dict[str, Any]) -> None:
    payload["effects"][0]["reduced_motion"] = {"mode": "same"}


def _create_presentation_profile_cycle(payload: dict[str, Any]) -> None:
    payload["profiles"][0]["parent_profile_id"] = "presentation_player_default"


def _replace_objective_spawn_with_connector(payload: dict[str, Any]) -> None:
    payload["worlds"][0]["objective_spawn"]["template_id"] = "module_connector_cross"


def _add_duplicate_fixed_start_role(payload: dict[str, Any]) -> None:
    payload["worlds"][0]["fixed_slots"].append(
        {"slot": {"x": 1, "y": 1}, "template_id": "module_start_cross", "rotation": 0}
    )


def _remove_objective_candidate(payload: dict[str, Any]) -> None:
    payload["worlds"][0]["objective_spawn"]["candidate_slots"].pop()


def _duplicate_objective_candidate(payload: dict[str, Any]) -> None:
    candidates = payload["worlds"][0]["objective_spawn"]["candidate_slots"]
    candidates[1] = dict(candidates[0])


def _move_objective_candidate_out_of_bounds(payload: dict[str, Any]) -> None:
    payload["worlds"][0]["objective_spawn"]["candidate_slots"][2]["x"] = 7


def _move_objective_candidate_inside_bounds(payload: dict[str, Any]) -> None:
    payload["worlds"][0]["objective_spawn"]["candidate_slots"][2] = {"x": 0, "y": 1}


def _set_optional_exploration_max(value: int) -> JsonMutator:
    def mutate(payload: dict[str, Any]) -> None:
        payload["worlds"][0]["route_budget"]["optional_exploration_modules"]["max"] = value

    return mutate


def _remove_module_terrain_row(payload: dict[str, Any]) -> None:
    payload["terrain_rows"].pop()


def _upgrade_module_to_v4(payload: dict[str, Any]) -> None:
    payload["schema_version"] = 4
    payload.pop("edge_sockets", None)
    payload["visual_layers"] = {
        "ground": {
            "default_tile_id": "module_tile_ground_default",
            "overrides": [],
        },
        "obstacles": {
            "default_tile_id": "module_tile_obstacle_default",
            "overrides": [],
        },
        "decoration": {
            "cells": [],
        },
    }


def _upgrade_module_to_v4_keep_sockets(payload: dict[str, Any]) -> None:
    _upgrade_module_to_v4(payload)
    payload["edge_sockets"] = _derived_sockets(payload["terrain_rows"])


def _downgrade_module_to_v3(payload: dict[str, Any]) -> None:
    payload["schema_version"] = 3


def _derived_sockets(terrain_rows: list[list[str]]) -> dict[str, list[int]]:
    floor = "module_cell_floor"
    return {
        "edge_north": [index for index in range(11) if terrain_rows[0][index] == floor],
        "edge_south": [index for index in range(11) if terrain_rows[10][index] == floor],
        "edge_east": [index for index in range(11) if terrain_rows[index][10] == floor],
        "edge_west": [index for index in range(11) if terrain_rows[index][0] == floor],
    }


def _set_v4_unknown_visual_tile(payload: dict[str, Any]) -> None:
    _upgrade_module_to_v4(payload)
    payload["visual_layers"]["ground"]["overrides"] = [
        {
            "cell": {"x": 0, "y": 0},
            "tile_id": "module_tile_unknown",
            "rotation": 0,
            "flip_h": False,
            "flip_v": False,
        }
    ]


def _set_v4_wrong_layer_tile(payload: dict[str, Any]) -> None:
    _upgrade_module_to_v4(payload)
    payload["visual_layers"]["ground"]["default_tile_id"] = "module_tile_decoration_default"


def _set_v4_invalid_visual_rotation(payload: dict[str, Any]) -> None:
    _upgrade_module_to_v4(payload)
    payload["visual_layers"]["decoration"]["cells"] = [
        {
            "cell": {"x": 5, "y": 5},
            "tile_id": "module_tile_decoration_default",
            "rotation": 45,
            "flip_h": True,
            "flip_v": False,
        }
    ]


def _set_v4_decoration_default_tile(payload: dict[str, Any]) -> None:
    _upgrade_module_to_v4(payload)
    payload["visual_layers"]["decoration"]["default_tile_id"] = "module_tile_decoration_default"


def _set_unknown_module_tile_catalog_id(payload: dict[str, Any]) -> None:
    payload["tiles"][0]["id"] = "module_tile_unknown"


def _make_first_pool_template_candidate(payload: dict[str, Any]) -> None:
    for template in payload["templates"]:
        if template["id"] == "module_flat_ground":
            template["review_status"] = "module_review_candidate"
            template.pop("approved_gameplay_hash", None)
            return


def _remove_first_approved_gameplay_hash(payload: dict[str, Any]) -> None:
    payload["templates"][0].pop("approved_gameplay_hash", None)


def _make_sealed_template_keep_approved_hash(payload: dict[str, Any]) -> None:
    payload["templates"][-1]["approved_gameplay_hash"] = "0" * 64


def _remove_fallback_assignment(payload: dict[str, Any]) -> None:
    payload["worlds"][0]["fallback_assignment"].pop()


def _duplicate_fallback_slot(payload: dict[str, Any]) -> None:
    assignment = payload["worlds"][0]["fallback_assignment"]
    assignment[1]["slot"] = dict(assignment[0]["slot"])


def _close_module_east_socket(payload: dict[str, Any]) -> None:
    for row in payload["terrain_rows"]:
        row[10] = "module_cell_blocked"


def _set_unknown_module_token(payload: dict[str, Any]) -> None:
    payload["terrain_rows"][0][0] = "module_cell_unknown"


def _set_unknown_module_placement(payload: dict[str, Any]) -> None:
    payload["placements"][0]["type"] = "module_place_unknown"


def _set_module_placement_out_of_bounds(payload: dict[str, Any]) -> None:
    payload["placements"][0]["cell"]["x"] = 11


def _set_module_reward_gold_zero(payload: dict[str, Any]) -> None:
    payload["placements"][0]["gold_reward_amount"] = 0


def _add_legacy_module_resource_rewards(payload: dict[str, Any]) -> None:
    payload["placements"][0]["resource_rewards"] = [
        {"id": "gear_mod_dust", "amount": 1}
    ]


def _set_unknown_world_event_placement_id(payload: dict[str, Any]) -> None:
    payload["placements"][0]["world_event_id"] = "world_event_unknown"


def _add_world_event_placement_surplus_field(payload: dict[str, Any]) -> None:
    payload["placements"][0]["surplus"] = True


def _add_legacy_module_enemy_spawn(payload: dict[str, Any]) -> None:
    payload["placements"].append(
        {
            "type": "module_place_enemy_spawn",
            "cell": {"x": 5, "y": 5},
            "enemy_id": "enemy_chaser",
            "count": 1,
        }
    )


def _leave_five_spawnable_floor_cells(payload: dict[str, Any]) -> None:
    payload["terrain_rows"] = [
        ["module_cell_blocked" for _x in range(11)] for _y in range(11)
    ]
    for x in range(3, 8):
        payload["terrain_rows"][5][x] = "module_cell_floor"


def _close_all_module_sockets(payload: dict[str, Any]) -> None:
    for index in range(11):
        payload["terrain_rows"][0][index] = "module_cell_blocked"
        payload["terrain_rows"][10][index] = "module_cell_blocked"
        payload["terrain_rows"][index][0] = "module_cell_blocked"
        payload["terrain_rows"][index][10] = "module_cell_blocked"


def _format_failure(name: str, output: str, reason: str) -> str:
    return f"[data-loader-schema-test] {name}: failed; {reason}\n{output.rstrip()}"


if __name__ == "__main__":
    sys.exit(main())
