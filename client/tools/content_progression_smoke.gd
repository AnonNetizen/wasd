extends Node


const CONTENT_UNLOCK_SCRIPT := preload(
	"res://scripts/autoload/content_unlock_system.gd"
)
const SAVE_MANAGER_SCRIPT := preload("res://scripts/autoload/save_manager.gd")

var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _run() -> void:
	_expect_meta_v3_to_v4_migration()
	_expect_default_availability_and_codex_fallbacks()
	_expect_rule_status_and_pending_delta()
	_expect_commit_and_unlock_idempotence()
	_finish()


func _expect_meta_v3_to_v4_migration() -> void:
	var save_manager: Node = SAVE_MANAGER_SCRIPT.new()
	var migrated: Dictionary = save_manager.call(
		"_migrate_meta_v3_to_v4",
		{
			"hero_composition": {
				"main_hero_id": "character_default_a",
				"sub_hero_id": "character_default_b",
			},
			"marker": "preserved",
		}
	) as Dictionary
	var composition: Dictionary = migrated.get("hero_composition", {}) as Dictionary
	var progression: Dictionary = migrated.get("content_progression", {}) as Dictionary
	_expect(
		String(composition.get("main_hero_id", "")) == "character_default_a"
		and String(composition.get("sub_hero_id", "")) == "character_default_b",
		"Meta v3->v4 should preserve the confirmed hero composition"
	)
	_expect(
		String(migrated.get("marker", "")) == "preserved",
		"Meta v3->v4 should preserve unrelated fields"
	)
	_expect(
		progression.get("unlocked", null) is Dictionary
		and progression.get("counters", null) is Dictionary,
		"Meta v3->v4 should add sparse unlocked and counters dictionaries"
	)
	save_manager.free()


func _expect_default_availability_and_codex_fallbacks() -> void:
	var fixture: Dictionary = _fixture_system()
	var system: Node = fixture["system"] as Node
	_expect(
		bool(system.call("is_unlocked", "character", "character_default_a")),
		"missing default_unlocked should default to available"
	)
	_expect(
		bool(system.call("is_unlocked", "character", "character_default_b")),
		"explicit default_unlocked=true should be available"
	)
	_expect(
		bool(system.call("is_unlocked", "enemy", "enemy_default")),
		"an empty CSV default_unlocked cell should default to available"
	)
	_expect(
		not bool(system.call("is_unlocked", "character", "character_locked")),
		"locked content should remain unavailable before its rule completes"
	)
	var snapshot: Dictionary = system.call("build_run_availability_snapshot") as Dictionary
	_expect(
		(snapshot.get("character", []) as Array).size() == 2
		and (snapshot.get("gear_mod", []) as Array).has("gear_mod_default")
		and (snapshot.get("enemy", []) as Array).has("enemy_default"),
		"run availability should include all three default-open content pools"
	)
	var enemy_entries: Array = system.call("codex_entries", "enemy") as Array
	var enemy_default: Dictionary = _entry_by_id(enemy_entries, "enemy_default")
	var character_entries: Array = system.call(
		"codex_entries",
		"character"
	) as Array
	var locked_character: Dictionary = _entry_by_id(
		character_entries,
		"character_locked"
	)
	var character_default: Dictionary = _entry_by_id(
		character_entries,
		"character_default_a"
	)
	var gear_mod_default: Dictionary = _entry_by_id(
		system.call("codex_entries", "gear_mod") as Array,
		"gear_mod_default"
	)
	_expect(
		String(enemy_default.get("desc_key", "")) == "enemy_default_name",
		"enemy Codex entry should fall back to name_key when desc_key is missing"
	)
	_expect(
		String(enemy_default.get("icon_path", "")).is_empty(),
		"enemy Codex entry should safely expose an empty missing icon path"
	)
	_expect(
		(character_default.get("details", {}) as Dictionary).has("base_stats")
		and (character_default.get("details", {}) as Dictionary).has(
			"passive_id"
		)
		and (gear_mod_default.get("details", {}) as Dictionary).has(
			"rank_modifiers"
		)
		and (enemy_default.get("details", {}) as Dictionary).has("max_hp"),
		"unlocked Codex entries should normalize details for all three content types"
	)
	_expect(
		not locked_character.has("name_key")
		and not locked_character.has("desc_key")
		and not locked_character.has("icon_path")
		and not locked_character.has("details"),
		"locked Codex entries should not leak identity or gameplay details"
	)
	system.free()


