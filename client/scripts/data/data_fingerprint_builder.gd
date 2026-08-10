# Doc: docs/代码/data_loader.md
# Authority: docs/决策记录.md ADR #196
class_name DataFingerprintBuilder
extends RefCounted
## Builds normalized gameplay payloads used by deterministic data fingerprints.


static func gear_mod_gameplay_payload(
	raw_data: Variant,
	drop_rows: Array[Dictionary]
) -> Dictionary:
	if not raw_data is Dictionary:
		return {}
	var data: Dictionary = raw_data as Dictionary
	var normalized_board: Dictionary = {}
	var raw_board: Variant = data.get("board", {})
	if raw_board is Dictionary:
		var board: Dictionary = raw_board as Dictionary
		var normalized_center: Dictionary = {}
		var raw_center: Variant = board.get("center", {})
		if raw_center is Dictionary:
			var center: Dictionary = raw_center as Dictionary
			normalized_center = {
				"x": int(center.get("x", -1)),
				"y": int(center.get("y", -1)),
			}
		var normalized_initial_cells: Array[Dictionary] = []
		var raw_initial_cells: Variant = board.get(
			"initial_unlocked_cells",
			[]
		)
		if raw_initial_cells is Array:
			for raw_cell: Variant in raw_initial_cells as Array:
				if not raw_cell is Dictionary:
					continue
				var cell: Dictionary = raw_cell as Dictionary
				normalized_initial_cells.append({
					"x": int(cell.get("x", -1)),
					"y": int(cell.get("y", -1)),
				})
		normalized_board = {
			"width": int(board.get("width", 0)),
			"height": int(board.get("height", 0)),
			"center": normalized_center,
			"initial_unlocked_cells": normalized_initial_cells,
		}
	var normalized_pickup: Dictionary = {}
	var raw_pickup: Variant = data.get("pickup", {})
	if raw_pickup is Dictionary:
		var pickup: Dictionary = raw_pickup as Dictionary
		normalized_pickup = {
			"pool_id": String(pickup.get("pool_id", "")),
			"interaction_radius": float(
				pickup.get("interaction_radius", 0.0)
			),
			"spawn_vertical_offset": float(
				pickup.get("spawn_vertical_offset", 0.0)
			),
			"spawn_spread": float(pickup.get("spawn_spread", 0.0)),
		}

	# Array order is gameplay-significant for deterministic pool selection. Keep
	# source order while normalizing scalar types and excluding display fields.
	var normalized_reward_pools: Array[Dictionary] = []
	var raw_reward_pools: Variant = data.get("reward_pools", [])
	if raw_reward_pools is Array:
		for raw_pool: Variant in raw_reward_pools as Array:
			if not raw_pool is Dictionary:
				continue
			var pool: Dictionary = raw_pool as Dictionary
			var normalized_mod_ids: Array[String] = []
			var raw_mod_ids: Variant = pool.get("mod_ids", [])
			if raw_mod_ids is Array:
				for raw_mod_id: Variant in raw_mod_ids as Array:
					normalized_mod_ids.append(String(raw_mod_id))
			normalized_reward_pools.append({
				"id": String(pool.get("id", "")),
				"mod_ids": normalized_mod_ids,
			})

	var normalized_mods: Array[Dictionary] = []
	var raw_mods: Variant = data.get("mods", [])
	if raw_mods is Array:
		for raw_mod: Variant in raw_mods as Array:
			if not raw_mod is Dictionary:
				continue
			var mod: Dictionary = raw_mod as Dictionary
			normalized_mods.append({
				"id": String(mod.get("id", "")),
				"default_unlocked": bool(
					mod.get("default_unlocked", true)
				),
				"rarity": String(mod.get("rarity", "")),
				"components": (
					(mod.get("components", []) as Array).duplicate(true)
				),
			})

	var normalized_contributions: Array[Dictionary] = []
	var raw_contributions: Variant = data.get(
		"reward_pool_contributions",
		[]
	)
	if raw_contributions is Array:
		for raw_contribution: Variant in raw_contributions as Array:
			if not raw_contribution is Dictionary:
				continue
			var contribution: Dictionary = raw_contribution as Dictionary
			normalized_contributions.append({
				"pool_id": String(contribution.get("pool_id", "")),
				"mod_ids": (
					(contribution.get("mod_ids", []) as Array).duplicate()
				),
			})

	var normalized_drop_rows: Array[Dictionary] = []
	for row: Dictionary in drop_rows:
		normalized_drop_rows.append({
			"source_enemy_id": String(row.get("source_enemy_id", "")),
			"mod_id": String(row.get("mod_id", "")),
			"drop_chance": float(String(row.get("drop_chance", "0"))),
			"min_enemy_level": int(
				String(row.get("min_enemy_level", "0"))
			),
			"max_enemy_level": int(
				String(row.get("max_enemy_level", "0"))
			),
		})

	return {
		"schema_version": int(data.get("schema_version", 0)),
		"board": normalized_board,
		"pickup": normalized_pickup,
		"reward_pools": normalized_reward_pools,
		"reward_pool_contributions": normalized_contributions,
		"mods": normalized_mods,
		"drop_rows": normalized_drop_rows,
	}


static func effect_gameplay_payload(
	skills: Variant,
	gear_mods: Dictionary
) -> Dictionary:
	return {
		"skills": skills.duplicate(true) if skills is Dictionary else {},
		"gear_mods": gear_mods,
	}
