# Doc: docs/代码/run_snapshot_coordinator.md
# Authority: docs/代码/gameplay_runtime.md, docs/代码/save_manager.md
class_name RunSnapshotCoordinator
extends RefCounted

## Owns the stable Run v20 payload assembly and restore order. GameplayRunLoop
## retains lifecycle, scene ownership, and the leaf operations supplied as ports.


const RUN_SNAPSHOT_SCHEMA_VERSION: int = 20


class CaptureState:
	extends RefCounted

	var mode: String = ""
	var character: String = ""
	var hero_composition: Dictionary = {}
	var gold_progression: Dictionary = {}
	var kills: int = 0
	var next_enemy_spawn_serial: int = 1
	var game_clock: Dictionary = {}
	var difficulty: Dictionary = {}
	var rng: Dictionary = {}
	var map: Dictionary = {}
	var interest_points: Dictionary = {}
	var gear_mods: Dictionary = {}
	var content_availability: Dictionary = {}
	var content_progress_delta: Dictionary = {}
	var spawn_states: Dictionary = {}
	var player: Dictionary = {}
	var weapon: Dictionary = {}
	var skills: Dictionary = {}
	var effects: Dictionary = {}
	var hazards: Array = []
	var enemies: Array = []
	var bullets: Array = []
	var gold_orbs: Array = []
	var energy_orbs: Array = []
	var gear_mod_pickups: Array = []
	var module_world: Dictionary = {}
	var world_events: Dictionary = {}
	var reward_choice: Dictionary = {}
	var ui_restore: Dictionary = {}


class RestoreBindings:
	extends RefCounted

	var normalize_persisted_numbers: Callable = Callable()
	var validate_gear_mod_pickups: Callable = Callable()
	var restore_difficulty: Callable = Callable()
	var restore_module_world: Callable = Callable()
	var restore_gold_progression: Callable = Callable()
	var restore_reward_choice: Callable = Callable()
	var restore_scalar_state: Callable = Callable()
	var restore_rng: Callable = Callable()
	var restore_map_and_bounds: Callable = Callable()
	var restore_player: Callable = Callable()
	var restore_weapon: Callable = Callable()
	var restore_gear_mods: Callable = Callable()
	var apply_gear_modifiers: Callable = Callable()
	var restore_skills: Callable = Callable()
	var restore_effect_runtime: Callable = Callable()
	var restore_hazards_and_interest: Callable = Callable()
	var restore_entity_batches: Callable = Callable()
	var restore_game_clock: Callable = Callable()
	var refresh_hud: Callable = Callable()


func capture(state: CaptureState) -> Dictionary:
	return {
		"schema_version": RUN_SNAPSHOT_SCHEMA_VERSION,
		"mode": state.mode,
		"character": state.character,
		"hero_composition": state.hero_composition.duplicate(true),
		"gold_progression": state.gold_progression.duplicate(true),
		"kills": state.kills,
		"next_enemy_spawn_serial": state.next_enemy_spawn_serial,
		"game_clock": state.game_clock.duplicate(true),
		"difficulty": state.difficulty.duplicate(true),
		"rng": state.rng.duplicate(true),
		"map": state.map.duplicate(true),
		"interest_points": state.interest_points.duplicate(true),
		"gear_mods": state.gear_mods.duplicate(true),
		"content_availability": state.content_availability.duplicate(true),
		"content_progress_delta": state.content_progress_delta.duplicate(true),
		"spawn_states": state.spawn_states.duplicate(true),
		"player": state.player.duplicate(true),
		"weapon": state.weapon.duplicate(true),
		"skills": state.skills.duplicate(true),
		"effects": state.effects.duplicate(true),
		"hazards": state.hazards.duplicate(true),
		"enemies": state.enemies.duplicate(true),
		"bullets": state.bullets.duplicate(true),
		"gold_orbs": state.gold_orbs.duplicate(true),
		"energy_orbs": state.energy_orbs.duplicate(true),
		"gear_mod_pickups": state.gear_mod_pickups.duplicate(true),
		"module_world": state.module_world.duplicate(true),
		"world_events": state.world_events.duplicate(true),
		"reward_choice": state.reward_choice.duplicate(true),
		"ui_restore": state.ui_restore.duplicate(true),
	}


func restore(
	snapshot_data: Dictionary,
	bindings: RestoreBindings,
	staged_loading: bool = false
) -> bool:
	if (
		int(snapshot_data.get("schema_version", -1))
		!= RUN_SNAPSHOT_SCHEMA_VERSION
	):
		push_error("[GameplayRunLoop] unsupported run snapshot schema")
		return false
	if not bool(bindings.normalize_persisted_numbers.call(snapshot_data)):
		push_error(
			"[GameplayRunLoop] Gear Mod snapshot numeric fields are invalid"
		)
		return false
	if (
		not snapshot_data.get("content_availability", {}) is Dictionary
		or not snapshot_data.get("content_progress_delta", {}) is Dictionary
	):
		push_error("[GameplayRunLoop] run snapshot content progression is invalid")
		return false
	if not bool(bindings.validate_gear_mod_pickups.call(snapshot_data)):
		push_error("[GameplayRunLoop] Gear Mod pickup snapshot is invalid")
		return false
	if not bool(bindings.restore_difficulty.call(snapshot_data)):
		push_error("[GameplayRunLoop] difficulty snapshot restore failed")
		return false
	if not bool(await bindings.restore_module_world.call(
		snapshot_data,
		staged_loading
	)):
		return false
	if not bool(bindings.restore_gold_progression.call(snapshot_data)):
		push_error("[GameplayRunLoop] gold progression restore failed")
		return false
	if not bool(bindings.restore_reward_choice.call(snapshot_data)):
		push_error("[GameplayRunLoop] reward choice restore failed")
		return false
	bindings.restore_scalar_state.call(snapshot_data)
	bindings.restore_rng.call(snapshot_data)
	bindings.restore_map_and_bounds.call(snapshot_data)
	bindings.restore_player.call(snapshot_data)
	bindings.restore_weapon.call(snapshot_data)
	if not bool(bindings.restore_gear_mods.call(snapshot_data)):
		push_error("[GameplayRunLoop] Gear Mod snapshot restore failed")
		return false
	bindings.apply_gear_modifiers.call()
	bindings.restore_skills.call(snapshot_data)
	if not bool(bindings.restore_effect_runtime.call(snapshot_data)):
		push_error("[GameplayRunLoop] effect runtime snapshot restore failed")
		return false
	if not bool(await bindings.restore_hazards_and_interest.call(
		snapshot_data,
		staged_loading
	)):
		return false
	if not bool(await bindings.restore_entity_batches.call(
		snapshot_data,
		staged_loading
	)):
		return false
	bindings.restore_game_clock.call(snapshot_data)
	bindings.refresh_hud.call()
	return true