func _expect_rule_status_and_pending_delta() -> void:
	var fixture: Dictionary = _fixture_system()
	var system: Node = fixture["system"] as Node
	var save_manager: FakeSaveManager = fixture["save_manager"] as FakeSaveManager
	save_manager.meta_payload = {
		"content_progression": {
			"unlocked": {},
			"counters": {
				"runs_completed": 1,
				"enemy_defeated": {"enemy_default": 2},
				"runs_ended": 1,
				"enemy_defeated_total": 9,
			},
		},
	}
	system.set("_meta_payload", save_manager.meta_payload.duplicate(true))
	save_manager.run_payload = {
		"schema_version": 14,
		"content_progress_delta": {
			"runs_completed": 1,
			"enemy_defeated": {"enemy_default": 1},
		},
	}
	var all_status: Dictionary = system.call(
		"requirement_status",
		"character",
		"character_locked"
	) as Dictionary
	var conditions: Array = all_status.get("conditions", []) as Array
	_expect(
		String(all_status.get("mode", "")) == "all"
		and not bool(all_status.get("complete", false)),
		"all rule should remain incomplete using committed Meta only"
	)
	_expect(
		_condition_matches(conditions, "runs_completed", "", 1, 1, 2)
		and _condition_matches(
			conditions,
			"enemy_defeated",
			"enemy_default",
			2,
			1,
			3
		),
		"requirement status should expose committed current and uncommitted pending separately"
	)
	_expect(
		_condition_subject_name(
			conditions,
			"enemy_defeated",
			"enemy_default"
		) == "enemy_default_name",
		"subject requirements should expose the default-open subject name key"
	)
	var any_status: Dictionary = system.call(
		"requirement_status",
		"gear_mod",
		"gear_mod_locked"
	) as Dictionary
	_expect(
		bool(any_status.get("complete", false)),
		"any rule should complete when one committed condition reaches target"
	)
	_expect(
		not bool(system.call("is_unlocked", "gear_mod", "gear_mod_locked")),
		"completed requirements should not unlock content before an explicit commit"
	)
	var pending_preview: Dictionary = system.call(
		"pending_run_preview"
	) as Dictionary
	_expect(
		(pending_preview.get("character", []) as Array).has(
			"character_locked"
		),
		"saved Run progress should preview newly qualified unlocks without committing"
	)
	save_manager.run_payload["schema_version"] = 13
	var legacy_status: Dictionary = system.call(
		"requirement_status",
		"character",
		"character_locked"
	) as Dictionary
	_expect(
		_condition_matches(
			legacy_status.get("conditions", []) as Array,
			"runs_completed",
			"",
			1,
			0,
			2
		),
		"legacy or incompatible Run payloads should not contribute pending progress"
	)
	system.free()


func _expect_commit_and_unlock_idempotence() -> void:
	var fixture: Dictionary = _fixture_system()
	var system: Node = fixture["system"] as Node
	var save_manager: FakeSaveManager = fixture["save_manager"] as FakeSaveManager
	save_manager.meta_payload = {
		"hero_composition": {
			"main_hero_id": "character_default_a",
			"sub_hero_id": "character_default_b",
		},
		"content_progression": {
			"unlocked": {},
			"counters": {
				"runs_completed": 1,
				"enemy_defeated": {"enemy_default": 2},
			},
		},
	}
	system.set("_meta_payload", save_manager.meta_payload.duplicate(true))
	var first: Dictionary = system.call("commit_run_progress", {
		"runs_completed": 1,
		"enemy_defeated": {"enemy_default": 1},
	}) as Dictionary
	var first_unlocks: Dictionary = first.get("newly_unlocked", {}) as Dictionary
	_expect(bool(first.get("saved", false)), "valid run progress should save Meta")
	_expect(
		(first_unlocks.get("character", []) as Array) == ["character_locked"],
		"first completed rule evaluation should return the newly unlocked character once"
	)
	var saved_progression: Dictionary = save_manager.meta_payload.get(
		"content_progression",
		{}
	) as Dictionary
	var saved_unlocked: Dictionary = saved_progression.get("unlocked", {}) as Dictionary
	_expect(
		(saved_unlocked.get("character", []) as Array).count("character_locked") == 1,
		"Meta unlocked set should store a content id only once"
	)
	_expect(
		not (saved_unlocked.get("character", []) as Array).has(
			"character_default_a"
		),
		"default-open content should remain sparse instead of being copied to Meta"
	)

	var second: Dictionary = system.call("commit_run_progress", {}) as Dictionary
	var second_unlocks: Dictionary = second.get("newly_unlocked", {}) as Dictionary
	saved_progression = save_manager.meta_payload.get(
		"content_progression",
		{}
	) as Dictionary
	saved_unlocked = saved_progression.get("unlocked", {}) as Dictionary
	_expect(
		(second_unlocks.get("character", []) as Array).is_empty()
		and (saved_unlocked.get("character", []) as Array).count(
			"character_locked"
		) == 1,
		"re-evaluation should neither return nor record the same unlock twice"
	)
	_expect(
		String(
			(save_manager.meta_payload.get("hero_composition", {}) as Dictionary).get(
				"main_hero_id",
				""
			)
		) == "character_default_a",
		"progress commit should preserve unrelated Meta composition fields"
	)
	system.free()


func _fixture_system() -> Dictionary:
	var system: Node = CONTENT_UNLOCK_SCRIPT.new()
	var save_manager := FakeSaveManager.new()
	var entries: Dictionary = {
		"character": {
			"character_default_a": {
				"id": "character_default_a",
				"name_key": "character_default_a_name",
				"base_stats": {"max_hp": 100.0},
				"passive_id": "passive_default",
				"hero_skill_ids": ["skill_a", "skill_b"],
			},
			"character_default_b": {
				"id": "character_default_b",
				"name_key": "character_default_b_name",
				"default_unlocked": true,
			},
			"character_locked": {
				"id": "character_locked",
				"name_key": "character_locked_name",
				"desc_key": "character_locked_desc",
				"default_unlocked": false,
				"unlock_rule_id": "rule_character_all",
			},
		},
		"gear_mod": {
			"gear_mod_default": {
				"id": "gear_mod_default",
				"name_key": "gear_mod_default_name",
				"slot": "weapon",
				"rarity": "common",
				"max_rank": 5,
				"rank_modifiers": [],
			},
			"gear_mod_locked": {
				"id": "gear_mod_locked",
				"name_key": "gear_mod_locked_name",
				"default_unlocked": false,
				"unlock_rule_id": "rule_mod_any",
			},
		},
		"enemy": {
			"enemy_default": {
				"id": "enemy_default",
				"name_key": "enemy_default_name",
				"default_unlocked": "",
				"max_hp": "10",
				"move_speed": "100.0",
				"gold_value_multiplier": "1.0",
				"hit_radius": "12.0",
				"separation_radius": "8.0",
			},
		},
	}
	var rules: Dictionary = {
		"rule_character_all": {
			"id": "rule_character_all",
			"mode": "all",
			"conditions": [
				{"counter_id": "runs_completed", "target": 2},
				{
					"counter_id": "enemy_defeated",
					"subject_id": "enemy_default",
					"target": 3,
				},
			],
		},
		"rule_mod_any": {
			"id": "rule_mod_any",
			"mode": "any",
			"conditions": [
				{"counter_id": "runs_ended", "target": 5},
				{"counter_id": "enemy_defeated_total", "target": 9},
			],
		},
	}
	system.set("_entries_by_type", entries)
	system.set("_rules_by_id", rules)
	system.set("_meta_payload", {})
	system.set("_save_manager_override", save_manager)
	return {"system": system, "save_manager": save_manager}


func _entry_by_id(entries: Array, content_id: String) -> Dictionary:
	for raw_entry: Variant in entries:
		if (
			raw_entry is Dictionary
			and String((raw_entry as Dictionary).get("id", "")) == content_id
		):
			return raw_entry as Dictionary
	return {}


func _condition_matches(
	conditions: Array,
	counter_id: String,
	subject_id: String,
	current: int,
	pending: int,
	target: int
) -> bool:
	for raw_condition: Variant in conditions:
		if not raw_condition is Dictionary:
			continue
		var condition: Dictionary = raw_condition as Dictionary
		if (
			String(condition.get("counter_id", "")) == counter_id
			and String(condition.get("subject_id", "")) == subject_id
			and int(condition.get("current", -1)) == current
			and int(condition.get("pending", -1)) == pending
			and int(condition.get("target", -1)) == target
		):
			return true
	return false


func _condition_subject_name(
	conditions: Array,
	counter_id: String,
	subject_id: String
) -> String:
	for raw_condition: Variant in conditions:
		if not raw_condition is Dictionary:
			continue
		var condition: Dictionary = raw_condition as Dictionary
		if (
			String(condition.get("counter_id", "")) == counter_id
			and String(condition.get("subject_id", "")) == subject_id
		):
			return String(condition.get("subject_name_key", ""))
	return ""


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[ContentProgressionSmoke] %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("[ContentProgressionSmoke] ALL PASS")
		get_tree().quit(0)
		return
	print("[ContentProgressionSmoke] failed; failures=%d" % _failures.size())
	get_tree().quit(1)


class FakeSaveManager:
	extends RefCounted

	var meta_payload: Dictionary = {}
	var run_payload: Dictionary = {}
	var save_count: int = 0


	func has_save(_slot: String, kind: String) -> bool:
		if kind == "meta":
			return not meta_payload.is_empty()
		if kind == "run":
			return not run_payload.is_empty()
		return false


	func load(_slot: String, kind: String) -> Dictionary:
		if kind == "meta":
			return meta_payload.duplicate(true)
		if kind == "run":
			return run_payload.duplicate(true)
		return {}


	func load_envelope(_slot: String, kind: String) -> Dictionary:
		var payload: Dictionary = self.load(_slot, kind)
		if payload.is_empty() and not has_save(_slot, kind):
			return {}
		return {"payload": payload}


	func save(_slot: String, kind: String, payload: Dictionary) -> bool:
		if kind != "meta":
			return false
		meta_payload = payload.duplicate(true)
		save_count += 1
		return true
